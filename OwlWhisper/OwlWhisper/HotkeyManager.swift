import Cocoa

// MARK: - 快捷键配置

struct HotkeyConfig: CustomStringConvertible {
    var keyCode: UInt16
    var modifiers: NSEvent.ModifierFlags  // 空 = 单 modifier 键
    var displayName: String

    /// 是否是纯 modifier 键（Fn、Shift 等），用 flagsChanged 检测
    var isModifierOnly: Bool {
        return modifiers.isEmpty
    }

    var description: String { displayName }

    // 预设快捷键
    static let presets: [(name: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags)] = [
        ("Fn (🌐) 键",    63, []),
        ("右 Option 键",   61, []),
        ("右 Command 键",  54, []),
        ("左 Control 键",  59, []),
    ]

    static var current: HotkeyConfig {
        get {
            let keyCode: UInt16
            if let stored = UserDefaults.standard.object(forKey: "hotkeyKeyCode") as? Int {
                keyCode = UInt16(stored)
            } else {
                keyCode = 63  // 默认 Fn
            }
            let mods = UserDefaults.standard.integer(forKey: "hotkeyModifiers")
            let modFlags = NSEvent.ModifierFlags(rawValue: UInt(mods))
            let name = modFlags.isEmpty
                ? keyCodeName(keyCode)
                : displayName(keyCode: keyCode, modifiers: modFlags)
            return HotkeyConfig(keyCode: keyCode, modifiers: modFlags, displayName: name)
        }
        set {
            UserDefaults.standard.set(Int(newValue.keyCode), forKey: "hotkeyKeyCode")
            UserDefaults.standard.set(Int(newValue.modifiers.rawValue), forKey: "hotkeyModifiers")
        }
    }

    /// 从 NSEvent 生成可读的快捷键名称
    static func displayName(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option)  { parts.append("⌥") }
        if modifiers.contains(.shift)   { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }

        let keyName = keyCodeName(keyCode)
        parts.append(keyName)
        return parts.joined()
    }

    static func keyCodeName(_ keyCode: UInt16) -> String {
        let map: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 31: "O", 32: "U", 34: "I", 35: "P",
            37: "L", 38: "J", 40: "K", 45: "N", 46: "M",
            18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6",
            26: "7", 28: "8", 25: "9", 29: "0",
            36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "Esc",
            55: "⌘", 54: "⌘", 56: "⇧", 60: "⇧",
            58: "⌥", 61: "⌥", 59: "⌃", 62: "⌃",
            57: "⇪", 63: "Fn",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
            123: "←", 124: "→", 125: "↓", 126: "↑",
            44: "/", 47: ".", 43: ",", 41: ";", 39: "'", 27: "-", 24: "=",
            30: "]", 33: "[", 42: "\\", 50: "`",
        ]
        return map[keyCode] ?? "Key\(keyCode)"
    }
}

// MARK: - 快捷键监听器

class HotkeyManager {

    var onKeyDown: (() -> Void)?
    var onKeyUp: (() -> Void)?

    private var globalFlagMonitor: Any?
    private var localFlagMonitor: Any?
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    private var globalKeyUpMonitor: Any?
    private var localKeyUpMonitor: Any?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var retryTimer: Timer?

    private var keyPressed = false
    private var config = HotkeyConfig.current

