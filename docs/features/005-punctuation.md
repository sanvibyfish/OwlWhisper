# FEAT-005: 标点恢复

> 状态：✅ Done | 创建日期：2026-03-17 | 完成日期：2026-03-17

---

## 1. 功能概述

转写结果自动添加中英文标点符号（逗号、句号等），使用 sherpa-onnx 的 ct-transformer 模型。

## 2. 用户流程

用户无感知——转写完成后自动加标点，直接粘贴带标点的文字。

## 3. 技术实现

- **模型**：`sherpa-onnx-punct-ct-transformer-zh-en-vocab272727-2024-04-12`
- **API**：`SherpaOnnxCreateOfflinePunctuation` → `SherpaOfflinePunctuationAddPunct`
- **可选**：标点模型找不到时跳过，不影响基本转写功能
- **调用位置**：ASRService.transcribe() 中，ASR 解码完成后

## 4. 注意事项

- 标点模型约 270MB，与 ASR 模型一起下载
- 标点恢复始终启用，逗号和句号都保留

## 5. 相关需求

- [REQ-001: 本地语音输入工具](../requirements/001-local-voice-input.md)

## 6. 更新记录

| 日期 | 变更 |
|------|------|
| 2026-03-17 | 集成 ct-transformer 标点模型 |
