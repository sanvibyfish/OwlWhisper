# FEAT-002: 设置窗口与引导流程

> 状态：✅ Done | 创建日期：2026-03-17 | 完成日期：2026-03-17

---

## 1. 功能概述

统一的设置窗口，兼具首次引导和日常设置功能。Auto Layout 布局，毛玻璃背景。

## 2. 用户流程

- **首次启动**：模型缺失或权限不全时自动弹出，引导用户完成设置
- **日常使用**：从 menubar → 设置 打开，管理快捷键、权限、语言

## 3. 技术实现

- **NSStackView + Auto Layout**：垂直布局，自动对齐
- **引导区**：根据状态显示不同图标和提示（一切就绪/完成设置/需要下载模型/正在准备）
- **状态行**：`makeStatusRow()` 生成图标 + 名称 + 状态文字 + 按钮
- **快捷键录制**：NSEvent.addLocalMonitorForEvents，支持组合键和纯 modifier 键
- **权限轮询**：每 2 秒检查权限变化，自动刷新 UI
- **窗口浮动**：`level = .floating` 确保在 LSUIElement app 中可见

## 4. 注意事项

- 删除了独立的 OnboardingWindow，所有功能收敛到设置窗口
- 麦克风授权直接弹系统对话框，辅助功能跳系统设置页

## 5. 相关需求

- [REQ-001: 本地语音输入工具](../requirements/001-local-voice-input.md)

## 6. 更新记录

| 日期 | 变更 |
|------|------|
| 2026-03-17 | 从 OnboardingWindow + SettingsWindow 合并为统一设置窗口 |
| 2026-03-17 | 重构为 Auto Layout |
