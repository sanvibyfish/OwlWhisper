import Foundation
import Cocoa

/// 检查 GitHub Releases 最新版本，提示用户更新。
class UpdateChecker {

    private static let repoOwner = "sanvi"
    private static let repoName = "OwlWhisper"
    private static let releasesURL = "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest"

    /// 启动时检查更新（静默，有新版才弹窗）。
    static func checkOnLaunch() {
        // 每天最多检查一次
        let lastCheck = UserDefaults.standard.double(forKey: "lastUpdateCheck")
        let now = Date().timeIntervalSince1970
        guard now - lastCheck > 86400 else { return }

        check(silent: true)
    }

    /// 手动检查更新（无论有没有新版都给反馈）。
    static func checkManually() {
        check(silent: false)
    }

    private static func check(silent: Bool) {
        guard let url = URL(string: releasesURL) else { return }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error {
                    NSLog("[UpdateChecker] Check failed: %@", error.localizedDescription)
                    if !silent {
                        showAlert(title: L("update.checkFailed"), message: error.localizedDescription)
                    }
                    return
                }

                guard let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tagName = json["tag_name"] as? String else {
                    NSLog("[UpdateChecker] Invalid response or missing tag_name")
                    if !silent {
                        showAlert(title: L("update.checkFailed"), message: "Invalid response")
                    }
                    return
                }

                // 成功解析后才标记已检查
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastUpdateCheck")

                let remoteVersion = tagName.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
                let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"

                if compareVersions(remoteVersion, isNewerThan: currentVersion) {
                    let body = json["body"] as? String ?? ""
                    let downloadURL = json["html_url"] as? String ?? "https://github.com/\(repoOwner)/\(repoName)/releases"
                    showUpdateAvailable(version: remoteVersion, notes: body, url: downloadURL)
                } else if !silent {
                    showAlert(
                        title: L("update.upToDate"),
                        message: String(format: L("update.currentVersion"), currentVersion)
                    )
                }
            }
        }.resume()
    }

    private static func showUpdateAvailable(version: String, notes: String, url: String) {
        let alert = NSAlert()
        alert.messageText = String(format: L("update.available"), version)
        alert.informativeText = notes.prefix(300) + (notes.count > 300 ? "..." : "")
        alert.addButton(withTitle: L("update.download"))
        alert.addButton(withTitle: L("update.later"))
        alert.alertStyle = .informational

        if alert.runModal() == .alertFirstButtonReturn {
            if let downloadURL = URL(string: url) {
                NSWorkspace.shared.open(downloadURL)
            }
        }
    }

    private static func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: L("update.copy"))
        if alert.runModal() == .alertSecondButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("\(title)\n\(message)", forType: .string)
        }
    }

    /// 简单版本号比较：1.2.3 > 1.2.2
    private static func compareVersions(_ remote: String, isNewerThan local: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let l = local.split(separator: ".").compactMap { Int($0) }
        let count = max(r.count, l.count)
        for i in 0..<count {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv > lv { return true }
            if rv < lv { return false }
        }
        return false
    }
}

private func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}
