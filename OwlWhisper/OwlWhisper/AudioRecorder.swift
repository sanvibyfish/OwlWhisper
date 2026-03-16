import AVFoundation

/// 麦克风录音器。
/// 使用 AVAudioEngine 录制 16kHz mono float32 PCM 音频。
class AudioRecorder {

    private let engine = AVAudioEngine()
    private var buffer = Data()
    private let lock = NSLock()
    private let targetSampleRate: Double = 16000
    private(set) var lastError: Error?

    /// 开始录音，音频数据累积到内部 buffer。
    /// 失败时抛出错误（调用方应展示给用户）。
    func startRecording() throws {
        lock.lock()
        buffer = Data()
        lastError = nil
        lock.unlock()

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // 目标格式：16kHz mono float32
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioRecorderError.formatCreationFailed
        }

        // 如果输入格式与目标不同，使用转换器
        let converter: AVAudioConverter?
        if inputFormat.sampleRate != targetSampleRate || inputFormat.channelCount != 1 {
            guard let conv = AVAudioConverter(from: inputFormat, to: targetFormat) else {
                throw AudioRecorderError.converterCreationFailed(
                    from: inputFormat.description, to: targetFormat.description)
            }
            converter = conv
        } else {
            converter = nil
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] pcmBuffer, _ in
            guard let self else { return }

            let outputBuffer: AVAudioPCMBuffer
            if let converter {
                // 计算输出帧数（按采样率比例换算）
                let ratio = targetSampleRate / inputFormat.sampleRate
                let outputFrameCount = AVAudioFrameCount(Double(pcmBuffer.frameLength) * ratio)
                guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCount) else {
                    NSLog("[AudioRecorder] PCM buffer 分配失败 (capacity=%d)", outputFrameCount)
                    self.lock.lock()
                    self.lastError = AudioRecorderError.formatCreationFailed
                    self.lock.unlock()
                    return
                }

                var error: NSError?
                // 用 hasProvidedData 标记避免 converter 重复读取同一 buffer
                var hasProvidedData = false
                converter.convert(to: converted, error: &error) { _, outStatus in
                    if hasProvidedData {
                        outStatus.pointee = .noDataNow
                        return nil
                    }
                    hasProvidedData = true
                    outStatus.pointee = .haveData
                    return pcmBuffer
                }
                if let error {
                    NSLog("[AudioRecorder] 音频转换失败: %@", error.localizedDescription)
                    self.lock.lock()
                    self.lastError = error
                    self.lock.unlock()
                    return
                }
                outputBuffer = converted
            } else {
                outputBuffer = pcmBuffer
            }

            // 提取 float32 数据
            guard let channelData = outputBuffer.floatChannelData else {
                NSLog("[AudioRecorder] floatChannelData 为 nil，丢弃帧")
                self.lock.lock()
                self.lastError = AudioRecorderError.formatCreationFailed
                self.lock.unlock()
                return
            }
            let frameCount = Int(outputBuffer.frameLength)
            let data = Data(bytes: channelData[0], count: frameCount * MemoryLayout<Float>.size)

            self.lock.lock()
            self.buffer.append(data)
            self.lock.unlock()
        }

        do {
            try engine.start()
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            NSLog("[AudioRecorder] 启动失败: %@", error.localizedDescription)
            throw error
        }
    }

    /// 停止录音，返回累积的 float32 PCM 数据和录音期间的错误（如有）。
    func stopRecording() -> (data: Data, error: Error?) {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        lock.lock()
        let result = buffer
        let error = lastError
        buffer = Data()
        lastError = nil
        lock.unlock()

        if let error {
            NSLog("[AudioRecorder] 录音期间发生错误: %@", error.localizedDescription)
        }
        return (result, error)
    }

    enum AudioRecorderError: LocalizedError {
        case formatCreationFailed
        case converterCreationFailed(from: String, to: String)

        var errorDescription: String? {
            switch self {
            case .formatCreationFailed:
                return "无法创建目标音频格式 (16kHz mono float32)"
            case .converterCreationFailed(let from, let to):
                return "无法创建音频转换器: \(from) -> \(to)"
            }
        }
    }
}
