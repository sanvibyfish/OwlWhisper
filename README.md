<p align="center">
  <img src="OwlWhisper/OwlWhisper/Assets.xcassets/AppIcon.appiconset/icon_1024.png" width="128" alt="OwlWhisper icon">
</p>

<h1 align="center">OwlWhisper</h1>

<p align="center">
  Local voice input for macOS — hold a hotkey, speak, release, text appears at your cursor.
  <br>
  Fully offline. No cloud APIs. Chinese-optimized with FireRedASR2.
</p>

<p align="center">
  <a href="https://github.com/sanvibyfish/OwlWhisper/releases"><img src="https://img.shields.io/github/v/release/sanvibyfish/OwlWhisper?style=flat-square" alt="Release"></a>
  <img src="https://img.shields.io/badge/platform-macOS%2013%2B-blue?style=flat-square" alt="Platform">
  <img src="https://img.shields.io/badge/arch-Apple%20Silicon-orange?style=flat-square" alt="Architecture">
  <img src="https://img.shields.io/badge/license-GPL--3.0-blue?style=flat-square" alt="License">
</p>

<p align="center">
  <strong>English</strong> | <a href="docs/README_zh.md">中文</a>
</p>

---

## How It Works

1. Hold your hotkey (default: `Fn`)
2. Speak naturally
3. Release — text is transcribed and pasted at your cursor

Everything runs locally on your Mac. No data leaves your device.

## Features

- **Hold-to-speak** — Global hotkey works in any app, fully configurable
- **Offline ASR** — FireRedASR2 int8 via sherpa-onnx C API (2.89% CER on Chinese)
- **Auto punctuation** — ct-transformer restores commas, periods, question marks
- **Auto paste** — Transcribed text is pasted at cursor via simulated `Cmd+V`
- **VAD** — Silero VAD trims silence, only speech is sent to ASR
- **Floating indicator** — Waveform animation while recording, dots while transcribing
- **Auto model download** — First launch downloads ~1.1GB of models automatically with resume support
- **i18n** — English (default) + Chinese
- **Update checker** — Checks GitHub Releases for new versions

## Requirements

- macOS 13.0+
- Apple Silicon (arm64)

## Install

### From Release (recommended)

1. Download `OwlWhisper-0.1.0.dmg` from [Releases](https://github.com/sanvibyfish/OwlWhisper/releases)
2. Open DMG, drag OwlWhisper to `/Applications`
3. Launch — models download automatically on first run (~1.1GB)

### From Source

```bash
git clone https://github.com/sanvibyfish/OwlWhisper.git
cd OwlWhisper
scripts/setup.sh          # downloads native libs + models
open OwlWhisper/OwlWhisper.xcodeproj
# Build & Run (⌘R)
```

## Permissions

On first launch, OwlWhisper will guide you through granting the required permissions:

| Permission | Purpose |
|---|---|
| Microphone | Record your speech |
| Accessibility | Simulate `Cmd+V` paste and listen for global hotkeys |

## Architecture

```
OwlWhisper.app
├── ASRService.swift          # sherpa-onnx C API: VAD + ASR + punctuation
├── AudioRecorder.swift       # AVAudioEngine 16kHz mono capture
├── HotkeyManager.swift       # CGEventTap global hotkey detection
├── FloatingIndicator.swift   # Waveform + dots animation overlay
├── SettingsWindowController  # Auto Layout settings & onboarding
├── ModelDownloader.swift     # Chunked parallel download with resume
├── UpdateChecker.swift       # GitHub Release version check
├── MenubarController.swift   # Status bar icon + menu
├── PasteController.swift     # CGEvent Cmd+V simulation
├── AppDelegate.swift         # App lifecycle & orchestration
└── Frameworks/
    ├── libsherpa-onnx-c-api.dylib
    └── libonnxruntime.1.23.2.dylib
```

## Models

Downloaded to `~/Library/Application Support/OwlWhisper/models/` on first launch:

| Model | Size | Purpose |
|---|---|---|
| FireRedASR2 int8 | ~300MB | Chinese/English speech recognition |
| ct-transformer | ~270MB | Punctuation restoration |
| Silero VAD | ~2MB | Voice activity detection |

## Tech Stack

- Swift 5.9, AppKit (no SwiftUI)
- sherpa-onnx C API via bridging header
- onnxruntime 1.23.2

## License

[GPL-3.0](LICENSE)
