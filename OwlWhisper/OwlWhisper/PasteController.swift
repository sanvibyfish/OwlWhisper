import Cocoa

/// 粘贴控制器。
/// 将文字写入系统剪贴板，然后模拟 Cmd+V 粘贴到当前焦点应用。
class PasteController {

    /// 将文字粘贴到当前光标位置。
    func pasteText(_ text: String) {
        // 保存原始剪贴板内容
        let pasteboard = NSPasteboard.general
        let previousContents = pasteboard.string(forType: .string)

        // 写入新文字到剪贴板
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // 等待剪贴板就绪后模拟 Cmd+V
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.simulateCmdV()

            // 恢复原始剪贴板内容（延迟以确保粘贴完成）
            if let previous = previousContents {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    pasteboard.clearContents()
                    pasteboard.setString(previous, forType: .string)
                }
            }
        }
    }

    /// 使用 CGEvent 模拟 Cmd+V 按键。
    private func simulateCmdV() {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            NSLog("[PasteController] CGEventSource 创建失败")
            return
        }
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            NSLog("[PasteController] CGEvent 创建失败，请检查辅助功能权限")
            return
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
