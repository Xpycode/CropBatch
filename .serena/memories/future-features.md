# CropBatch Future Features

**Last Updated:** 2025-12-29

## Completed Features
- [x] Undo/redo for crop adjustments (Cmd+Z / Cmd+Shift+Z)
- [x] Batch rename on export (pattern tokens: {name}, {index}, {counter}, {date}, {time})
- [x] Image rotation (90 CW/CCW, flip H/V) - Transform menu and toolbar
- [x] Resize on export (percentage, exact size, max width/height)
- [x] Draggable crop center bubble to reposition crop window
- [x] Dynamic crop handle positioning (centers on visible crop line)
- [x] Export overwrite warning with Rename option

## On Hold (For Later Session)
- [ ] Blur/Redact tool - See `docs/blur-feature-status.md` for details
- [ ] Watermark overlay
- [ ] Aspect ratio lock during crop
- [ ] Before/after comparison improvements
- [ ] Menu bar / status bar quick access
- [ ] Drag & drop export to Finder

## Blur Tool Status
**Status:** Disabled (code exists but commented out)
**Documentation:** `docs/blur-feature-status.md`

Key issues to fix:
1. CGImage Y-coordinate flip (bottom-left vs top-left origin)
2. Gesture priority conflicts between resize/move handles
3. State update race conditions during drag
4. Live preview performance with large images
