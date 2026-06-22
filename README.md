# PPTiny

<img width="520" height="572" alt="image" src="https://github.com/user-attachments/assets/3a9a6eba-713e-4cec-9241-c243818cf9a2" />

[EN](https://github.com/HansonChan/PPTiny/blob/main/README.md) | [中文](https://github.com/HansonChan/PPTiny/blob/main/README_CN.md)

PPTiny is a small macOS app for one-click PowerPoint compression.

Current version: `1.0.0`

It accepts one or more `.pptx` files by drag-and-drop or file picker, compresses them in order, and keeps the original file name for the compressed result. The old original file is renamed with an `.old.pptx` suffix.

## Features

- Drag in one or multiple PPTX files.
- Review the file queue before compression.
- Remove files from the queue.
- Compress files sequentially.
- Keep the compressed file at the original path.
- Rename the original file to `name.old.pptx`, or `name.old-1.pptx` if needed.
- Downsample images to a 1080p-equivalent bound:
  - landscape: up to `1920x1080`
  - portrait: up to `1080x1920`
- Convert non-transparent PNG/BMP/TIFF images to JPEG.
- Compress audio/video with macOS `AVFoundation`, without requiring `ffmpeg`.
- Remove embedded PowerPoint fonts to reduce file size.
- Detect cloud placeholder files and show a clear download-first message.

## Requirements

- Apple Silicon Mac
- macOS 14 or later
- No `ffmpeg` or Homebrew dependency

The app is currently built for `arm64` only. Intel Mac support is intentionally not included.

## Build

```bash
swift build
```

The app version is managed in `VERSION`. The build script writes this value into `CFBundleShortVersionString`; `CFBundleVersion` defaults to `1` and can be overridden with `BUILD_NUMBER`.

## Run

```bash
./script/build_and_run.sh
```

This builds the SwiftPM app, stages `dist/PPTiny.app`, copies the app icon, applies ad-hoc signing, and launches the app.

## Packaged App

After running the build script, the app bundle is available at:

```text
dist/PPTiny.app
```

The app bundle contains only the app executable and icon. Runtime media compression uses macOS system frameworks.

## CLI Test Helper

A CLI target exists for testing the compression core:

```bash
swift run PPTinyCLI /path/to/file.pptx
```

The CLI uses the same compressor as the app and performs the same in-place replacement behavior.

## Privacy And Git Hygiene

This repository intentionally ignores local documents, generated decks, Office files, media files, build products, app bundles, local Codex state, and signing material.

Do not commit real customer decks, cloud-drive files, generated compression outputs, or signing credentials.

## Project Layout

```text
Sources/PPTiny/       SwiftUI macOS app
Sources/PPTinyCore/   PPTX compression engine
Sources/PPTinyCLI/    CLI test wrapper
Assets/AppIcon/       App icon assets
script/               Build and run script
tools/                Icon generation utility
```
