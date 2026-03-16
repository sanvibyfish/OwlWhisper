import Cocoa

/// 浮窗指示器：录音时显示声波动画，转写时显示加载动画。
class FloatingIndicator {

    enum State {
        case recording
        case transcribing
        case hidden
    }

    private var window: NSWindow?
    private var bars: [NSView] = []
    private var dots: [NSView] = []
    private var animationTimer: Timer?
    private var animationFrame = 0

    // 声波参数
    private static let barCount = 20
    private static let barWidth: CGFloat = 3
    private static let barGap: CGFloat = 2.5
    private static let barMaxH: CGFloat = 12
    private static let barMinH: CGFloat = 3
    private static let padding: CGFloat = 14

    // 加载点参数
    private static let dotCount = 3
    private static let dotSize: CGFloat = 6
    private static let dotGap: CGFloat = 6

    private static var windowWidth: CGFloat {
        CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barGap + padding * 2
    }
    private static var windowHeight: CGFloat { barMaxH + padding * 2 }

    func setState(_ state: State) {
        switch state {
        case .recording:
            show()
            showWaveform()
            startWaveAnimation()
        case .transcribing:
            showLoadingDots()
            startDotsAnimation()
        case .hidden:
            hide()
        }
    }

    // MARK: - 窗口

    private func ensureWindow() {
        guard window == nil else { return }
        let w = Self.windowWidth
        let h = Self.windowHeight

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: w, height: h),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        win.isOpaque = false
        win.backgroundColor = .clear
        win.level = .statusBar
        win.hasShadow = false
        win.ignoresMouseEvents = true
        win.collectionBehavior = [.canJoinAllSpaces, .stationary]

        let bg = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        bg.blendingMode = .behindWindow
        bg.material = .hudWindow
        bg.state = .active
        bg.wantsLayer = true
        bg.layer?.cornerRadius = h / 2
        bg.layer?.masksToBounds = true
        bg.layer?.borderWidth = 0
        bg.appearance = NSAppearance(named: .darkAqua)
        win.contentView = bg

        window = win
    }

    private func show() {
        ensureWindow()
        let w = Self.windowWidth
        let h = Self.windowHeight

        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            let x = f.midX - w / 2
            let y = f.minY + 4
            window?.setFrameOrigin(NSPoint(x: x, y: y))
        }

        window?.alphaValue = 0
        window?.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            window?.animator().alphaValue = 1
        }
    }

    private func hide() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            self.window?.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.animationTimer?.invalidate()
            self?.animationTimer = nil
            self?.window?.orderOut(nil)
            self?.clearContent()
        })
    }

    private func clearContent() {
        bars.forEach { $0.removeFromSuperview() }
        bars.removeAll()
        dots.forEach { $0.removeFromSuperview() }
        dots.removeAll()
    }

    // MARK: - 声波动画（录音）

    private func showWaveform() {
        clearContent()
        guard let container = window?.contentView else { return }

        let centerY = Self.windowHeight / 2

        for i in 0..<Self.barCount {
            let x = Self.padding + CGFloat(i) * (Self.barWidth + Self.barGap)
            let h = Self.barMinH
            let y = centerY - h / 2

            let bar = NSView(frame: NSRect(x: x, y: y, width: Self.barWidth, height: h))
            bar.wantsLayer = true
            bar.layer?.cornerRadius = Self.barWidth / 2
            bar.layer?.backgroundColor = NSColor.labelColor.cgColor
            container.addSubview(bar)
            bars.append(bar)
        }
    }

    private func startWaveAnimation() {
        animationTimer?.invalidate()
        animationFrame = 0

        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.animationFrame += 1
            let centerY = Self.windowHeight / 2

            for (i, bar) in self.bars.enumerated() {
                // 生成波浪形高度：用 sin 函数 + 时间偏移
                let phase = Double(self.animationFrame) * 0.3 + Double(i) * 0.5
                let wave = (sin(phase) + 1) / 2  // 0~1
                let h = Self.barMinH + (Self.barMaxH - Self.barMinH) * CGFloat(wave)
                let y = centerY - h / 2

                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.08
                    bar.animator().frame = NSRect(
                        x: bar.frame.origin.x, y: y,
                        width: Self.barWidth, height: h
                    )
                }
            }
        }
    }

    // MARK: - 加载动画（转写）

    private func showLoadingDots() {
        animationTimer?.invalidate()
        clearContent()
        guard let container = window?.contentView else { return }

        let totalW = CGFloat(Self.dotCount) * Self.dotSize + CGFloat(Self.dotCount - 1) * Self.dotGap
        let startX = (Self.windowWidth - totalW) / 2
        let centerY = Self.windowHeight / 2 - Self.dotSize / 2

        for i in 0..<Self.dotCount {
            let x = startX + CGFloat(i) * (Self.dotSize + Self.dotGap)
            let dot = NSView(frame: NSRect(x: x, y: centerY, width: Self.dotSize, height: Self.dotSize))
            dot.wantsLayer = true
            dot.layer?.cornerRadius = Self.dotSize / 2
            dot.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
            dot.alphaValue = 0.4
            container.addSubview(dot)
            dots.append(dot)
        }
    }

    private func startDotsAnimation() {
        animationFrame = 0
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.18, repeats: true) { [weak self] _ in
            guard let self else { return }
            let idx = self.animationFrame % (Self.dotCount + 1)
            self.animationFrame += 1

            for (i, dot) in self.dots.enumerated() {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.15
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    if i == idx {
                        dot.animator().frame.origin.y = Self.windowHeight / 2 - Self.dotSize / 2 + 4
                        dot.animator().alphaValue = 1.0
                    } else {
                        dot.animator().frame.origin.y = Self.windowHeight / 2 - Self.dotSize / 2
                        dot.animator().alphaValue = 0.4
                    }
                }
            }
        }
    }
}
