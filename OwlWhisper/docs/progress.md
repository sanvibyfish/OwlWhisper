# OwlWhisper - Progress

> Last updated: 2026-03-16

## Project Overview

OwlWhisper is a macOS menubar app for local voice-to-text input, powered by sherpa-onnx (on-device ASR). No cloud services required.

---

## Status Summary

| Feature | Status | Notes |
|---------|--------|-------|
| Core ASR (sherpa-onnx C API) | Done | Direct bridging header + dylib integration |
| Python layer removal | Done | Fully removed, pure Swift/C now |
| VAD (Voice Activity Detection) | Done | sherpa-onnx silero VAD |
| Punctuation restoration | Done | ct-transformer model via sherpa-onnx |
| Model auto-download | Done | Chunked parallel download with resume |
| Hotkey recording trigger | Done | Global hotkey via CGEventTap |
| Floating indicator | Done | Waveform (recording) + blue dots (transcribing) |
| Menubar UI | Done | Three-dot bounce animation for transcribing |
| Unified settings window | Done | Merged onboarding + settings into one window |
| Text paste to active app | Done | Via PasteController |
| Production build & test | Done | Clean install from /Applications verified |
| UI layout optimization | In Progress | Smaller hotkey area, hint text repositioned |
| Internationalization (i18n) | Not Started | Chinese + English, default English |
| Auto-update (Sparkle) | Not Started | Version update management |

---

## Architecture

```
OwlWhisper.app (Swift, macOS)
  |
  +-- ASRService.swift        -- sherpa-onnx C API (bridging header)
  +-- AudioRecorder.swift     -- AVAudioEngine mic capture
  +-- HotkeyManager.swift     -- CGEventTap global hotkey
  +-- MenubarController.swift -- NSStatusItem menubar UI
  +-- SettingsWindowController -- Unified guide + settings
  +-- FloatingIndicator.swift -- Recording/transcribing animation
  +-- ModelDownloader.swift   -- Chunked parallel model download
  +-- PasteController.swift   -- Paste transcribed text to active app
  |
  +-- Models (~/Library/Application Support/OwlWhisper/models/)
       +-- ASR model (~838MB)
       +-- Punctuation model (~270MB)
       +-- VAD model (~2MB)
```

---

## Checkpoints

| Date | Summary |
|------|---------|
| 2026-03-16 | Python removed, sherpa-onnx direct integration, unified UI, floating indicator, production test passed. [Details](memory/2026-03-16.md) |
