# CropBatch Future Features

**Last Updated:** 2025-12-29

## Completed Features
- [x] Undo/redo for crop adjustments (Cmd+Z / Cmd+Shift+Z)
- [x] Batch rename on export (pattern tokens: {name}, {index}, {counter}, {date}, {time})
- [x] Resize on export (percentage, exact size, max width/height)
- [x] Draggable crop center bubble to reposition crop window
- [x] Dynamic crop handle positioning (centers on visible crop line)
- [x] Export overwrite warning with Rename option

## Shelved Features (2025-12-31)
The following features are disabled (`#if false`) to simplify the app:
- **Rotation/Flip transforms** - Works but breaks crop state; code in TransformRowView and Image menu
- **Presets** - Shelved in CropSectionView and Crop menu
- **Folder Watch** - Shelved CollapsibleSection in SidebarView
- **Blur/Redact** - Already hidden; coordinate issues documented in blur-feature-status.md

Core focus: Load images → Configure crop → Export batch

## Recently Implemented
- [x] Rectangle snapping - Crop handles snap to detected rectangle edges in images (Vision framework VNDetectRectanglesRequest)

## On Hold (For Later Session)
- [ ] Blur/Redact tool - See `docs/blur-feature-status.md` for details
- [x] Watermark overlay (PNG image with position, size, opacity, margin controls)
- [ ] Aspect ratio lock during crop
- [ ] Before/after comparison improvements
- [ ] Menu bar / status bar quick access
- [ ] Drag & drop export to Finder

## Blur Tool Status
**Status:** Re-enabled on `blur-again` branch (2026-01-06)
**Documentation:** `docs/blur-feature-status.md`

### Fixed Issues:
- ✅ Intensity slider now updates selected region (was only setting default for new regions)
- ✅ Style picker now updates selected region
- ✅ Blur, Black, White styles work with live preview

### Remaining Work:
- [ ] **Pixelate live preview** - Currently hidden. SwiftUI has no `.pixelate()` modifier like `.blur()`. Options:
  - Use CIPixellate filter with cached rendering
  - Downscale/upscale approximation
  - Keep grid indicator (current placeholder approach)
- [ ] **Edge gradient artifact** - Blur regions touching image edges show gradient fade due to edge pixel clamping. Tried mirroring approaches (manual + CIAffineTile) but they didn't work or caused performance issues. Would need Metal shader or more complex solution.
- [ ] Performance optimization for large images (throttle slider if needed)
