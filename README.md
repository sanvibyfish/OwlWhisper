# OwlWhisper

Local voice input for macOS — hold a hotkey, speak, release, text appears at your cursor.

Fully offline. No cloud APIs. Chinese-optimized with FireRedASR2 (2.89% CER).

## Features

- **Hold-to-speak** — Global hotkey (default ⌥Z), works in any app
- **Offline ASR** — FireRedASR2 int8 via sherpa-onnx C API, no Python dependency
- **Auto punctuation** — ct-transformer restores commas, periods, etc.
- **Auto paste** — Transcribed text is pasted at cursor via simulated ⌘V
- **VAD** — Silero VAD trims silence, only speech is transcribed
- **Floating indicator** — Waveform animation while recording, dots while transcribing
- **Auto model download** — First launch downloads ~1.1GB of models automatically
- **i18n** — English (default) + Chinese
- **Update checker** — Checks GitHub Releases for new versions

## Requirements

- macOS 13.0+
- Apple Silicon (arm64)

## Install

### From Release (recommended)

1. Download `OwlWhisper.app.zip` from [Releases](https://github.com/sanvi/OwlWhisper/releases)
2. Unzip and move to `/Applications`
3. Open — models download automatically on first launch (~1.1GB)

### From Source

```bash
git clone https://github.com/sanvi/OwlWhisper.git
cd OwlWhisper
scripts/setup.sh          # downloads native libs + models
open OwlWhisper/OwlWhisper.xcodeproj
# Build & Run (⌘R)
```

## Permissions

| Permission | Purpose |
|---|---|
| Microphone | Record audio |
| Accessibility | Simulate ⌘V paste |
| Input Monitoring | Auto-granted for signed apps from /Applications |

## Architecture

```
OwlWhisper.app
├── ASRService.swift          # sherpa-onnx C API: VAD + ASR + punctuation
├── HotkeyManager.swift       # CGEventTap global hotkey detection
├── AudioRecorder.swift       # AVAudioEngine 16kHz mono capture
├── FloatingIndicator.swift   # Waveform + dots animation
├── SettingsWindowController  # Auto Layout settings/onboarding
├── ModelDownloader.swift     # Chunked parallel download with resume
├── UpdateChecker.swift       # GitHub Release version check
├── MenubarController.swift   # Status bar icon + menu
├── PasteController.swift     # CGEvent ⌘V simulation
└── Frameworks/
    ├── libsherpa-onnx-c-api.dylib
    └── libonnxruntime.1.23.2.dylib
```

## Models

Downloaded to `~/Library/Application Support/OwlWhisper/models/`:

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

MIT
