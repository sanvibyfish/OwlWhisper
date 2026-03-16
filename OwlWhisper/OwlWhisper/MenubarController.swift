import Cocoa

private func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

/// Menubar 状态图标控制器。
class MenubarController: NSObject {

    enum State {
        case ready
        case recording
        case transcribing
        case error
    }

    var onHotkeyChanged: (() -> Void)?
    var onModelsReady: (() -> Void)?

    private let statusItem: NSStatusItem
    private var settingsWindow: SettingsWindowController?
    private var animationTimer: Timer?
    private var animationFrame = 0
    private var currentFrames: [NSImage] = []

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            if let icon = NSImage(named: "MenubarIcon") {
                icon.isTemplate = true
                button.image = icon
            } else {
                button.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "OwlWhisper")
            }
        }

        rebuildMenu()
    }

    func setState(_ state: State) {
        guard let button = statusItem.button else { return }

        switch state {
        case .ready:
            stopAnimation()
            if let icon = NSImage(named: "MenubarIcon") {
                icon.isTemplate = true
                button.image = icon
            } else {
                button.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "就绪")
            }
            button.appearsDisabled = false
        case .recording:
            button.appearsDisabled = false
            startAnimation(frames: Self.recordingFrames, interval: 0.3)
        case .transcribing:
            button.appearsDisabled = false
            startAnimation(frames: Self.transcribingFrames, interval: 0.25)
        case .error:
            stopAnimation()
            button.image = NSImage(systemSymbolName: "mic.badge.xmark", accessibilityDescription: "错误")
            button.appearsDisabled = true
        }
    }

    // MARK: - 动画

    private static let recordingFrames: [NSImage] = {
        let barSets: [[CGFloat]] = [
            [0.3, 0.8, 0.5],
            [0.7, 0.4, 0.9],
            [0.5, 0.9, 0.3],
            [0.9, 0.5, 0.7],
        ]
        return barSets.map { heights in
            let size = NSSize(width: 18, height: 18)
            let img = NSImage(size: size, flipped: false) { _ in
                let barW: CGFloat = 2.5
                let gap: CGFloat = 2.5
                let count = CGFloat(heights.count)
                let totalW = count * barW + (count - 1) * gap
                let startX = (size.width - totalW) / 2
                let maxH = size.height * 0.75
                let baseY = size.height * 0.125

                NSColor.controlTextColor.setFill()
                for (i, h) in heights.enumerated() {
                    let x = startX + CGFloat(i) * (barW + gap)
                    let barH = max(maxH * h, 2)
                    let y = baseY + (maxH - barH) / 2
                    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: barW, height: barH),
                                 xRadius: 1.25, yRadius: 1.25).fill()
                }
                return true
            }
            img.isTemplate = true
            return img
        }
    }()

    private static let transcribingFrames: [NSImage] = {
        // 三个点依次高亮，4帧（3个点 + 1帧全暗）
        let dotCount = 3
        let dotR: CGFloat = 2.5
        let gap: CGFloat = 3.5
        let size = NSSize(width: 18, height: 18)

        return (0..<(dotCount + 1)).map { frame in
            let img = NSImage(size: size, flipped: false) { _ in
                let totalW = CGFloat(dotCount) * dotR * 2 + CGFloat(dotCount - 1) * gap
                let startX = (size.width - totalW) / 2
                let baseY = size.height / 2

                for i in 0..<dotCount {
                    let x = startX + CGFloat(i) * (dotR * 2 + gap)
                    let isActive = (i == frame)
                    let y = isActive ? baseY + 1.5 : baseY - dotR
                    let alpha: CGFloat = isActive ? 1.0 : 0.35

                    NSColor.controlTextColor.withAlphaComponent(alpha).setFill()
                    let dot = NSBezierPath(ovalIn: NSRect(x: x, y: y, width: dotR * 2, height: dotR * 2))
                    dot.fill()
                }
                return true
            }
            img.isTemplate = true
            return img
        }
    }()

    private func startAnimation(frames: [NSImage], interval: TimeInterval) {
        stopAnimation()
        currentFrames = frames
        animationFrame = 0
        updateAnimationFrame()
        animationTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.updateAnimationFrame()
        }
    }

    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    private func updateAnimationFrame() {
        guard let button = statusItem.button, !currentFrames.isEmpty else { return }
        button.image = currentFrames[animationFrame % currentFrames.count]
        animationFrame += 1
    }

    func showPermissionWarning(mic: Bool, accessibility: Bool) {
        guard let menu = statusItem.menu else { return }
        clearPermissionWarning()

        var warnings: [String] = []
        if mic { warnings.append(L("status.microphone")) }
        if accessibility { warnings.append(L("status.paste")) }

        let item = NSMenuItem(
            title: "⚠️ 需要授权: \(warnings.joined(separator: " + "))",
            action: #selector(openAccessibilitySettings),
            keyEquivalent: ""
        )
        item.target = self
        item.tag = 999
        menu.insertItem(item, at: min(2, menu.items.count))

        statusItem.button?.image = NSImage(
            systemSymbolName: "mic.badge.xmark",
            accessibilityDescription: "需要权限"
        )
    }

    func clearPermissionWarning() {
        guard let menu = statusItem.menu else { return }
        if let item = menu.item(withTag: 999), let index = menu.items.firstIndex(of: item) {
            menu.removeItem(at: index)
        }
    }

    // MARK: - 菜单

    func rebuildMenu() {
        let menu = NSMenu()

        let titleItem = NSMenuItem(title: "OwlWhisper", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(NSMenuItem.separator())

        let hintItem = NSMenuItem(title: String(format: L("menu.holdToSpeak"), HotkeyConfig.current.displayName), action: nil, keyEquivalent: "")
        hintItem.isEnabled = false
        menu.addItem(hintItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: L("menu.settings"), action: #selector(openSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let updateItem = NSMenuItem(title: L("update.check"), action: #selector(checkForUpdates), keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: L("menu.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    // MARK: - Actions

    func showSettings() {
        openSettings()
    }

    @objc private func checkForUpdates() {
        UpdateChecker.checkManually()
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController()
            settingsWindow?.onHotkeyChanged = { [weak self] in
                self?.rebuildMenu()
                self?.onHotkeyChanged?()
            }
            settingsWindow?.onModelsReady = { [weak self] in
                self?.onModelsReady?()
            }
        }
        settingsWindow?.show()
    }

    @objc private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - 快捷键录制窗口

class KeyRecorderWindow: NSObject, NSWindowDelegate {

    var onKeyRecorded: ((HotkeyConfig) -> Void)?
    var onDismiss: (() -> Void)?
    private var window: NSWindow!
    private var recorderView: KeyRecorderView!
    private var eventMonitor: Any?

    func show() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 180),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "录制快捷键"
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.level = .floating

        let cv = NSView(frame: window.contentView!.bounds)
        window.contentView = cv

        // 提示
        let hint = NSTextField(frame: NSRect(x: 0, y: 145, width: 380, height: 20))
        hint.isEditable = false; hint.isBordered = false; hint.drawsBackground = false
        hint.alignment = .center
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .secondaryLabelColor
        hint.stringValue = L("recorder.hint")
        cv.addSubview(hint)

        // 按键捕获视图
        recorderView = KeyRecorderView(frame: NSRect(x: 40, y: 60, width: 300, height: 70))
        recorderView.onRecorded = { [weak self] config in
            // 延迟关闭，让用户看到录制结果
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                self?.onKeyRecorded?(config)
                self?.window.close()
            }
        }
        cv.addSubview(recorderView)

        // 说明
        let sub = NSTextField(frame: NSRect(x: 0, y: 30, width: 380, height: 18))
        sub.isEditable = false; sub.isBordered = false; sub.drawsBackground = false
        sub.alignment = .center
        sub.font = .systemFont(ofSize: 11)
        sub.textColor = .tertiaryLabelColor
        sub.stringValue = L("recorder.support")
        cv.addSubview(sub)

        // 先激活应用，再让窗口成为 key window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(recorderView)

        // 用 local monitor 拦截键盘事件，防止 ⌘Z 等被系统菜单吃掉
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let view = self?.recorderView else { return event }
            if event.type == .keyDown {
                view.keyDown(with: event)
                return nil
            } else if event.type == .flagsChanged {
                view.flagsChanged(with: event)
                return nil
            }
            return event
        }

        NSLog("[Recorder] show() isKey=%d isMain=%d firstResponder=%@",
              window.isKeyWindow ? 1 : 0, window.isMainWindow ? 1 : 0,
              String(describing: window.firstResponder))
    }

    func windowWillClose(_ notification: Notification) {
        if let m = eventMonitor {
            NSEvent.removeMonitor(m)
            eventMonitor = nil
        }
        onDismiss?()
    }
}

