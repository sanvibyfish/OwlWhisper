import Foundation

/// 原生 ASR 服务，直接调用 sherpa-onnx C API。
class ASRService {

    struct TranscribeResult {
        let text: String
        let hasSpeech: Bool
        let durationMs: Int
    }

    var onReady: ((String) -> Void)?
    var onError: ((String) -> Void)?
    /// 线程安全：仅在 main thread 读写
    private(set) var isReady = false

    private let queue = DispatchQueue(label: "com.sanvi.OwlWhisper.asr")
    private var recognizer: OpaquePointer?
    private var vad: OpaquePointer?
    private var punctuation: OpaquePointer?
    private var modelName = ""
    private let vadWindowSize: Int32 = 512
    private var generation = 0  // 仅在 queue 上访问，用于检测 stop() 导致的指针失效

    /// 空闲超时后自动卸载模型释放内存（秒）
    private static let idleTimeout: TimeInterval = 60
    private var idleTimer: DispatchWorkItem?

    /// 验证模型文件并标记服务就绪（不加载到内存，首次使用时按需加载）。
    func start() {
        queue.async { [weak self] in
            self?.verifyModels()
        }
    }

    /// 预加载模型到内存（非阻塞）。在录音开始时调用，录音期间完成加载。
    func preload() {
        queue.async { [weak self] in
            guard let self else { return }
            self.idleTimer?.cancel()
            self.ensureLoaded()
        }
    }

    func stop() {
        // 立即在主线程置 false，防止 stop() 之后仍有 transcribe 调用通过 guard
        DispatchQueue.main.async { [weak self] in self?.isReady = false }
        queue.async { [weak self] in
            guard let self else { return }
            self.idleTimer?.cancel()
            self.idleTimer = nil
            self.generation += 1
            self.cleanupModels()
        }
    }

    /// 清理已加载的模型（失败路径用）
    private func cleanupModels() {
        if let r = recognizer { SherpaOnnxDestroyOfflineRecognizer(r); recognizer = nil }
        if let v = vad { SherpaOnnxDestroyVoiceActivityDetector(v); vad = nil }
        if let p = punctuation { SherpaOnnxDestroyOfflinePunctuation(p); punctuation = nil }
    }

    func transcribe(audioData: Data, sampleRate: Int, completion: @escaping (Result<TranscribeResult, Error>) -> Void) {
        queue.async { [weak self] in
            guard let self else {
                completion(.failure(NSError(domain: "ASRService", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "ASR 已释放"])))
                return
            }

            // 取消空闲卸载计时器，按需加载模型
            self.idleTimer?.cancel()
            self.ensureLoaded()

            guard let recognizer = self.recognizer, let vad = self.vad else {
                completion(.failure(NSError(domain: "ASRService", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "ASR 模型加载失败"])))
                return
            }
            let gen = self.generation

            let t0 = CFAbsoluteTimeGetCurrent()

            var samples = audioData.withUnsafeBytes { buf -> [Float] in
                let ptr = buf.bindMemory(to: Float.self)
                return Array(ptr)
            }

            // 末尾补 500ms 静音，防止 VAD 截断最后一个字
            let silencePadding = Int(16000 * 0.5)  // 500ms @ 16kHz
            samples.append(contentsOf: [Float](repeating: 0, count: silencePadding))
            let floatCount = samples.count

            // VAD: 提取语音片段
            SherpaOnnxVoiceActivityDetectorReset(vad)

            var offset = 0
            while offset + Int(self.vadWindowSize) <= floatCount {
                samples.withUnsafeBufferPointer { buf in
                    SherpaOnnxVoiceActivityDetectorAcceptWaveform(
                        vad, buf.baseAddress! + offset, self.vadWindowSize)
                }
                offset += Int(self.vadWindowSize)
            }

            // 补零处理剩余样本
            if offset < floatCount {
                var padded = [Float](repeating: 0, count: Int(self.vadWindowSize))
                let remaining = floatCount - offset
                samples.withUnsafeBufferPointer { buf in
                    for i in 0..<remaining {
                        padded[i] = buf[offset + i]
                    }
                }
                padded.withUnsafeBufferPointer { buf in
                    SherpaOnnxVoiceActivityDetectorAcceptWaveform(
                        vad, buf.baseAddress!, self.vadWindowSize)
                }
            }

            SherpaOnnxVoiceActivityDetectorFlush(vad)

            // 收集语音片段
            var speechSamples = [Float]()
            while SherpaOnnxVoiceActivityDetectorEmpty(vad) == 0 {
                if let segment = SherpaOnnxVoiceActivityDetectorFront(vad) {
                    let n = Int(segment.pointee.n)
                    if n > 0, let ptr = segment.pointee.samples {
                        speechSamples.append(contentsOf: UnsafeBufferPointer(start: ptr, count: n))
                    }
                    SherpaOnnxDestroySpeechSegment(segment)
                }
                SherpaOnnxVoiceActivityDetectorPop(vad)
            }

