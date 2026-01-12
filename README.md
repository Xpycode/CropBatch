# CropBatch

A macOS app for batch cropping images with configurable edge trimming.

![macOS](https://img.shields.io/badge/macOS-15.0+-blue.svg)
![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)
![Version](https://img.shields.io/badge/version-1.2-brightgreen.svg)
[![Download](https://img.shields.io/badge/Download-v1.2-blue.svg)](https://github.com/Xpycode/CropBatch/releases/latest)
![Downloads](https://img.shields.io/github/downloads/Xpycode/CropBatch/total.svg)

## Screenshots

![CropBatch](03_Screenshots/mainwindow-1.png)
![CropBatch](03_Screenshots/mainwindow-2.png)
![CropBatch](03_Screenshots/mainwindow-3.png)
![Snap to Edges](03_Screenshots/mainwindow-4-mismatch-cropsnap.png)
![Watermark Icon](03_Screenshots/mainwindow-5-WatermarkIcon.png)
![Watermark Text](03_Screenshots/mainwindow-6-WatermarkText.png)

## Features

- **Batch Processing** — Import multiple images via drag & drop or file browser
- **Visual Crop Editor** — Draggable handles on the image preview
- **Watermarks** — Add image or text overlays with position, opacity, and styling
- **Snap-to-Edge** — Crop handles snap to detected UI element boundaries
- **Scrubber Controls** — Drag the T/B/L/R labels to quickly adjust crop values
- **Aspect Ratio Guides** — 16:9, 4:3, 1:1, 9:16, 3:2, 21:9 overlays
- **Multiple Export Formats** — PNG, JPEG, HEIC, TIFF, WebP
- **Resize Options** — Exact size, max width/height, or percentage scaling
- **Flexible Naming** — Keep original names with suffix, or use patterns
- **File Size Estimation** — Preview output size for current file and batch
- **Keyboard Shortcuts** — Arrow keys for navigation, Shift+Arrow for crop adjustment

## Installation

1. Download `CropBatch-1.2.dmg` from [Releases](https://github.com/Xpycode/CropBatch/releases/latest)
2. Open the DMG and drag CropBatch to Applications
3. Launch from Applications folder

## Usage

1. **Import** — Drop images onto the window or click Import Images
2. **Crop** — Drag handles on the preview, or scrub the T/B/L/R controls
3. **Configure** — Set format, naming, and resize options
4. **Export** — Click Export All to save cropped images

### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| ← → | Navigate images |
| ⇧ Arrow | Adjust crop |
| ⇧⌥ Arrow | Uncrop (expand) |
| ⇧⌃ Arrow | Adjust by 10px |
| ⌘1/2/3/4 | Zoom modes |
| S | Toggle snap-to-edge |

## Building from Source

Requires Xcode 16+ and macOS 15.0+

```bash
git clone https://github.com/Xpycode/CropBatch.git
cd CropBatch/01_Project
xcodebuild -scheme CropBatch -configuration Release
```

## License

MIT
