# FEAT-007: 版本更新检查

> 状态：✅ Done | 创建日期：2026-03-17 | 完成日期：2026-03-17

---

## 1. 功能概述

检查 GitHub Releases 最新版本，有新版弹窗提示用户下载。

## 2. 用户流程

- **自动**：启动时静默检查（每天一次），有新版才弹窗
- **手动**：menubar → 检查更新 / 设置窗口 → Check for Updates

## 3. 技术实现

- **UpdateChecker.swift**：查询 `api.github.com/repos/{owner}/{repo}/releases/latest`
- **版本比较**：`compareVersions()` 逐段比较 major.minor.patch
- **弹窗**：NSAlert 显示版本号 + release notes，点「Download」跳 GitHub 页面
- **错误处理**：弹窗 + Copy 按钮，可复制错误信息
- **频率控制**：`lastUpdateCheck` UserDefaults，成功解析后才标记已检查

## 4. 注意事项

- GitHub 仓库需要存在且有 Release 才能正常工作
- `repoOwner` 和 `repoName` 在 UpdateChecker.swift 中配置
- 后续可升级为 Sparkle 自动更新框架

## 5. 相关需求

- [REQ-001: 本地语音输入工具](../requirements/001-local-voice-input.md)

## 6. 更新记录

| 日期 | 变更 |
|------|------|
| 2026-03-17 | 实现 GitHub Release 版本检查 |
