# CropBatch — Project Instructions

## What Is This
macOS batch image cropping app. Born from needing to crop iOS screenshots for pdf2calendar.eu documentation.

**Read `05_Docs/PROJECT_STATE.md` for current status.**

## Tech Stack
- macOS 15.0+ / Swift 6.0 / SwiftUI
- Xcode 16+
- Notarized for distribution (not sandboxed)

## Project Structure
```
01_Project/     — Xcode project and source
02_Design/      — Design assets (.afdesign, icons)
03_Screenshots/ — App screenshots for README
04_Exports/     — Built .app and .dmg
05_Docs/        — Directions documentation system
```

## Key Architecture

### Image Processing Pipeline
```
Blur → Transform → Crop → Corner Mask → Resize → Watermark
```
Each step depends on the previous. Order matters.

### Core Files
| File | Purpose |
|------|---------|
| `ImageCropService.swift` | Processing pipeline |
| `CropSettings.swift` | Crop configuration model |
| `AppState.swift` | Main app state |
| `BlurManager.swift` | Blur regions management |
| `CropManager.swift` | Crop state management |

## Conventions
- Feature branches: `feature/name` or just `name`
- PNG required for transparency features (corner radius, etc.)
- "Works for me" polish level — don't over-engineer edge cases

## Current Work
See `05_Docs/PROJECT_STATE.md` for branches in flight and next actions.
