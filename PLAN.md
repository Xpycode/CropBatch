# Execution Plan: Production Hardening — pre-v1.4

## Goal
Fix the 4 real issues found in the production review (1 High, 3 Medium). One reviewer finding
was a false positive (ThumbnailCache) — no action needed there.

---

## False Positive: ThumbnailCache TOCTOU — NO ACTION

The reviewer flagged an actor re-entrancy race between `inFlight[key]` check and write.
This cannot happen: there are zero suspension points between those two lines. An actor
serializes all synchronous sequences. The code is correct as written.

---

## Issues to Fix (Priority Order)

### Issue 1 — HIGH: `@MainActor` missing from `@Observable` model classes

**Files:** `ImageManager.swift`, `BlurManager.swift`, `CropManager.swift`,
`SnapPointsManager.swift`, `AppState.swift`

**Why it matters:** In Swift 6, `@Observable` without `@MainActor` permits mutation from any
concurrency context. The current code patches this per-call with `Task { @MainActor in }` hops,
but the compiler doesn't enforce it. One missed call site = a data race.

**The fix:** Add `@MainActor` above `@Observable` on each of the 5 classes. One line per file.

**Expected compiler impact:** Minimal. `processAndExport` and all async methods are already
explicitly `@MainActor`. The `Task { @MainActor in self?.isProcessing = false }` hops inside
them become redundant but compile cleanly. The Swift 6 compiler will flag any genuinely unsafe
call sites — fix those as they appear.

**Note on sub-managers:** ImageManager, BlurManager, CropManager, SnapPointsManager are only
accessed through AppState (which is `@MainActor` after this fix), so they're safe to mark too.
Doing it anyway enforces it at the type level, not just at the call site.

```swift
// Before
@Observable
final class ImageManager {

// After
@MainActor
@Observable
final class ImageManager {
```

Apply to all 5. Do AppState last (gives clearer compiler errors if any exist in sub-managers first).

---

### Issue 2 — MEDIUM: `FolderWatcher.processNewFile` uses `DispatchQueue.main.asyncAfter`

**File:** `Services/FolderWatcher.swift` line ~115

**Why it matters:** `FolderWatcher` is `@MainActor`. Using `DispatchQueue.main.asyncAfter`
inside a `@MainActor` method bypasses actor isolation — the closure runs on the dispatch queue
without the actor's guarantee, creating a conceptual inconsistency and a potential Swift 6 warning.

**The fix:** Replace `DispatchQueue.main.asyncAfter(deadline: .now() + 0.5)` with a structured
async delay inside a `@MainActor` Task:

```swift
// Before
private func processNewFile(_ url: URL) {
    guard let outputFolder = outputFolder else { return }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
        guard let self = self else { return }
        do { ... } catch { ... }
    }
}

// After
private func processNewFile(_ url: URL) {
    guard let outputFolder = outputFolder else { return }
    Task { @MainActor [weak self] in
        try? await Task.sleep(for: .milliseconds(500))
        guard let self else { return }
        do { ... } catch { ... }
    }
}
```

The body of the closure is unchanged — only the outer wrapper changes.

---

### Issue 3 — MEDIUM: Watermark drop gives no user feedback on load failure

**File:** `Views/ExportSettingsView.swift` — `loadWatermarkImage(from:isSecurityScoped:)`

**Why it matters:** If `Data(contentsOf: url)` fails (permissions, file moved, I/O error),
the error is logged but the user sees nothing. They're left wondering why the watermark didn't load.

**The fix:** Surface the error through the view's local state.

Step 1: Identify where `loadWatermarkImage` lives — it's a private func inside a view struct
(or its container). Confirm the exact struct name, then add a `@State var watermarkError: String?`.

Step 2: In `loadWatermarkImage`, set `watermarkError = "Could not load watermark image."` in the
guard's else branch (keep the logger call too):

```swift
guard let imageData = try? Data(contentsOf: url),
      let image = NSImage(data: imageData) else {
    CropBatchLogger.ui.error("Failed to load watermark image from: \(url.path)")
    watermarkError = "Could not load watermark image."  // NEW
    return
}
watermarkError = nil  // clear on success — NEW
```

Step 3: Show the error. Find the watermark section's UI — add a small inline error label
next to where the watermark thumbnail is shown (or use `.alert`):

```swift
// Inline (preferred — stays in context):
if let error = watermarkError {
    Text(error)
        .font(.caption)
        .foregroundStyle(.red)
}

// OR: reuse the existing alert pattern in ExportSettingsView if one already exists
```

Inline label is preferred over an alert — it's lower friction for a recoverable UI action.

---

### Issue 4 — LOW: Drop handler passes `isSecurityScoped: false`

**File:** `Views/ExportSettingsView.swift` — `handleDrop(_:)`

**Why it matters:** The file-picker path (`handleFileSelection`) correctly calls
`loadWatermarkImage(from: url, isSecurityScoped: true)`. The drag-drop path calls
`loadWatermarkImage(from: url)` (defaulting to `false`). For the current non-sandboxed app,
`startAccessingSecurityScopedResource()` returns `false` and is a no-op anyway — so there's
no actual bug. But the inconsistency is a gotcha if sandboxing is ever enabled.

**The fix:** One character change.

```swift
// Before
loadWatermarkImage(from: url)

// After
loadWatermarkImage(from: url, isSecurityScoped: true)
```

---

## Wave Plan

### Wave 1 — Compiler-validated (do together, build after)
- [x] **1.1** Add `@MainActor` to `ImageManager.swift`
- [x] **1.2** Add `@MainActor` to `BlurManager.swift`
- [x] **1.3** Add `@MainActor` to `CropManager.swift`
- [x] **1.4** Add `@MainActor` to `SnapPointsManager.swift`
- [x] **1.5** Add `@MainActor` to `AppState.swift`
- [x] **1.6** Clean build — fix any new compiler errors
- [x] **1.7** Fix `FolderWatcher.processNewFile` dispatch → Task
- [x] **1.8** Fix drop handler `isSecurityScoped` (1 word change)

### Wave 2 — UI change (requires verifying the view layout first)
- [x] **2.1** Add `@State var watermarkError: String?` to watermark view
- [x] **2.2** Set `watermarkError` in `loadWatermarkImage` guard else branch
- [x] **2.3** Add inline error label to watermark UI section
- [ ] **2.4** Manual test: drag a non-image file onto watermark drop zone → error appears

### Deferred
- Large files (ExportSettingsView 1,484 lines) — "works for me" policy, not a correctness issue
- ThumbnailCache — no issue (false positive, actor prevents the race)

---

## Definition of Done
- [x] Clean build, zero errors or warnings introduced by these changes
- [x] Watermark error message visible in UI when load fails (code done, needs manual test)
- [x] FolderWatcher uses Task-based delay (no DispatchQueue.main.asyncAfter)
- [x] All 5 model classes have `@MainActor`
- [ ] Ready for v1.4 release prep

---
*Created 2026-04-03. Replaces previous quality-fixes plan (complete).*
