# 🎙️ Ambi

**Ambient voice recorder for macOS** — always-on transcription powered by local AI.

Ambi runs quietly in your menu bar, continuously capturing and transcribing everything you say. All processing happens locally using Whisper, so your conversations never leave your Mac.

![Ambi Screenshot](docs/screenshot.png)

## Features

- **Always-on recording** — Starts automatically when you log in
- **Local AI transcription** — Uses Whisper.cpp for fast, private transcription
- **No audio storage** — Only transcriptions are saved, raw audio is discarded
- **Beautiful UI** — Modern, minimalistic interface to browse your transcriptions
- **Smart organization** — Auto-generated titles and date-based grouping
- **Full-text search** — Find any conversation instantly
- **Privacy-first** — Everything stays on your device

## Requirements

- macOS 13.0 (Ventura) or later
- Apple Silicon Mac (M1/M2/M3) recommended for best transcription performance
- ~1.5GB disk space for the Whisper model

## Installation

### Download Release

1. Download the latest `.dmg` from [Releases](https://github.com/hariPrasadCoder/ambi/releases)
2. Drag Ambi to your Applications folder
3. Launch Ambi — it will request microphone permission
4. Click the menu bar icon to access settings and view transcriptions

### Build from Source

```bash
# Clone the repo
git clone https://github.com/hariPrasadCoder/ambi.git
cd ambi

# Open in Xcode
open Ambi.xcodeproj

# Build and run (⌘R)
```

## Setup

On first launch, Ambi will:
1. Request microphone permission (required)
2. Download the Whisper model (~1.5GB, one-time)
3. Start recording automatically

### Whisper Model

Ambi uses the `whisper-large-v3-turbo` model by default for best accuracy. You can change this in Settings:

- **Tiny** (~75MB) — Fastest, lowest accuracy
- **Base** (~142MB) — Good balance
- **Small** (~466MB) — Better accuracy
- **Medium** (~1.5GB) — High accuracy
- **Large-v3-turbo** (~1.5GB) — Best accuracy (default)

## Usage

### Menu Bar

Click the 🎙️ icon in your menu bar to:
- See recording status
- View recent transcription
- Open the main app
- Access settings
- Pause/resume recording

### Main App

- **Sidebar** — Browse transcriptions by date
- **Detail view** — Read full transcriptions
- **Search** — Find any conversation (⌘F)
- **Export** — Copy or export transcriptions

### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| ⌘N | New session |
| ⌘F | Search |
| ⌘, | Settings |
| ⌘Q | Quit |

## Privacy

Ambi is designed with privacy as a core principle:

- **100% local processing** — No data leaves your Mac
- **No audio storage** — Raw audio is discarded after transcription
- **No analytics** — We don't track anything
- **No network requests** — Works completely offline (after model download)

## Tech Stack

- Swift + SwiftUI
- whisper.cpp (via WhisperKit)
- GRDB.swift for SQLite storage
- AVFoundation for audio capture

## Contributing

Contributions welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) first.

## License

MIT License — see [LICENSE](LICENSE) for details.

---

Built with ❤️ by [Hari](https://github.com/hariPrasadCoder)
