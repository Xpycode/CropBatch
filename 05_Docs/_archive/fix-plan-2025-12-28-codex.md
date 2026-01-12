# CropBatch Issue Remediation Plan (Dependency-Ordered)

_Composed from the three 2025-12-28 code reviews plus AppleDoc/Sosumi/Xcode Swift MCP references (Quartz 2D Programming Guide, Swift Concurrency, Swift Argument Parser)._ 

## Overview
- **Goal:** Ship corrective fixes in a safe order, highest dependency first.
- **Source Inputs:**
  1. `docs/code-review-2025-12-28-214330Z.md`
  2. `docs/code-review-2025-12-28-224520.md`
  3. `docs/code-review-report-2025-12-28.md`
- **Apple References Used:** Quartz 2D coordinate system guidance (AppleDoc), Sosumi SwiftUI validation patterns, Xcode Swift MCP docs for Concurrency + `swift-argument-parser`.

## Step 1 — Normalize Vertical Coordinate Handling
- **Depends on:** Nothing.
- **Why first:** Core crop math is wrong, blocking every follow-up fix and alignment with Quartz coordinate rules.
- **Scope:**
  - Adjust `ImageCropService` crop rects to use bottom-origin math per AppleDoc Quartz 2D best practices.
  - Align `UIDetector` sampling so “top”/“bottom” suggestions match actual image edges.
  - Re-run overlay/preset sanity checks; update snapshot fixtures if they exist.

## Step 2 — Validate & Clamp User Crop Input
- **Depends on:** Step 1 (so clamped bounds match corrected geometry).
- **Scope:**
  - Funnel `CropSettingsView` edits through `AppState.adjustCrop`, clamping via Sosumi input-validation patterns.
  - Sanitize linked-edge propagation, preventing negatives and >image size values.
  - Add regression tests to ensure invalid ASCII input is coerced before persisting to state/service layers.

## Step 3 — Unify Preview & Export Pipelines
- **Depends on:** Steps 1–2 (accurate crop data & validation).
- **Scope:**
  - Extract a shared render pipeline (transforms → blur → crop → resize → encode) reusable by Batch Review and final export.
  - Cache intermediate previews to avoid redundant CG work; verify parity with export outputs.
  - Update tests/ui snapshots so preview thumbnails reflect transforms/blur/resize choices highlighted in review #1.

## Step 4 — Strengthen Export Preconditions (Collisions & Format-Only Runs)
- **Depends on:** Steps 1–3 to ensure destination rectangles are trustworthy.
- **Scope:**
  - During preflight, build the full set of planned destination URLs; fail fast (or auto-disambiguate) on duplicates to fix silent overwrites.
  - Teach `canExport` / `ActionButtonsView` that a pure format change (preserveOriginalFormat == false) is a valid export trigger.
  - Extend UI warnings to include collision diagnostics referencing the offending sources.

## Step 5 — Move Batch Work Off the Main Actor & Parallelize
- **Depends on:** Steps 1–4 so we parallelize correct logic.
- **Scope:**
  - Remove `@MainActor` from heavy `ImageCropService` entry points.
  - Use Swift Concurrency task groups (per Xcode Swift MCP guidance) to process inputs concurrently while marshalling progress updates back to the main actor.
  - Make CLI/export helpers async-safe; add perf regression harness (e.g., 50×4K images) to confirm UI remains responsive.

## Step 6 — Replace Deprecated `lockFocus` Calls with Core Graphics Contexts
- **Depends on:** Step 5 (shared pipeline stabilized post-concurrency changes).
- **Scope:**
  - Port resize/rotate/flip/blur helpers to explicit `CGContext` usage per AppleDoc Quartz 2D samples.
  - Remove macOS 14 deprecation warnings; profile to ensure throughput improvements.
  - Update unit tests comparing before/after pixels to catch regressions from the new drawing path.

## Step 7 — Optimize UI Rendering Hotspots
- **Depends on:** Step 6 (so drawing helpers are modernized before caching them).
- **Scope:**
  - Cache `CropEditorView.highQualityScaledImage` via `@State` + invalidation hooks; adopt `.equatable()` on static subviews noted in Review #2.
  - Measure with Instruments; ensure cached state invalidates when source image/size changes.

## Step 8 — Architectural & UX Polish
- **Depends on:** Steps 1–7 (foundational correctness/perf done).
- **Scope:**
  - Split `AppState` into focused sub-stores (ImageState, ExportState, UIState) as suggested in Review #3.
  - Modernize drag-and-drop + zoom calculations in `ContentView` using GeometryReader data.
  - Adopt `swift-argument-parser` (per Xcode Swift MCP guidance) for CLI robustness.
  - Optional UX extras: Touch Bar bindings, undo/redo toolbar buttons, etc., once core defects are resolved.

## QA & Verification Checklist (Run After Each Step)
1. **Unit Tests:** Geometry math, validation, and pipeline parity.
2. **UI Snapshots:** Overlay/preview/export comparisons.
3. **Performance:** Timeline traces for batch exports; confirm no main-thread stalls post-Step 5.
4. **Regression Matrix:** Sample set covering rotations, blurs, format changes, and rename patterns to ensure collisions + validation behave.
