# FEAT-003: 模型自动下载

> 状态：✅ Done | 创建日期：2026-03-17 | 完成日期：2026-03-17

---

## 1. 功能概述

首次启动自动下载 ASR、标点、VAD 三个模型到 `~/Library/Application Support/OwlWhisper/models/`。

## 2. 用户流程

1. 首次打开 → 设置窗口自动弹出 → 模型自动开始下载
2. 进度条显示下载进度（ASR 80% + 标点 15% + VAD 5%）
3. 下载完成 → 自动解压 → 状态变绿

## 3. 技术实现

- **ModelDownloader.swift**：分块并行下载器
  - 6 路并发，每 chunk 5MB
  - `.chunks` 元数据文件记录已完成分块，支持断点续传
  - `resolveDownload()` 用 Range: bytes=0-0 探测文件大小
  - GitHub CDN 不返回 Content-Length 时回退到 simpleDownload + 硬编码大小
- **解压安全**：tar 解压到 `.extracting` 临时目录，完成后原子 rename
- **三个模型**：
  - `sherpa-onnx-fire-red-asr2-zh_en-int8-2026-02-26` (~838MB)
  - `sherpa-onnx-punct-ct-transformer-zh-en-vocab272727-2024-04-12` (~270MB)
  - `silero_vad.onnx` (~2MB)

## 4. 注意事项

- AsyncSemaphore actor 控制并发数
- LockedCounter 保证进度统计线程安全
- 下载失败显示重试按钮

## 5. 相关需求

- [REQ-001: 本地语音输入工具](../requirements/001-local-voice-input.md)

## 6. 更新记录

| 日期 | 变更 |
|------|------|
| 2026-03-17 | 实现分块并行下载，参考 OwlUploader R2Service |