    func start() {
        stop()
        config = HotkeyConfig.current

        if config.isModifierOnly {
            // 纯 modifier 键：监听 flagsChanged
            globalFlagMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] e in
                self?.handleModifierEvent(e)
            }
            localFlagMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] e in
                self?.handleModifierEvent(e)
                return e
            }
        } else {
            // 组合键：用 CGEventTap 拦截并吞掉按键，防止 ⌥Z → Ω 等副作用
            let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)

            let callback: CGEventTapCallBack = { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let mgr = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()

                // 系统超时禁用了 tap，重新启用
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = mgr.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
                    return Unmanaged.passUnretained(event)
                }

                let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
                guard keyCode == mgr.config.keyCode else { return Unmanaged.passUnretained(event) }

                // keyUp 时不检查 modifier（用户可能先松开了修饰键）
                if type == .keyUp && mgr.keyPressed {
                    mgr.updateState(false)
                    return nil
                }

                let actual = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
                    .intersection([.shift, .control, .option, .command])
                let required = mgr.config.modifiers.intersection([.shift, .control, .option, .command])
                guard actual == required else { return Unmanaged.passUnretained(event) }

                if type == .keyDown {
                    mgr.updateState(true)
                    return nil
                }
                return Unmanaged.passUnretained(event)
            }

            guard let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: callback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ) else {
                NSLog("[HotkeyManager] CGEventTap 创建失败，使用 NSEvent fallback + 定时重试")
                globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] e in
                    self?.handleKeyDown(e)
                }
                localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
                    self?.handleKeyDown(e)
                    return e
                }
                globalKeyUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyUp) { [weak self] e in
                    self?.handleKeyUp(e)
                }
                localKeyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] e in
                    self?.handleKeyUp(e)
                    return e
                }
                // 每 5 秒重试 CGEventTap（用户可能稍后授权）
                retryTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
                    self?.retryEventTap()
                }
                return
            }

            eventTap = tap
            runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)

            // 每 3 秒检查 tap 是否被系统禁用，禁用则重新启用
            retryTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
                guard let self, let tap = self.eventTap else { return }
                if !CGEvent.tapIsEnabled(tap: tap) {
                    NSLog("[HotkeyManager] EventTap 被系统禁用，重新启用")
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
            }
        }

        NSLog("[HotkeyManager] 已启动: %@ (keyCode=%d, modOnly=%d)", config.displayName, config.keyCode, config.isModifierOnly ? 1 : 0)
    }

    deinit { stop() }

    func stop() {
        for m in [globalFlagMonitor, localFlagMonitor, globalKeyMonitor, localKeyMonitor, globalKeyUpMonitor, localKeyUpMonitor] {
            if let m { NSEvent.removeMonitor(m) }
        }
        retryTimer?.invalidate(); retryTimer = nil
        globalFlagMonitor = nil; localFlagMonitor = nil
        globalKeyMonitor = nil; localKeyMonitor = nil
        globalKeyUpMonitor = nil; localKeyUpMonitor = nil

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil; runLoopSource = nil

        keyPressed = false
    }

    func reload() { start() }

    private func retryEventTap() {
        // 尝试创建 CGEventTap，成功则切换到 tap 模式
        let mask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)
        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask,
            callback: { _, _, e, _ in Unmanaged.passUnretained(e) }, userInfo: nil
        )
        guard let tap else { return }
        CFMachPortInvalidate(tap)
        // 权限已授予，重新初始化
        NSLog("[HotkeyManager] 输入监控权限已获取，重新初始化")
        retryTimer?.invalidate()
        retryTimer = nil
        start()
    }

    // MARK: - 纯 modifier 键检测

    /// 左右 modifier 配对表
    private static let modifierPairs: [UInt16: UInt16] = [
        55: 54, 54: 55,  // ⌘
        56: 60, 60: 56,  // ⇧
        58: 61, 61: 58,  // ⌥
        59: 62, 62: 59,  // ⌃
    ]

    private func handleModifierEvent(_ event: NSEvent) {
        let code = event.keyCode
        guard code == config.keyCode || code == Self.modifierPairs[config.keyCode] else { return }
        let hasModifier = !event.modifierFlags.intersection([.shift, .control, .option, .command, .function]).isEmpty
        updateState(hasModifier)
    }

    // MARK: - 组合键检测

    private func handleKeyDown(_ event: NSEvent) {
        guard event.keyCode == config.keyCode else { return }
        let required = config.modifiers.intersection([.shift, .control, .option, .command])
        let actual = event.modifierFlags.intersection([.shift, .control, .option, .command])
        guard actual == required else { return }
        updateState(true)
    }

    private func handleKeyUp(_ event: NSEvent) {
        guard event.keyCode == config.keyCode, keyPressed else { return }
        updateState(false)
    }

    private func updateState(_ isDown: Bool) {
        if isDown && !keyPressed {
            keyPressed = true
            DispatchQueue.main.async { [weak self] in self?.onKeyDown?() }
        } else if !isDown && keyPressed {
            keyPressed = false
            DispatchQueue.main.async { [weak self] in self?.onKeyUp?() }
        }
    }
}
