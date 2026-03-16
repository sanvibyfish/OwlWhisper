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
                button.image = NSImage(systemSymbolName: "mic", accessibilityDescription: L("accessibility.ready"))
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
            button.image = NSImage(systemSymbolName: "mic.badge.xmark", accessibilityDescription: L("accessibility.error"))
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
}
