import Cocoa
import AVFoundation

class AppDelegate: NSObject, NSApplicationDelegate {

    private var menubarController: MenubarController!
    private var hotkeyManager: HotkeyManager!
    private var audioRecorder: AudioRecorder!
    private var asrService: ASRService?
    private var pasteController: PasteController!
    private var floatingIndicator = FloatingIndicator()

    private var isRecording = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        menubarController = MenubarController()
        pasteController = PasteController()
        audioRecorder = AudioRecorder()

        hotkeyManager = HotkeyManager()
        hotkeyManager.onKeyDown = { [weak self] in self?.startRecording() }
        hotkeyManager.onKeyUp = { [weak self] in self?.stopRecordingAndTranscribe() }
        hotkeyManager.start()

        menubarController.onHotkeyChanged = { [weak self] in
            self?.hotkeyManager.reload()
        }

        menubarController.onModelsReady = { [weak self] in
            self?.startASR()
        }

        // 模型就绪 → 启动 ASR；缺模型或权限不全 → 弹设置窗口
        let needsSetup = !ASRService.modelsReady()
            || AVCaptureDevice.authorizationStatus(for: .audio) != .authorized
            || !AXIsProcessTrusted()

        if ASRService.modelsReady() {
            startASR()
        }

        if needsSetup {
            menubarController.showSettings()
        }

        // 静默检查更新（每天一次）
        UpdateChecker.checkOnLaunch()

        log("OwlWhisper 已启动")
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager?.stop()
        asrService?.stop()
    }

    // MARK: - ASR

    private func startASR() {
        guard asrService == nil else { return }
        let asr = ASRService()
        asr.onReady = { [weak self] modelName in
            self?.log("ASR 就绪: \(modelName)")
            self?.menubarController.setState(.ready)
        }
        asr.onError = { [weak self] message in
            self?.log("ASR 错误: \(message)")
            self?.menubarController.setState(.error)
        }
        asr.start()
        asrService = asr
    }

    // MARK: - 录音与转写

    private func startRecording() {
        guard !isRecording, asrService?.isReady == true else { return }

        isRecording = true
        menubarController.setState(.recording)
        floatingIndicator.setState(.recording)
        audioRecorder.startRecording()
        log("开始录音")

        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
            guard let self, self.isRecording else { return }
            self.log("录音超时 60s，自动停止")
            self.stopRecordingAndTranscribe()
        }
    }

    private func stopRecordingAndTranscribe() {
        guard isRecording else { return }
        isRecording = false
        menubarController.setState(.transcribing)
        floatingIndicator.setState(.transcribing)

        let audioData = audioRecorder.stopRecording()
        log("停止录音，音频 \(audioData.count) 字节")

        if audioData.isEmpty {
            menubarController.setState(.ready)
            floatingIndicator.setState(.hidden)
            return
        }

        asrService?.transcribe(audioData: audioData, sampleRate: 16000) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let r):
                    if r.hasSpeech, !r.text.isEmpty {
                        self.pasteController.pasteText(r.text)
                        self.log("转写: \"\(r.text)\" (\(r.durationMs)ms)")
                    } else {
                        self.log("无语音内容")
                    }
                case .failure(let error):
                    self.log("转写失败: \(error.localizedDescription)")
                }
                self.menubarController.setState(.ready)
                self.floatingIndicator.setState(.hidden)
            }
        }
    }

    private func log(_ message: String) {
        NSLog("[OwlWhisper] %@", message)
    }
}
