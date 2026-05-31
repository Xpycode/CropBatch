# How Penumbra Gets Flat AppKit-Style Toolbar Buttons

**From:** Penumbra sessions (2026-04-05)
**For:** CropBatch sessions struggling with toolbar button styling

---

## The Short Answer

Penumbra uses **four things together** — all four are required:

```xml
<!-- 0. Info.plist — THE MISSING KEY -->
<key>UIDesignRequiresCompatibility</key>
<true/>
```

```swift
// 1. PenumbraApp.swift — window style
.windowStyle(.hiddenTitleBar)

// 2. ContentView.swift — toolbar role
.toolbarRole(.editor)

// 3. ContentView.swift — real toolbar items with custom ButtonStyle
.toolbar {
    ToolbarItemGroup(placement: .navigation) {
        HStack {
            Button(action: { ... }) {
                Image(systemName: "plus")
            }
            .buttonStyle(FCPToolbarButtonStyle(isOn: .constant(false)))
        }
        .buttonStyle(.borderless)
    }
}
```

There is **no NSView injection**, **no NSToolbar subclassing**, **no AppKit button wrapping**. It's pure SwiftUI toolbar items with a custom `ButtonStyle`.

> **Critical:** Without `UIDesignRequiresCompatibility = true` in Info.plist, none of the
> SwiftUI modifiers matter — the system forces pill/capsule chrome regardless. This was
> the root cause of CropBatch's failed attempts on 2026-04-05.

---

## Why This Works (and why CropBatch's attempts failed)

### The macOS 26 toolbar chrome problem

Under `.windowStyle(.automatic)`, SwiftUI wraps every toolbar `Button` in an `NSToolbarItem` hosting view that **force-applies pill/capsule chrome**. Your `ButtonStyle.makeBody()` still runs, but the system draws its own background on top — so `FCPToolbarButtonStyle` appears to do nothing.

### What `.hiddenTitleBar` changes

`.hiddenTitleBar` removes the standard title bar and **relaxes** the chrome enforcement on toolbar items. The toolbar still exists (it's not removed!), but `NSToolbarItem` hosting views no longer apply their own background/border chrome. This lets your `ButtonStyle` actually control the visual appearance.

### The critical mistake CropBatch made

The session on 2026-04-05 tried two approaches that both failed:

1. **FCPToolbarButtonStyle under `.automatic`** — Chrome overridden by system. Correct diagnosis.

2. **Titlebar NSView injection** — This is the cookbook pattern where you remove all `.toolbar {}` items and inject an `NSView` as a titlebar accessory. This failed because:
   - It removed the real toolbar items
   - Under `.automatic`, the system uses toolbar items for safe area calculation
   - Removing them collapsed the safe area → `GeometryReader` got zero size
   - Switching to `.hiddenTitleBar` was also tried but **combined with removing toolbar items**, which is the wrong approach

**The fix that was never tried:** `.hiddenTitleBar` + **keep** real `.toolbar {}` items + `FCPToolbarButtonStyle`. This is exactly what Penumbra does.

---

## The FCPToolbarButtonStyle Implementation

From `Penumbra/Views/ToolbarButtonStyles.swift`:

```swift
struct FCPToolbarButtonStyle: ButtonStyle {
    @Binding var isOn: Bool
    private let themeManager = ThemeManager.shared

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .foregroundColor(isOn ? .white : .primary)
            .background(
                ZStack {
                    if isOn {
                        themeManager.accentColor
                    } else {
                        Color(nsColor: .gray.withAlphaComponent(0.2))
                    }
                    if configuration.isPressed {
                        Color.black.opacity(0.2)
                    }
                }
            )
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.black.opacity(0.2), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
            .animation(.spring(response: 0.3, dampingFraction: 0.5), value: isOn)
    }
}
```

For CropBatch, you'd simplify this — you don't need the `isOn` binding for non-toggle buttons:

```swift
struct FCPToolbarButtonStyle: ButtonStyle {
    var isOn: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .foregroundColor(isOn ? .white : .primary)
            .background(
                ZStack {
                    if isOn {
                        Color.accentColor
                    } else {
                        Color(nsColor: .gray.withAlphaComponent(0.2))
                    }
                    if configuration.isPressed {
                        Color.black.opacity(0.2)
                    }
                }
            )
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.black.opacity(0.2), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}
```

---

## The GeometryReader Risk

CropBatch's `CropEditorView` wraps the entire canvas in a `GeometryReader`:

```swift
// CropEditorView.swift
var body: some View {
    GeometryReader { geometry in
        Group {
            if viewSize.width > 0, viewSize.height > 0 {
                // ... editor content
            }
        }
        .onChange(of: geometry.size, initial: true) { _, newSize in
            viewSize = newSize
        }
    }
}
```

Penumbra does **not** use `GeometryReader` at the top level of its content. It uses `HSplitView` with `VStack` and fixed heights:

```swift
// Penumbra ContentView — mainContent
VStack(spacing: 0) {
    HSplitView { ... }
        .layoutPriority(1)
    ControlsRow(...)
        .frame(height: 50)
    // ...
}
```

### Why this matters

`.hiddenTitleBar` changes the safe area insets of the window's content region. `GeometryReader` reports the available size **after** safe area insets are applied. If the safe area changes unexpectedly, `GeometryReader` can briefly report zero or near-zero size.

### Mitigation strategy

When switching CropBatch to `.hiddenTitleBar`, the `GeometryReader` in `CropEditorView` may need:

1. **Guard against zero size** (already present — `if viewSize.width > 0, viewSize.height > 0`)
2. **Ignore safe area on the content** — add `.ignoresSafeArea()` to the outer container if needed
3. **Test:** The most likely issue is a one-frame flash where `GeometryReader` reports wrong size during window setup. The existing guard should handle this, but verify.

---

## Migration Checklist for CropBatch

1. **Info.plist:** Add `UIDesignRequiresCompatibility = true` ← **this is the key that makes everything work**
2. **CropBatchApp.swift:** Change `.windowStyle(.automatic)` → `.windowStyle(.hiddenTitleBar)`
3. **CropBatchApp.swift:** Add `.preferredColorScheme(.dark)` if not present (hiddenTitleBar looks best dark)
4. **ContentView.swift:** Add `.toolbarRole(.editor)` after `.toolbar { ... }`
5. **ContentView.swift:** Wrap toolbar buttons in `HStack` with `.buttonStyle(.borderless)` on container
6. **ContentView.swift:** Apply `FCPToolbarButtonStyle` to individual toolbar buttons
7. **Keep all existing `.toolbar {}` items** — do NOT remove them
8. **Test `CropEditorView`** — verify `GeometryReader` still gets correct size

---

## What NOT To Do

- Do NOT use NSView titlebar injection — unnecessary complexity
- Do NOT remove toolbar items — the system needs them for layout
- Do NOT subclass NSToolbar or NSToolbarItem — pure SwiftUI works fine
- Do NOT use `.windowStyle(.automatic)` with FCPToolbarButtonStyle — the chrome will override it
