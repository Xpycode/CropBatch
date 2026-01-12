# Sidebar UI Overhaul

**Date:** 2026-01-02
**Branch:** `ui-overhaul`

## Summary

Redesigned the CropBatch sidebar using Apple Human Interface Guidelines (HIG) patterns to improve usability, reduce visual clutter, and provide better progressive disclosure.

## Changes

### Before
- All options always visible, requiring scrolling
- Custom `CollapsibleSection` component
- Export button buried at bottom
- Redundant labels (e.g., "Snap to Edges" section with "Snap to Edges" toggle inside)
- Aspect Guide mixed into Snap section

### After
- Native SwiftUI `Form` with `Section(isExpanded:)` for proper macOS inspector styling
- Progressive disclosure: primary controls always visible, advanced options collapsed
- Sticky footer with Export button (no scrolling needed)
- Toggles integrated into section headers (saves vertical space)
- Auto-expand sections when enabling features

## Architecture

### New Sidebar Structure

```
┌─────────────────────────────────┐
│  Crop: [T] [B] [L] [R]          │  ← Always visible
│  [Reset Crop]                   │
├─────────────────────────────────┤
│  Aspect: [×] 16:9 4:3 1:1 ...   │  ← Always visible
├─────────────────────────────────┤
│  ▶ Snap to Edges       [toggle] │  ← Toggle in header
│    (options when expanded)      │
├─────────────────────────────────┤
│  Format: PNG JPEG HEIC ...      │  ← Always visible
│  Naming: [Keep Original|Pattern]│
│  Output: preview.png            │
├─────────────────────────────────┤
│  ▶ Quality & Resize             │  ← Collapsed by default
│  ▶ Watermark           [toggle] │  ← Toggle in header
│  ▶ Keyboard Shortcuts           │
├─────────────────────────────────┤
│  ~2.1 MB/image                  │  ← Sticky footer
│  [ Export All (5) ]             │
└─────────────────────────────────┘
```

### Key Components

| Component | Purpose |
|-----------|---------|
| `SidebarView` | Main container with Form and sticky footer |
| `CropControlsView` | T/B/L/R fields + Reset button |
| `AspectGuideView` | Aspect ratio guide buttons |
| `SnapOptionsView` | Threshold, center, debug options |
| `ExportFormatView` | Format picker, naming mode, output preview |
| `QualityResizeView` | Quality slider, suffix/pattern, resize controls |
| `ExportFooterView` | File size estimate + Export button (sticky) |

### State Persistence

Section expansion states are persisted via `@AppStorage`:
- `sidebar.snapExpanded`
- `sidebar.qualityResizeExpanded`
- `sidebar.watermarkExpanded`
- `sidebar.shortcutsExpanded`

## HIG Patterns Applied

1. **`Form` container** - Apple's recommended container for inspectors/settings
2. **`Section(isExpanded:)`** - Native collapsible sections with disclosure triangles
3. **`LabeledContent`** - Standard label-value pairs with automatic alignment
4. **`ControlGroup`** - Semantic grouping for related buttons
5. **`.controlSize(.small)`** - Appropriate sizing for sidebar controls
6. **`.formStyle(.grouped)`** - macOS grouped form appearance
7. **`.regularMaterial`** - System material for footer visual separation

## UX Improvements

### Toggle in Section Header
Saves vertical space by combining the section title with its enable toggle:

```swift
Section(isExpanded: $snapExpanded) {
    SnapOptionsView()
} header: {
    HStack {
        Text("Snap to Edges")
        Spacer()
        Toggle("", isOn: $state.snapEnabled)
            .labelsHidden()
    }
}
```

### Auto-Expand on Enable
When enabling a feature, the section automatically expands to show options:

```swift
.onChange(of: appState.snapEnabled) { _, isEnabled in
    if isEnabled {
        withAnimation { snapExpanded = true }
    }
}
```

### Sticky Export Footer
Export button is always accessible without scrolling:

```swift
VStack(spacing: 0) {
    Form { /* scrollable content */ }
    ExportFooterView()  // sticky at bottom
}
```

### Scrollbar Gutter Fix
The Form's `.grouped` style reserves space for a scrollbar gutter on the right edge, creating visual asymmetry with the section backgrounds. Fixed with:

1. **Hidden scroll indicators** - `.scrollIndicators(.hidden)` removes the scrollbar (trackpad scrolling still works)
2. **Trailing overlay** - Fills the gutter gap with matching background color:

```swift
Form { /* sections */ }
    .formStyle(.grouped)
    .scrollContentBackground(.hidden)
    .scrollIndicators(.hidden)
    .background(Color(nsColor: .windowBackgroundColor))
    .overlay(alignment: .trailing) {
        Color(nsColor: .controlBackgroundColor)
            .frame(width: 14)
            .ignoresSafeArea()
    }
```

This ensures symmetric appearance regardless of content overflow.

## Files Modified

- `CropBatch/ContentView.swift` - Major refactor of sidebar views
- `CropBatch/Views/ExportSettingsView.swift` - Updated `WatermarkSettingsSection`

## Notes

- Old unused views (`CropSectionView`, `ExportSectionView`, `CollapsibleSection`) remain in codebase but are no longer used
- ~~Minor warnings about nil coalescing operators in resize controls~~ (fixed - removed unnecessary `??` on non-optional Int types)
- Watermark section shows "Enable watermark to configure" when disabled