// MARK: - 按键捕获 NSView（覆写 keyDown / flagsChanged，不依赖 monitor）

class KeyRecorderView: NSView {

    var onRecorded: ((HotkeyConfig) -> Void)?

    private var label: NSTextField!
    private var currentMods: NSEvent.ModifierFlags = []
    private var modKeyCode: UInt16?
    private var recorded = false
    private var modTimer: Timer?

    override init(frame: NSRect) {
        super.init(frame: frame)

        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.cornerRadius = 12
        layer?.borderWidth = 2
        layer?.borderColor = NSColor.selectedControlColor.cgColor

        label = NSTextField(frame: NSRect(x: 0, y: 10, width: frame.width, height: 44))
        label.isEditable = false; label.isBordered = false; label.drawsBackground = false
        label.alignment = .center
        label.font = .monospacedSystemFont(ofSize: 28, weight: .medium)
        label.textColor = .tertiaryLabelColor
        label.stringValue = L("recorder.pressKey")
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    override func becomeFirstResponder() -> Bool {
        NSLog("[Recorder] becomeFirstResponder")
        layer?.borderColor = NSColor.controlAccentColor.cgColor
        return true
    }

    override func resignFirstResponder() -> Bool {
        layer?.borderColor = NSColor.separatorColor.cgColor
        return true
    }

    override func mouseDown(with event: NSEvent) {
        NSLog("[Recorder] mouseDown, requesting firstResponder")
        window?.makeFirstResponder(self)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // performKeyEquivalent 比 keyDown 更早被调用
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        NSLog("[Recorder] performKeyEquivalent type=%ld keyCode=%d", event.type.rawValue, event.keyCode)
        if !recorded && event.type == .keyDown {
            handleKeyPress(event)
            return true
        }
        return false
    }

    override func keyDown(with event: NSEvent) {
        NSLog("[Recorder] keyDown keyCode=%d", event.keyCode)
        handleKeyPress(event)
    }

    private func handleKeyPress(_ event: NSEvent) {
        guard !recorded else { return }
        modTimer?.invalidate()

        let mods = event.modifierFlags.intersection([.shift, .control, .option, .command])
        let keyCode = event.keyCode
        let name = HotkeyConfig.displayName(keyCode: keyCode, modifiers: mods)

        label.stringValue = name
        label.textColor = .systemGreen
        recorded = true

        onRecorded?(HotkeyConfig(keyCode: keyCode, modifiers: mods, displayName: name))
    }

    // 捕获 modifier 键变化（实时显示 + 单 modifier 录制）
    override func flagsChanged(with event: NSEvent) {
        NSLog("[Recorder] flagsChanged keyCode=%d flags=0x%lx", event.keyCode, event.modifierFlags.rawValue)
        guard !recorded else { return }
        modTimer?.invalidate()

        let mods = event.modifierFlags.intersection([.shift, .control, .option, .command, .function])

        if !mods.isEmpty {
            currentMods = mods
            modKeyCode = event.keyCode

            // 实时显示当前按住的 modifier
            label.textColor = .labelColor
            label.stringValue = modifierSymbols(mods, keyCode: event.keyCode)

            // 如果用户只按 modifier 不加其他键，松开后自动录制
            modTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
                self?.commitModifierOnly()
            }
        } else if let mkc = modKeyCode {
            // modifier 全部松开 → 录制为单 modifier 键
            commitModifierOnly()
            _ = mkc // suppress warning
        } else {
            label.textColor = .tertiaryLabelColor
            label.stringValue = L("recorder.pressKey")
        }
    }

    private func commitModifierOnly() {
        guard !recorded, let mkc = modKeyCode else { return }
        modTimer?.invalidate()
        recorded = true

        let name = HotkeyConfig.keyCodeName(mkc)
        label.stringValue = name
        label.textColor = .systemGreen

        onRecorded?(HotkeyConfig(keyCode: mkc, modifiers: [], displayName: name))
    }

    private func modifierSymbols(_ mods: NSEvent.ModifierFlags, keyCode: UInt16) -> String {
        var parts: [String] = []
        if mods.contains(.control) { parts.append("⌃") }
        if mods.contains(.option)  { parts.append("⌥") }
        if mods.contains(.shift)   { parts.append("⇧") }
        if mods.contains(.command) { parts.append("⌘") }
        if mods.contains(.function) && keyCode == 63 { parts.append("Fn") }
        return parts.joined(separator: " ")
    }
}
