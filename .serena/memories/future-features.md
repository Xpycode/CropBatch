# CropBatch Future Features

## Next Up (Approved) - Plan Ready: docs/implementation-plan-2025-12-28.md
- [ ] Undo/redo for crop adjustments (infrastructure exists, add UI/menu)
- [ ] Batch rename on export (pattern tokens: {name}, {index}, {date})
- [ ] Image rotation (90 CW/CCW, flip H/V via CGAffineTransform)

## On Hold (For Later Session)
- [ ] Blur/Redact tool (disabled - needs coordinate/gesture fixes)
- [ ] Watermark overlay
- [ ] Aspect ratio lock during crop
- [ ] Before/after comparison improvements
- [ ] Menu bar / status bar quick access
- [ ] Drag & drop export to Finder

## Blur Tool Issues (Reference)
When revisiting blur:
- CGImage Y-coordinate flip (bottom-left vs top-left origin)
- SwiftUI blur filter caching (needs `.id(intensity)`)
- Gesture priority conflicts between resize/move handles
- State update race conditions during drag (use local state pattern)
