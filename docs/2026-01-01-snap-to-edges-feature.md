# Snap to Edges Feature Implementation

**Date:** 2026-01-01
**Branch:** `snapping`

## Overview

Implemented automatic snap-to-edge functionality for crop handles. When dragging crop handles, they now snap to detected UI element edges in the image, making it easier to precisely crop screenshots.

## Features

### Edge Detection (3 methods combined)

| Method | Technology | Best For |
|--------|------------|----------|
| Rectangle Detection | `VNDetectRectanglesRequest` | Windows, dialogs, cards with clear corners |
| Contour Detection | `VNDetectContoursRequest` | UI element borders, buttons, outlines |
| Edge Detection | Core Image `CIEdges` filter | Color bars, separators, high-contrast lines |

All three methods run in parallel and results are merged with deduplication.

### Visual Feedback

- **Green handles**: Handle turns green when snapped to a detected edge
- **Green guide lines**: Appear near crop edges when a snap point is within 20px
- **Rectangle icon**: Label shows a rectangle icon when snapped
- **Edge count badge**: Shows number of detected edges in sidebar

### Controls

| Control | Action |
|---------|--------|
| Toggle switch | Sidebar → "Snap to Edges" toggle |
| **S** key | Toggle snap on/off (when editor focused) |
| **⌃ Drag** | Grid snap (10px increments) - unchanged |

## Files Changed

### New Files

- `CropBatch/Services/RectangleDetector.swift` - Detection service with three methods

### Modified Files

- `CropBatch/Models/AppState.swift`
  - Added `snapPointsCache`, `snapEnabled`, `isDetectingSnapPoints`
  - Added `activeSnapPoints`, `detectSnapPointsForActiveImage()`, `snapValue()`

- `CropBatch/Views/CropEditorView.swift`
  - Added `SnapGuidesView` overlay
  - Updated `CropHandlesView` with snap support
  - Updated `EdgeHandle` and `PixelLabel` with rectangle snap indicators
  - Added **S** keyboard shortcut

- `CropBatch/ContentView.swift`
  - Added snap toggle in sidebar
  - Added "S - Toggle snap" to keyboard shortcuts panel

## Technical Details

### SnapPoints Structure

```swift
struct SnapPoints: Equatable {
    var horizontalEdges: [Int]  // Y positions in pixels
    var verticalEdges: [Int]    // X positions in pixels

    func nearestHorizontalEdge(to value: Int, threshold: Int = 15) -> Int?
    func nearestVerticalEdge(to value: Int, threshold: Int = 15) -> Int?
    func merged(with other: SnapPoints, tolerance: Int = 5) -> SnapPoints
}
```

### Detection Configuration

```swift
static let screenshot = Configuration(
    minimumAspectRatio: 0.05,
    maximumAspectRatio: 1.0,
    maximumObservations: 25,
    minimumConfidence: 0.1,
    quadratureTolerance: 35.0,
    minimumSize: 0.01,
    detectContours: true,
    contourMinimumLength: 30,
    detectEdges: true,
    edgeIntensity: 1.5
)
```

### Coordinate System Notes

- Vision framework uses bottom-left origin (Y=0 at bottom)
- CropBatch uses top-left origin (Y=0 at top)
- Conversion: `topY = (1.0 - visionY) * imageHeight`

## Usage

1. Load a screenshot with UI elements
2. Ensure "Snap to Edges" toggle is on (default)
3. Drag any crop handle
4. Handle will snap to detected edges within 15px
5. Green visual feedback indicates active snap
6. Press **S** to quickly toggle snapping

## Enhancements (Completed)

- [x] **Option key bypass** - Hold ⌥ while dragging to temporarily disable snap
- [x] **Adjustable threshold** - Slider in sidebar (5-30px range, default 15px)
- [x] **Debug view** - Toggle shows all detected edges in orange, center lines in blue
- [x] **Snap to center lines** - Automatic horizontal/vertical center line snapping
