import Cocoa
import AVFoundation

private func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

class SettingsWindowController: NSObject, NSWindowDelegate {

    var onHotkeyChanged: (() -> Void)?
    var onModelsReady: (() -> Void)?

    private var window: NSWindow?
    private var guideIcon: NSImageView!
    private var guideTitle: NSTextField!
    private var guideDesc: NSTextField!
    private var hotkeyLabel: NSTextField!
    private var hotkeyHint: NSTextField!
    private var hotkeyArea: NSView!
    private var micStatusIcon: NSImageView!
    private var micStatusLabel: NSTextField!
    private var micGrantBtn: NSButton!
    private var accStatusIcon: NSImageView!
    private var accStatusLabel: NSTextField!
    private var accGrantBtn: NSButton!
    private var modelStatusIcon: NSImageView!
    private var modelStatusLabel: NSTextField!
    private var modelActionBtn: NSButton!
    private var modelProgressBar: NSProgressIndicator!
    private var eventMonitor: Any?
    private var isRecording = false
    private var modKeyCode: UInt16?
    private var modTimer: Timer?
    private var pollTimer: Timer?

    private var downloader: ModelDownloader?
    private var downloadTaskHandle: Task<Void, Never>?

    // MARK: - Show

    func show() {
        if let w = window, w.isVisible {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            refreshStatus()
            return
        }

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 10), // height auto-sized by stack
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.backgroundColor = .clear

        let vfx = NSVisualEffectView()
        vfx.blendingMode = .behindWindow
        vfx.material = .windowBackground
        vfx.state = .followsWindowActiveState
        vfx.translatesAutoresizingMaskIntoConstraints = false
        w.contentView!.addSubview(vfx)
        NSLayoutConstraint.activate([
            vfx.topAnchor.constraint(equalTo: w.contentView!.topAnchor),
            vfx.bottomAnchor.constraint(equalTo: w.contentView!.bottomAnchor),
            vfx.leadingAnchor.constraint(equalTo: w.contentView!.leadingAnchor),
            vfx.trailingAnchor.constraint(equalTo: w.contentView!.trailingAnchor),
        ])

