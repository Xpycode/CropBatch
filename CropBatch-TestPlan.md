# CropBatch Test Plan
## Phase 1 - Image Import & Management
### Drag & Drop
- [x] Drop single PNG onto main window
- [x] Drop single JPEG onto main window
- [x] Drop multiple images at once (mixed formats)
- [x] Drop images when images already loaded
- [x] Unsupported formats ignored gracefully
### File Import
- [x] Toolbar "+" button opens import panel
- [x] Import multiple images via Open Panel
- [x] First image becomes active after import
### Image List Management
- [x] Select images via thumbnail strip click
- [x] Navigate using left/right arrow keys
- [x] Active image has blue border highlight
- [x] Remove single image via context menu
- [x] Clear All button removes all images
- [x] Reorder images via drag in thumbnail strip
## Phase 2 - Crop Editor
### Visual Crop Handles
- [x] Drag top handle updates overlay live
- [x] Drag bottom handle
- [x] Drag left handle
- [x] Drag right handle
- [x] Drag corner handles (adjusts two edges)
- [x] Double-click handle resets that edge to 0
- [x] Double-click corner resets both edges
### Center Bubble Repositioning
- [x] Drag center bubble slides crop window
- [x] Crop values update while dragging
- [x] Cursor changes to hand on hover/drag
### Sidebar Crop Controls
- [x] Enter values in T/B/L/R number fields
- [x] Preview updates when pressing Enter
- [x] Reset button clears all crop values
### Keyboard Shortcuts
- [x] Shift+Arrow increases crop on opposite edge
- [x] Shift+Option+Arrow decreases crop (uncrop)
- [x] Shift+Control+Arrow gives 10x adjustment
- [x] Control+Drag snaps to 10px grid (orange handles)
### Crop Validation
- [x] Cannot crop beyond minimum 10px remaining
- [x] Values clamp when switching image sizes
## Phase 3 - Zoom & Display
### Zoom Modes
- [x] 100% mode (Cmd+1) shows actual pixels
- [x] Fit mode (Cmd+2) fits in viewport
- [x] Fit Width mode (Cmd+3) fills horizontal
- [x] Fit Height mode (Cmd+4) fills vertical
- [x] Zoom bubble shows percentage and dimensions
- [x] Large images trigger scroll view
- [x] Small images center in viewport
## Phase 4 - Image Transforms
### Rotation
- [x] Rotate Left button works (Cmd+[)
- [x] Rotate Right button works (Cmd+])
- [x] Image rotates 90 degrees each click
- [x] Rotation indicator in zoom bubble
- [x] 4 rotations return to original
### Flip
- [x] Flip Horizontal button works
- [x] Flip Vertical button works
- [x] Transform indicator shows when modified
### Reset
- [x] Reset button clears all transforms
### Transform + Crop Interaction
- [x] Crop then rotate exports correctly
- [x] Rotate then crop exports correctly
## Phase 5 - Crop Presets
### Preset Selection
- [x] Open Preset dropdown menu
- [x] Select preset updates crop values
- [x] None (Reset) clears all values
### Preset Categories
- [x] iOS presets visible and functional
- [x] macOS presets visible and functional
- [x] Custom presets visible (if saved)
## Phase 6 - Advanced Crop Options
### Edge Link Mode
- [x] None mode - edges independent
- [x] Top/Bottom link mode works
- [x] Left/Right link mode works
- [ ] All Edges link mode works
### Aspect Ratio Guide
- [x] 16:9 guide overlay appears
- [x] 4:3 guide overlay appears
- [x] 1:1 square guide overlay appears
- [x] 9:16 portrait guide overlay appears
- [x] Disable guide removes overlay
## Phase 7 - Export Basic
### Export Flow
- [x] Export All saves all images
- [ ] Export Selected saves only selected
- [x] Progress bar shows during export
- [x] Success alert appears after export
### Export Formats
- [ ] Export as PNG (lossless)
- [ ] Export as JPEG with quality slider
- [ ] Export as HEIC
- [ ] Export as WebP
- [ ] Export as TIFF
- [ ] Keep original format toggle works
## Phase 8 - Export Options
### Naming Options
- [ ] Keep Original with suffix works
- [ ] Pattern mode with {name} token
- [ ] Pattern mode with {counter} token
- [ ] Pattern mode with {index} token
- [ ] Pattern mode with {date} token
- [ ] Pattern mode with {time} token
### Overwrite Handling
- [ ] Overwrite option replaces existing files
- [ ] Rename option adds _1 _2 suffix
- [ ] Cancel option aborts export
### Resize on Export
- [ ] Exact Size mode works
- [ ] Max Width mode scales correctly
- [ ] Max Height mode scales correctly
- [ ] Percentage mode works
- [ ] Maintain aspect ratio toggle works
## Phase 9 - UI Feedback
### Resolution Mismatch Warning
- [ ] Warning banner appears for mixed sizes
- [ ] Lists mismatched files with dimensions
- [ ] Badge appears on mismatched thumbnails
### File Size Estimation
- [ ] Estimate shows in More Options
- [ ] Estimate updates with format changes
- [ ] Estimate updates with quality changes
## Phase 10 - Thumbnail Strip
### Navigation
- [ ] Click thumbnail to select
- [ ] Horizontal scroll works smoothly
- [ ] Current image counter shows X/Y
### Loop Navigation
- [ ] Toggle loop button works
- [ ] Left arrow at first goes to last
- [ ] Right arrow at last goes to first
- [ ] Infinite carousel scroll smooth
### Context Menu
- [ ] Set as Active works
- [ ] Copy Cropped to Clipboard works
- [ ] Quick Export opens save dialog
- [ ] Remove deletes the image
### Drag Reorder
- [ ] Drag thumbnail to new position
- [ ] Drop indicator appears correctly
- [ ] Order persists after drop
## Phase 11 - Folder Watch
### Setup
- [ ] Expand Folder Watch section
- [ ] Select input folder works
- [ ] Select output folder works
### Auto-Processing
- [ ] Start watching activates monitor
- [ ] New image in folder auto-processes
- [ ] Output saved to correct folder
- [ ] Notification appears on process
- [ ] Processed count updates
- [ ] Stop watching deactivates monitor
## Phase 12 - Undo/Redo
### History
- [ ] Cmd+Z undoes crop change
- [ ] Cmd+Shift+Z redoes undone change
- [ ] History persists through presets
## Phase 13 - Edge Cases
### Error Handling
- [ ] Corrupted image file handled gracefully
- [ ] Export to read-only folder shows error
- [ ] Very large image (8000x6000) performs OK
- [ ] Many images (50+) scrolls smoothly
- [ ] Window resize adapts UI correctly
- [ ] Quit and relaunch - no crash