# FEAT-001: 原生 ASR 语音转写

> 状态：✅ Done | 创建日期：2026-03-16 | 完成日期：2026-03-17

---

## 1. 功能概述

通过 sherpa-onnx C API 在 Swift 中直接调用 FireRedASR2 模型进行离线语音识别，替代原 Python 子进程方案。

## 2. 用户流程

1. 按住快捷键（如 ⌥Z）→ 开始录音
2. 松开快捷键 → 延迟 300ms 停止录音（捕获语音尾巴）
3. VAD 切段 → FireRedASR2 转写 → 标点恢复
4. 文字写入剪贴板 → 模拟 ⌘V 粘贴到光标处

## 3. 技术实现

- **桥接**：`SherpaOnnx-Bridging-Header.h` 引入 `c-api.h`
- **ASRService.swift**：串行 DispatchQueue 执行所有 C API 调用
- **模型加载**：`SherpaOnnxCreateOfflineRecognizer` + `SherpaOnnxCreateVoiceActivityDetector`
- **转写流程**：
  1. 音频末尾补 500ms 静音（防 VAD 截断）
  2. 按 window_size=512 喂入 VAD
  3. `SherpaOnnxVoiceActivityDetectorFlush` → 收集语音片段
  4. 拼接后 `SherpaOnnxAcceptWaveformOffline` → `SherpaOnnxDecodeOfflineStream`
- **内存管理**：`strdup`/`free` 管理 C 字符串，`defer` 确保释放
- **dylib**：`libsherpa-onnx-c-api.dylib` + `libonnxruntime.1.23.2.dylib` 嵌入 Frameworks

## 4. 注意事项

- VAD 参数：threshold=0.5, min_silence_duration=0.25, min_speech_duration=0.25
- 模型路径搜索顺序：Bundle Resources → Application Support
- 标点模型可选——找不到则跳过，不影响转写

## 5. 相关需求

- [REQ-001: 本地语音输入工具](../requirements/001-local-voice-input.md)

## 6. 更新记录

| 日期 | 变更 |
|------|------|
| 2026-03-16 | Python 子进程方案实现 |
| 2026-03-17 | 重写为原生 Swift + sherpa-onnx C API |