        // 主 stack
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 28, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        vfx.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: vfx.topAnchor),
            stack.bottomAnchor.constraint(equalTo: vfx.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: vfx.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: vfx.trailingAnchor),
        ])

        let innerW: CGFloat = 272  // 320 - 24*2

        // ── 引导区 ──
        guideIcon = makeImageView(size: 28)
        stack.addArrangedSubview(guideIcon)

        guideTitle = makeLabel(font: .boldSystemFont(ofSize: 14), alignment: .center)
        stack.addArrangedSubview(guideTitle)

        guideDesc = makeLabel(font: .systemFont(ofSize: 11), alignment: .center, color: .secondaryLabelColor)
        stack.addArrangedSubview(guideDesc)

        stack.setCustomSpacing(10, after: guideDesc)

        // ── 快捷键区 ──
        hotkeyArea = NSView()
        hotkeyArea.wantsLayer = true
        hotkeyArea.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.5).cgColor
        hotkeyArea.layer?.cornerRadius = 10
        hotkeyArea.layer?.borderWidth = 1.5
        hotkeyArea.layer?.borderColor = NSColor.separatorColor.cgColor
        hotkeyArea.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(hotkeyArea)
        NSLayoutConstraint.activate([
            hotkeyArea.widthAnchor.constraint(equalToConstant: innerW),
            hotkeyArea.heightAnchor.constraint(equalToConstant: 42),
        ])

        hotkeyLabel = makeLabel(font: .monospacedSystemFont(ofSize: 18, weight: .medium), alignment: .center)
        hotkeyLabel.stringValue = HotkeyConfig.current.displayName
        hotkeyLabel.translatesAutoresizingMaskIntoConstraints = false
        hotkeyArea.addSubview(hotkeyLabel)
        NSLayoutConstraint.activate([
            hotkeyLabel.centerXAnchor.constraint(equalTo: hotkeyArea.centerXAnchor),
            hotkeyLabel.centerYAnchor.constraint(equalTo: hotkeyArea.centerYAnchor),
        ])

        let click = NSClickGestureRecognizer(target: self, action: #selector(hotkeyAreaClicked))
        hotkeyArea.addGestureRecognizer(click)

        hotkeyHint = makeLabel(font: .systemFont(ofSize: 10), alignment: .center, color: .tertiaryLabelColor)
        hotkeyHint.stringValue = L("hotkey.hint")
        stack.addArrangedSubview(hotkeyHint)

        stack.setCustomSpacing(10, after: hotkeyHint)

        // ── 状态行 ──
        let (micRow, micIc, micLbl, micBtn) = makeStatusRow(
            name: L("status.microphone"), action: #selector(openMicSettings), width: innerW)
        micStatusIcon = micIc; micStatusLabel = micLbl; micGrantBtn = micBtn
        stack.addArrangedSubview(micRow)

        let (accRow, accIc, accLbl, accBtn) = makeStatusRow(
            name: L("status.paste"), action: #selector(openAccSettings), width: innerW)
        accStatusIcon = accIc; accStatusLabel = accLbl; accGrantBtn = accBtn
        stack.addArrangedSubview(accRow)

        let (modRow, modIc, modLbl, modBtn) = makeStatusRow(
            name: L("status.model"), action: #selector(startDownload), width: innerW)
        modelStatusIcon = modIc; modelStatusLabel = modLbl; modelActionBtn = modBtn
        modelActionBtn.title = L("status.download")
        stack.addArrangedSubview(modRow)

        // 进度条
        modelProgressBar = NSProgressIndicator()
        modelProgressBar.style = .bar
        modelProgressBar.minValue = 0; modelProgressBar.maxValue = 1
        modelProgressBar.isIndeterminate = false
        modelProgressBar.isHidden = true
        modelProgressBar.controlSize = .small
        modelProgressBar.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(modelProgressBar)
        modelProgressBar.widthAnchor.constraint(equalToConstant: innerW).isActive = true

        // ── 语言 ──
        let langRow = makeLangRow(width: innerW)
        stack.addArrangedSubview(langRow)

        // ── 检查更新 ──
        let updateBtn = NSButton(title: L("update.check"), target: self, action: #selector(checkUpdate))
        updateBtn.bezelStyle = .rounded
        updateBtn.controlSize = .small
        updateBtn.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(updateBtn)
        updateBtn.widthAnchor.constraint(equalToConstant: innerW).isActive = true

        stack.setCustomSpacing(10, after: updateBtn)

        // ── 底部信息 ──
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        let info = makeLabel(font: .systemFont(ofSize: 9), alignment: .center, color: .quaternaryLabelColor)
        info.stringValue = "OwlWhisper v\(version) (\(build)) · by Sanvi"
        stack.addArrangedSubview(info)

        refreshStatus()

        pollTimer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refreshStatus()
        }
        RunLoop.current.add(pollTimer!, forMode: .common)

        window = w
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        if !ASRService.modelsReady() && downloader == nil {
            startDownload()
        }
    }

    // MARK: - UI Builders

    private func makeStatusRow(name: String, action: Selector, width: CGFloat)
        -> (NSView, NSImageView, NSTextField, NSButton) {

        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: width).isActive = true
        row.heightAnchor.constraint(equalToConstant: 20).isActive = true

        let icon = makeImageView(size: 16)
        icon.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(icon)

        let label = makeLabel(font: .systemFont(ofSize: 12))
        label.stringValue = name
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        row.addSubview(label)

        let status = makeLabel(font: .systemFont(ofSize: 12), alignment: .right)
        status.translatesAutoresizingMaskIntoConstraints = false
        status.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.addSubview(status)

        let btn = NSButton(title: L("status.authorize"), target: self, action: action)
        btn.bezelStyle = .rounded
        btn.controlSize = .mini
        btn.isHidden = true
        btn.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(btn)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            icon.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),

            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            label.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            btn.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            btn.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            btn.widthAnchor.constraint(greaterThanOrEqualToConstant: 48),

            status.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            status.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])

        return (row, icon, status, btn)
    }

    private func makeLangRow(width: CGFloat) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: width).isActive = true
        row.heightAnchor.constraint(equalToConstant: 22).isActive = true

        let icon = makeImageView(size: 16)
        icon.image = NSImage(systemSymbolName: "globe", accessibilityDescription: nil)
        icon.contentTintColor = .secondaryLabelColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(icon)

        let label = makeLabel(font: .systemFont(ofSize: 12))
        label.stringValue = L("settings.language")
        label.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(label)

        let popup = NSPopUpButton()
        popup.controlSize = .small
        popup.font = .systemFont(ofSize: 11)
        popup.addItems(withTitles: ["English", "中文"])
        let lang = UserDefaults.standard.stringArray(forKey: "AppleLanguages")?.first ?? "en"
        popup.selectItem(at: lang.hasPrefix("zh") ? 1 : 0)
        popup.target = self
        popup.action = #selector(languageChanged(_:))
        popup.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(popup)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            icon.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),

            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            label.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            popup.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            popup.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            popup.widthAnchor.constraint(equalToConstant: 95),
        ])

        return row
    }

    private func makeLabel(font: NSFont, alignment: NSTextAlignment = .left, color: NSColor = .labelColor) -> NSTextField {
        let l = NSTextField(labelWithString: "")
        l.font = font
        l.alignment = alignment
        l.textColor = color
        l.lineBreakMode = .byTruncatingTail
        return l
    }

    private func makeImageView(size: CGFloat) -> NSImageView {
        let iv = NSImageView()
        iv.imageScaling = .scaleProportionallyUpOrDown
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.widthAnchor.constraint(equalToConstant: size).isActive = true
        iv.heightAnchor.constraint(equalToConstant: size).isActive = true
        return iv
    }

    // MARK: - Status

    private func refreshStatus() {
        guard micStatusLabel != nil else { return }

        let micOK = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        setStatus(icon: micStatusIcon, label: micStatusLabel, btn: micGrantBtn, ok: micOK)

        let accOK = AXIsProcessTrusted()
        setStatus(icon: accStatusIcon, label: accStatusLabel, btn: accGrantBtn, ok: accOK)

        if downloader == nil {
            let modelOK = ASRService.modelsReady()
            setStatus(icon: modelStatusIcon, label: modelStatusLabel, btn: modelActionBtn, ok: modelOK,
                      okText: L("status.ready"), failText: L("status.notDownloaded"))
        }

        updateGuide()
    }

    private func updateGuide() {
        let micOK = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let accOK = AXIsProcessTrusted()
        let modelOK = ASRService.modelsReady()
        let allOK = micOK && accOK && modelOK && downloader == nil

        if allOK {
            guideIcon.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
            guideIcon.contentTintColor = .systemGreen
            guideTitle.stringValue = L("guide.allReady")
            guideDesc.stringValue = L("guide.allReady.desc")
        } else if downloader != nil {
            guideIcon.image = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: nil)
            guideIcon.contentTintColor = .systemBlue
            guideTitle.stringValue = L("guide.preparing")
            guideDesc.stringValue = L("guide.preparing.desc")
        } else if !modelOK {
            guideIcon.image = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: nil)
            guideIcon.contentTintColor = .systemOrange
            guideTitle.stringValue = L("guide.needModel")
            guideDesc.stringValue = L("guide.needModel.desc")
        } else {
            guideIcon.image = NSImage(systemSymbolName: "gearshape.circle.fill", accessibilityDescription: nil)
            guideIcon.contentTintColor = .systemOrange
            guideTitle.stringValue = L("guide.needSetup")
            guideDesc.stringValue = L("guide.needSetup.desc")
        }
    }

    private func setStatus(icon: NSImageView, label: NSTextField, btn: NSButton, ok: Bool,
                           okText: String = L("status.authorized"), failText: String = L("status.unauthorized")) {
        if ok {
            icon.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
            icon.contentTintColor = .systemGreen
            label.stringValue = okText
            label.textColor = .secondaryLabelColor
            label.isHidden = false
            btn.isHidden = true
        } else {
            icon.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: nil)
            icon.contentTintColor = .systemRed
            label.isHidden = true
            btn.isHidden = false
        }
    }

    // MARK: - Model Download

    @objc private func startDownload() {
        let modelsDir = ASRService.modelsDirectory()
        do {
            try FileManager.default.createDirectory(atPath: modelsDir, withIntermediateDirectories: true)
        } catch {
            modelStatusLabel.stringValue = "\(L("download.dirFailed")): \(error.localizedDescription)"
            modelStatusLabel.textColor = .systemRed
            return
        }

        modelActionBtn.isHidden = true
        modelProgressBar.isHidden = false
        modelProgressBar.doubleValue = 0
        modelStatusLabel.stringValue = L("download.preparing")
        modelStatusLabel.textColor = .secondaryLabelColor
        modelStatusIcon.image = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: nil)
        modelStatusIcon.contentTintColor = .systemBlue
        updateGuide()

        let dl = ModelDownloader()
        self.downloader = dl

        downloadTaskHandle = Task { [weak self] in
            do {
                try await self?.downloadASRModel(downloader: dl, modelsDir: modelsDir)
                try await self?.downloadPunctModel(downloader: dl, modelsDir: modelsDir)
                try await self?.downloadVADModel(downloader: dl, modelsDir: modelsDir)
                await MainActor.run { self?.downloadComplete() }
            } catch {
                await MainActor.run {
                    guard let self else { return }
                    self.downloader = nil
                    self.downloadTaskHandle = nil
                    self.modelProgressBar.isHidden = true
                    self.modelStatusLabel.stringValue = L("download.failed")
                    self.modelStatusLabel.textColor = .systemRed
                    self.modelStatusIcon.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: nil)
                    self.modelStatusIcon.contentTintColor = .systemRed
                    self.modelActionBtn.title = L("status.retry")
                    self.modelActionBtn.isHidden = false
                    self.updateGuide()
                }
            }
        }
    }

    private static let asrTarSize: Int64 = 838_000_000
    private static let punctTarSize: Int64 = 270_000_000

    private func downloadASRModel(downloader: ModelDownloader, modelsDir: String) async throws {
        let name = "sherpa-onnx-fire-red-asr2-zh_en-int8-2026-02-26"
        let dir = (modelsDir as NSString).appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: dir) { return }

        let url = URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/\(name).tar.bz2")!
        let dest = URL(fileURLWithPath: (modelsDir as NSString).appendingPathComponent("\(name).tar.bz2"))
        let known = Self.asrTarSize

        try await downloader.download(from: url, to: dest) { [weak self] p in
            DispatchQueue.main.async {
                guard let self else { return }
                let total = p.totalBytes > 0 ? p.totalBytes : known
                self.modelProgressBar.doubleValue = min(Double(p.bytesDownloaded) / Double(total), 1) * 0.75
                self.modelStatusLabel.stringValue = "\(L("download.asr")) \(p.bytesDownloaded / 1_000_000) / \(total / 1_000_000) MB"
            }
        }

        await MainActor.run {
            self.modelStatusLabel.stringValue = L("download.extracting")
            self.modelProgressBar.isIndeterminate = true
            self.modelProgressBar.startAnimation(nil)
        }

        try await extractTar(dest.path, to: dir, name: name, in: modelsDir)

        await MainActor.run {
            self.modelProgressBar.stopAnimation(nil)
            self.modelProgressBar.isIndeterminate = false
        }
    }

    private func downloadPunctModel(downloader: ModelDownloader, modelsDir: String) async throws {
        let name = "sherpa-onnx-punct-ct-transformer-zh-en-vocab272727-2024-04-12"
        let dir = (modelsDir as NSString).appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: dir) { return }

        let url = URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/punctuation-models/\(name).tar.bz2")!
        let dest = URL(fileURLWithPath: (modelsDir as NSString).appendingPathComponent("\(name).tar.bz2"))
        let known = Self.punctTarSize

        try await downloader.download(from: url, to: dest) { [weak self] p in
            DispatchQueue.main.async {
                guard let self else { return }
                let total = p.totalBytes > 0 ? p.totalBytes : known
                self.modelProgressBar.doubleValue = 0.75 + min(Double(p.bytesDownloaded) / Double(total), 1) * 0.15
                self.modelStatusLabel.stringValue = "\(L("download.punct")) \(p.bytesDownloaded / 1_000_000) / \(total / 1_000_000) MB"
            }
        }

        await MainActor.run {
            self.modelStatusLabel.stringValue = L("download.extractingPunct")
            self.modelProgressBar.isIndeterminate = true
            self.modelProgressBar.startAnimation(nil)
        }

        try await extractTar(dest.path, to: dir, name: name, in: modelsDir)

        await MainActor.run {
            self.modelProgressBar.stopAnimation(nil)
            self.modelProgressBar.isIndeterminate = false
        }
    }

    private func downloadVADModel(downloader: ModelDownloader, modelsDir: String) async throws {
        let path = (modelsDir as NSString).appendingPathComponent("silero_vad.onnx")
        if FileManager.default.fileExists(atPath: path) { return }

        let url = URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx")!
        let tmp = URL(fileURLWithPath: path + ".downloading")

        try await downloader.download(from: url, to: tmp) { [weak self] p in
            DispatchQueue.main.async {
                guard let self else { return }
                self.modelProgressBar.doubleValue = 0.95 + p.fraction * 0.05
                self.modelStatusLabel.stringValue = L("download.vad")
            }
        }
        try FileManager.default.moveItem(atPath: tmp.path, toPath: path)
    }

    private func extractTar(_ tarPath: String, to modelDir: String, name: String, in modelsDir: String) async throws {
        let tmpDir = modelDir + ".extracting"
        let fm = FileManager.default
        try? fm.removeItem(atPath: tmpDir)
        try fm.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        proc.arguments = ["xf", tarPath]
        proc.currentDirectoryURL = URL(fileURLWithPath: tmpDir)
        let code = try await withCheckedThrowingContinuation { (c: CheckedContinuation<Int32, Error>) in
            proc.terminationHandler = { p in c.resume(returning: p.terminationStatus) }
            do { try proc.run() } catch { c.resume(throwing: error) }
        }
        guard code == 0 else {
            try? fm.removeItem(atPath: tmpDir)
            throw NSError(domain: "OwlWhisper", code: Int(code),
                userInfo: [NSLocalizedDescriptionKey: "Extract failed (exit \(code))"])
        }
        do {
            try fm.removeItem(atPath: tarPath)
        } catch {
            NSLog("[Settings] 删除 tar 文件失败 (%@): %@", tarPath, error.localizedDescription)
        }

        let extracted = (tmpDir as NSString).appendingPathComponent(name)
        if fm.fileExists(atPath: extracted) {
            try fm.moveItem(atPath: extracted, toPath: modelDir)
        } else {
            try fm.moveItem(atPath: tmpDir, toPath: modelDir)
        }
        try? fm.removeItem(atPath: tmpDir)
    }

    private func downloadComplete() {
        downloader = nil
        downloadTaskHandle = nil
        modelProgressBar.isHidden = true
        modelProgressBar.doubleValue = 0
        modelStatusIcon.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
        modelStatusIcon.contentTintColor = .systemGreen
        modelStatusLabel.stringValue = L("status.ready")
        modelStatusLabel.textColor = .secondaryLabelColor
        modelActionBtn.isHidden = true
        updateGuide()
        onModelsReady?()
    }

    // MARK: - Hotkey Recording

    @objc private func hotkeyAreaClicked() {
        guard !isRecording else { return }
        isRecording = true
        modKeyCode = nil
        hotkeyLabel.stringValue = L("hotkey.recording")
        hotkeyLabel.textColor = .tertiaryLabelColor
        hotkeyHint.stringValue = ""
        hotkeyArea.layer?.borderColor = NSColor.controlAccentColor.cgColor
        hotkeyArea.layer?.borderWidth = 2

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, self.isRecording else { return event }
            if event.type == .keyDown { self.handleKeyPress(event); return nil }
            if event.type == .flagsChanged { self.handleFlags(event); return nil }
            return event
        }
    }

    private func handleKeyPress(_ event: NSEvent) {
        modTimer?.invalidate()
        let mods = event.modifierFlags.intersection([.shift, .control, .option, .command])
        let name = HotkeyConfig.displayName(keyCode: event.keyCode, modifiers: mods)
        finishRecording(HotkeyConfig(keyCode: event.keyCode, modifiers: mods, displayName: name))
    }

    private func handleFlags(_ event: NSEvent) {
        modTimer?.invalidate()
        let mods = event.modifierFlags.intersection([.shift, .control, .option, .command, .function])
        if !mods.isEmpty {
            modKeyCode = event.keyCode
            hotkeyLabel.stringValue = modSymbols(mods, keyCode: event.keyCode)
            hotkeyLabel.textColor = .labelColor
            modTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] in _ = $0; self?.commitModifier() }
        } else if modKeyCode != nil {
            commitModifier()
        }
    }

    private func commitModifier() {
        guard isRecording, let mkc = modKeyCode else { return }
        modTimer?.invalidate()
        finishRecording(HotkeyConfig(keyCode: mkc, modifiers: [], displayName: HotkeyConfig.keyCodeName(mkc)))
    }

    private func finishRecording(_ config: HotkeyConfig) {
        isRecording = false
        if let m = eventMonitor { NSEvent.removeMonitor(m); eventMonitor = nil }

        HotkeyConfig.current = config
        hotkeyLabel.stringValue = config.displayName
        hotkeyLabel.textColor = .systemGreen
        hotkeyArea.layer?.borderColor = NSColor.systemGreen.cgColor

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.hotkeyLabel.textColor = .labelColor
            self?.hotkeyHint.stringValue = L("hotkey.hint")
            self?.hotkeyArea.layer?.borderColor = NSColor.separatorColor.cgColor
            self?.hotkeyArea.layer?.borderWidth = 1.5
        }

        onHotkeyChanged?()
    }

    private func modSymbols(_ mods: NSEvent.ModifierFlags, keyCode: UInt16) -> String {
        var p: [String] = []
        if mods.contains(.control) { p.append("⌃") }
        if mods.contains(.option)  { p.append("⌥") }
        if mods.contains(.shift)   { p.append("⇧") }
        if mods.contains(.command) { p.append("⌘") }
        if mods.contains(.function) && keyCode == 63 { p.append("Fn") }
        return p.joined(separator: " ")
    }

    // MARK: - Actions

    @objc private func openMicSettings() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
            DispatchQueue.main.async { self?.refreshStatus() }
        }
    }

    @objc private func openAccSettings() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func checkUpdate() {
        UpdateChecker.checkManually()
    }

    @objc private func languageChanged(_ sender: NSPopUpButton) {
        let lang = sender.indexOfSelectedItem == 1 ? "zh-Hans" : "en"
        UserDefaults.standard.set([lang], forKey: "AppleLanguages")
        UserDefaults.standard.synchronize()

        let alert = NSAlert()
        alert.messageText = L("settings.restartTitle")
        alert.informativeText = L("settings.restartMessage")
        alert.addButton(withTitle: L("settings.restartNow"))
        alert.addButton(withTitle: L("settings.restartLater"))
        if alert.runModal() == .alertFirstButtonReturn {
            let bundleURL = URL(fileURLWithPath: Bundle.main.bundlePath)
            let config = NSWorkspace.OpenConfiguration()
            config.createsNewApplicationInstance = true
            NSWorkspace.shared.openApplication(at: bundleURL, configuration: config) { app, error in
                if let error {
                    NSLog("[Settings] 重启失败: %@", error.localizedDescription)
                    return
                }
                DispatchQueue.main.async { NSApp.terminate(nil) }
            }
        }
    }

    // MARK: - Window Delegate

    func windowWillClose(_ notification: Notification) {
        if let m = eventMonitor { NSEvent.removeMonitor(m); eventMonitor = nil }
        isRecording = false
        pollTimer?.invalidate(); pollTimer = nil
        downloader?.cancel()
        downloadTaskHandle?.cancel()
        downloadTaskHandle = nil; downloader = nil
        window = nil
    }
}
