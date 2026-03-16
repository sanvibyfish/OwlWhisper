# FEAT-004: 浮窗状态指示

> 状态：✅ Done | 创建日期：2026-03-17 | 完成日期：2026-03-17

---

## 1. 功能概述

屏幕底部居中的浮窗，录音时显示声波动画，转写时显示蓝色跳动圆点。

## 2. 用户流程

- 按住快捷键 → 浮窗淡入，声波动画（20 根竖条 sin 波浪）
- 松开快捷键 → 切换为蓝色三点弹跳动画（转写中）
- 转写完成 → 浮窗淡出

## 3. 技术实现

- **FloatingIndicator.swift**：borderless NSWindow，level = .statusBar
- **声波动画**：20 根 NSView 竖条，Timer 每 0.08s 更新高度（sin 函数 + 时间偏移）
- **三点动画**：3 个 NSView 圆点，依次弹跳 + alpha 变化
- **背景**：NSVisualEffectView，hudWindow material，dark 外观，胶囊圆角（h/2），无边框无阴影
- **定位**：屏幕底部居中，距底边 4px
- **淡入淡出**：NSAnimationContext 0.2s alpha 动画

## 4. 注意事项

- AX API 获取文字光标位置在多数 app 中不可靠，最终选择固定屏幕底部居中
- Menubar 也有对应动画：录音声波条 + 转写三点

## 5. 相关需求

- [REQ-001: 本地语音输入工具](../requirements/001-local-voice-input.md)

## 6. 更新记录

| 日期 | 变更 |
|------|------|
| 2026-03-17 | 从圆点脉冲改为声波动画 + 三点弹跳 |