            if speechSamples.isEmpty {
                let ms = Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)
                self.scheduleIdleUnload()
                completion(.success(TranscribeResult(text: "", hasSpeech: false, durationMs: ms)))
                return
            }

            // 检查 stop() 是否在 VAD 处理期间被调用
            guard self.generation == gen else {
                completion(.failure(NSError(domain: "ASRService", code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "ASR 已停止"])))
                return
            }

            // 离线识别
            guard let stream = SherpaOnnxCreateOfflineStream(recognizer) else {
                completion(.failure(NSError(domain: "ASRService", code: -3,
                    userInfo: [NSLocalizedDescriptionKey: "创建 stream 失败"])))
                return
            }
            defer { SherpaOnnxDestroyOfflineStream(stream) }

            speechSamples.withUnsafeBufferPointer { buf in
                SherpaOnnxAcceptWaveformOffline(stream, Int32(sampleRate), buf.baseAddress!, Int32(buf.count))
            }
            SherpaOnnxDecodeOfflineStream(recognizer, stream)

            var text = ""
            if let result = SherpaOnnxGetOfflineStreamResult(stream) {
                if let cText = result.pointee.text {
                    text = String(cString: cText).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                SherpaOnnxDestroyOfflineRecognizerResult(result)
            } else {
                NSLog("[ASRService] SherpaOnnxGetOfflineStreamResult 返回 nil，可能模型状态异常")
            }

            // 标点恢复（延迟加载标点模型：首次走到这里时才加载）
            if !text.isEmpty {
                if self.punctuation == nil { self.ensurePunctuationLoaded() }
            }
            if !text.isEmpty, let punct = self.punctuation {
                guard let cInput = strdup(text) else {
                    NSLog("[ASRService] strdup 失败（内存不足），跳过标点恢复")
                    let ms = Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)
                    completion(.success(TranscribeResult(text: text, hasSpeech: true, durationMs: ms)))
                    return
                }
                defer { free(cInput) }
                if let cResult = SherpaOfflinePunctuationAddPunct(punct, cInput) {
                    text = String(cString: cResult)
                    SherpaOfflinePunctuationFreeText(cResult)
                } else {
                    NSLog("[ASRService] 标点推理失败（SherpaOfflinePunctuationAddPunct 返回 nil），使用无标点文本")
                }
            }

            let ms = Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)
            NSLog("[ASRService] 转写完成: \"%@\" (%dms, %d 语音样本)", text, ms, speechSamples.count)
            self.scheduleIdleUnload()
            completion(.success(TranscribeResult(text: text, hasSpeech: true, durationMs: ms)))
        }
    }

    // MARK: - 延迟加载与空闲卸载

    /// 仅验证模型文件存在，不加载到内存。
    private func verifyModels() {
        let modelsDir = findModelsDir()
        guard !modelsDir.isEmpty else {
            NSLog("[ASRService] 未找到 models 目录")
            DispatchQueue.main.async { [weak self] in self?.onError?("未找到 models 目录，请先运行 scripts/setup.sh") }
            return
        }

        let fm = FileManager.default
        let contents: [String]
        do {
            contents = try fm.contentsOfDirectory(atPath: modelsDir)
        } catch {
            NSLog("[ASRService] 读取模型目录失败: %@", error.localizedDescription)
            DispatchQueue.main.async { [weak self] in self?.onError?("读取模型目录失败: \(error.localizedDescription)") }
            return
        }

        guard let asrDirName = contents.first(where: { $0.hasPrefix("sherpa-onnx-fire-red-asr") }) else {
            NSLog("[ASRService] 未找到 FireRedASR 模型")
            DispatchQueue.main.async { [weak self] in self?.onError?("未找到 FireRedASR 模型") }
            return
        }

        modelName = asrDirName
        let name = asrDirName
        NSLog("[ASRService] 模型文件就绪（延迟加载）: %@", name)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isReady = true
            self.onReady?(name)
        }
    }

    /// 确保核心模型（ASR + VAD）已加载到内存（必须在 queue 上调用）。
    private func ensureLoaded() {
        guard recognizer == nil else { return }
        let t0 = CFAbsoluteTimeGetCurrent()
        NSLog("[ASRService] 按需加载模型到内存...")
        loadModels()
        let elapsed = Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)
        NSLog("[ASRService] 模型加载耗时 %dms", elapsed)
    }

    /// 按需加载标点模型（必须在 queue 上调用）。
    private func ensurePunctuationLoaded() {
        let modelsDir = findModelsDir()
        guard !modelsDir.isEmpty else { return }
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: modelsDir),
              let punctDirName = contents.first(where: { $0.hasPrefix("sherpa-onnx-punct-ct-transformer") }) else {
            return
        }
        let punctModel = (modelsDir as NSString)
            .appendingPathComponent(punctDirName)
            .appending("/model.onnx")
        guard fm.fileExists(atPath: punctModel) else { return }

        NSLog("[ASRService] 按需加载标点模型...")
        let t0 = CFAbsoluteTimeGetCurrent()
        self.punctuation = createPunctuation(modelPath: punctModel)
        let elapsed = Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)
        if self.punctuation != nil {
            NSLog("[ASRService] 标点模型已加载 (%dms)", elapsed)
        } else {
            NSLog("[ASRService] 标点模型加载失败，将不加标点")
        }
    }

    /// 转写完成后启动空闲计时器，超时后卸载模型释放内存（必须在 queue 上调用）。
    private func scheduleIdleUnload() {
        idleTimer?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            NSLog("[ASRService] 空闲 %.0f 秒，卸载模型释放内存", Self.idleTimeout)
            self.generation += 1
            self.cleanupModels()
        }
        self.idleTimer = work
        queue.asyncAfter(deadline: .now() + Self.idleTimeout, execute: work)
    }

    // MARK: - 模型加载

    private func loadModels() {
        let modelsDir = findModelsDir()
        guard !modelsDir.isEmpty else {
            NSLog("[ASRService] 未找到 models 目录")
            DispatchQueue.main.async { [weak self] in self?.onError?("未找到 models 目录，请先运行 scripts/setup.sh") }
            return
        }

        NSLog("[ASRService] 模型目录: %@", modelsDir)

        // 查找 FireRedASR 模型
        let fm = FileManager.default
        let contents: [String]
        do {
            contents = try fm.contentsOfDirectory(atPath: modelsDir)
        } catch {
            NSLog("[ASRService] 读取模型目录失败: %@", error.localizedDescription)
            DispatchQueue.main.async { [weak self] in self?.onError?("读取模型目录失败: \(error.localizedDescription)") }
            return
        }

        guard let asrDirName = contents.first(where: { $0.hasPrefix("sherpa-onnx-fire-red-asr") }) else {
            NSLog("[ASRService] 未找到 FireRedASR 模型")
            DispatchQueue.main.async { [weak self] in self?.onError?("未找到 FireRedASR 模型") }
            return
        }

        let asrDir = (modelsDir as NSString).appendingPathComponent(asrDirName)
        modelName = asrDirName

        // 定位模型文件（优先 int8）
        var encoder = (asrDir as NSString).appendingPathComponent("encoder.int8.onnx")
        if !fm.fileExists(atPath: encoder) {
            encoder = (asrDir as NSString).appendingPathComponent("encoder.onnx")
        }
        var decoder = (asrDir as NSString).appendingPathComponent("decoder.int8.onnx")
        if !fm.fileExists(atPath: decoder) {
            decoder = (asrDir as NSString).appendingPathComponent("decoder.onnx")
        }
        let tokens = (asrDir as NSString).appendingPathComponent("tokens.txt")

        for f in [encoder, decoder, tokens] {
            guard fm.fileExists(atPath: f) else {
                NSLog("[ASRService] 模型文件不存在: %@", f)
                DispatchQueue.main.async { [weak self] in self?.onError?("模型文件不存在: \(f)") }
                return
            }
        }

        // 创建离线识别器
        NSLog("[ASRService] 加载 ASR 模型: %@", asrDirName)
        let rec = createRecognizer(encoder: encoder, decoder: decoder, tokens: tokens)
        guard let rec else {
            NSLog("[ASRService] 创建识别器失败")
            DispatchQueue.main.async { [weak self] in self?.onError?("创建识别器失败") }
            return
        }
        self.recognizer = rec

        // 创建 VAD
        let vadModel = (modelsDir as NSString).appendingPathComponent("silero_vad.onnx")
        guard fm.fileExists(atPath: vadModel) else {
            NSLog("[ASRService] VAD 模型不存在: %@", vadModel)
            cleanupModels()
            DispatchQueue.main.async { [weak self] in self?.onError?("VAD 模型不存在") }
            return
        }

        NSLog("[ASRService] 加载 VAD 模型...")
        let v = createVAD(modelPath: vadModel)
        guard let v else {
            NSLog("[ASRService] 创建 VAD 失败")
            cleanupModels()
            DispatchQueue.main.async { [weak self] in self?.onError?("创建 VAD 失败") }
            return
        }
        self.vad = v

        // 标点恢复模型延迟到首次转写出文本时加载，加快 preload 速度
        NSLog("[ASRService] 核心模型已加载到内存: %@（标点模型将在首次使用时加载）", modelName)
    }

    // sherpa-onnx Create* 函数在调用时拷贝字符串，defer { free } 是安全的
    private func createRecognizer(encoder: String, decoder: String, tokens: String) -> OpaquePointer? {
        guard let cEncoder = strdup(encoder) else {
            NSLog("[ASRService] strdup 失败（内存不足）"); return nil
        }
        guard let cDecoder = strdup(decoder) else {
            free(cEncoder); return nil
        }
        guard let cTokens = strdup(tokens) else {
            free(cEncoder); free(cDecoder); return nil
        }
        defer { free(cEncoder); free(cDecoder); free(cTokens) }

        var config = SherpaOnnxOfflineRecognizerConfig()
        config.feat_config.sample_rate = 16000
        config.feat_config.feature_dim = 80
        config.model_config.fire_red_asr.encoder = UnsafePointer(cEncoder)
        config.model_config.fire_red_asr.decoder = UnsafePointer(cDecoder)
        config.model_config.tokens = UnsafePointer(cTokens)
        config.model_config.num_threads = 2
        config.model_config.debug = 0
        guard let cProvider = strdup("cpu") else { return nil }
        config.model_config.provider = UnsafePointer(cProvider)
        defer { free(cProvider) }

        return SherpaOnnxCreateOfflineRecognizer(&config)
    }

    private func createVAD(modelPath: String) -> OpaquePointer? {
        guard let cModel = strdup(modelPath) else {
            NSLog("[ASRService] strdup 失败（内存不足）")
            return nil
        }
        defer { free(cModel) }

        var config = SherpaOnnxVadModelConfig()
        config.silero_vad.model = UnsafePointer(cModel)
        config.silero_vad.threshold = 0.5
        config.silero_vad.min_silence_duration = 0.25
        config.silero_vad.min_speech_duration = 0.25
        config.silero_vad.window_size = vadWindowSize
        config.sample_rate = 16000
        config.num_threads = 1
        guard let cVadProvider = strdup("cpu") else { return nil }
        config.provider = UnsafePointer(cVadProvider)
        defer { free(cVadProvider) }

        return SherpaOnnxCreateVoiceActivityDetector(&config, 60.0)
    }

    private func createPunctuation(modelPath: String) -> OpaquePointer? {
        guard let cModel = strdup(modelPath) else {
            NSLog("[ASRService] strdup 失败（内存不足）")
            return nil
        }
        defer { free(cModel) }

        var config = SherpaOnnxOfflinePunctuationConfig()
        config.model.ct_transformer = UnsafePointer(cModel)
        config.model.num_threads = 1
        config.model.debug = 0
        guard let cProvider = strdup("cpu") else { return nil }
        config.model.provider = UnsafePointer(cProvider)
        defer { free(cProvider) }

        return SherpaOnnxCreateOfflinePunctuation(&config)
    }

    // MARK: - 模型路径

    /// 检查模型文件是否就绪（供 Onboarding 使用）。
    static func modelsReady() -> Bool {
        let dir = findModelsDirStatic()
        guard !dir.isEmpty else { return false }
        let fm = FileManager.default
        let contents: [String]
        do {
            contents = try fm.contentsOfDirectory(atPath: dir)
        } catch {
            NSLog("[ASRService] modelsReady: 读取模型目录失败: %@", error.localizedDescription)
            return false
        }
        guard contents.contains(where: { $0.hasPrefix("sherpa-onnx-fire-red-asr") }) else { return false }
        return fm.fileExists(atPath: (dir as NSString).appendingPathComponent("silero_vad.onnx"))
    }

    /// 返回模型应存放的目录（不存在时也返回路径，供下载使用）。
    static func modelsDirectory() -> String {
        let existing = findModelsDirStatic()
        if !existing.isEmpty { return existing }

        // 默认：~/Library/Application Support/OwlWhisper/models
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("OwlWhisper/models").path
    }

    private static func findModelsDirStatic() -> String {
        let fm = FileManager.default

        // 1. Bundle Resources（Release 打包模式）
        if let resourcePath = Bundle.main.resourcePath {
            let bundleModels = (resourcePath as NSString).appendingPathComponent("models")
            if fm.fileExists(atPath: bundleModels) { return bundleModels }
        }

        // 2. Application Support（用户下载的模型）
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appSupportModels = appSupport.appendingPathComponent("OwlWhisper/models").path
        if fm.fileExists(atPath: appSupportModels) { return appSupportModels }

        return ""
    }

    private func findModelsDir() -> String { Self.findModelsDirStatic() }
}
