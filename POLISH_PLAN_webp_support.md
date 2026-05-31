# POLISH_PLAN — REAL WebP export support (CropBatch)

Plan written 2026-05-29 via /ultrathink + 3 parallel research agents (SDWebImageWebPCoder web recon · CropBatch export-flow source recon · CropBatch .xcodeproj/build-sign recon). Adapted from `../ScreenshotFromVideos/POLISH_PLAN_webp_support.md` — but CropBatch's situation differs materially (see "Why now").

## Goal

Make WebP export **actually work**. Route WebP writes through SDWebImageWebPCoder (added via SPM) instead of ImageIO/`CGImageDestination`, which cannot encode WebP on macOS. Surface the encoder's two meaningful capabilities: lossless vs lossy mode, and the quality/effort dial.

## Why now — CropBatch ships a *broken* WebP option, not a missing one

Unlike ScreenshotFromVideos (which deliberately dropped WebP), CropBatch already **exposes** WebP everywhere the user can see it:

- `ExportFormat.webp` exists with `utType = .webP` (`Models/ExportSettings.swift:10,20`)
- Two presets ship it: **"WebP High (90%)"** and **"WebP Web (75%)"** (`Models/ExportSettings.swift:388-396`)
- The sidebar format button appears automatically via `ExportFormat.allCases`

…but every write path routes WebP through ImageIO. Verified on macOS 26.5:

```
CGImageDestinationCopyTypeIdentifiers() → WebP writable: false
```

So **selecting a WebP preset and exporting fails** — `CGImageDestinationFinalize` returns false → `ImageCropError.failedToWriteImage`; Quick Export throws "Failed to encode image". The option has been dead since it shipped. This plan converts a visible-but-broken feature into a working one. User has a paid Apple Developer account; hardened-runtime + notarization stay clean with SDWebImageWebPCoder (pure-source SPM build, no dlopen/JIT/binaryTarget).

## Verified facts (research, 2026-05-29)

- **SDWebImageWebPCoder 0.15.0** (tagged 2025-11-03) is latest. Adds ICC-profile embedding on encode. Pulls **SDWebImage** core (5.21.x) + **libwebp** (1.5.x via libwebp-Xcode), both pure-source SPM C/Obj-C targets — no binary blobs, no dlopen, no JIT. Estimated **~2–4 MB** app-binary growth (measure after integration).
- **Encode API:** `SDImageWebPCoder.shared.encodedData(with: nsImage, format: .webP, options: opts) -> Data?` (Obj-C `sharedCoder` imports as Swift `.shared`). `SDImageFormatWebP = 4` → `.webP`.
- **Options (exact, verified against headers):**
  - `.encodeCompressionQuality` → `NSNumber` in **0.0–1.0** (coder multiplies ×100 internally; defaults to 1.0 if unset).
  - `SDImageCoderEncodeWebPMethod` → `NSNumber(Int)` in **0–6** (0=fast, 6=slow/best). **Out-of-range fails the encode** — must clamp.
  - `SDImageCoderEncodeWebPLossless` → `NSNumber(0/1)`. When lossless=1, the quality param becomes **compression effort** (100 = max compression).
- **Correction to the SFV plan's decision #4:** issue #116 ("low quality vs cwebp") is primarily about **lossless** mode, not the lossy "method=4 vs 6" gap. The library's default **and** cwebp's default are both `method=4`; the library is *not* secretly worse. No primary-source benchmark proves "method=6 closes the gap with cwebp." `method=6` is still sound — it genuinely gives better quality/size at a given `q` — but it's an absolute-quality choice, not a cwebp-parity fix. See decision #4 below for the revised rationale.
- **Swift 6 / strict concurrency:** these are Obj-C modules without `Sendable` audit. Under Swift 6 mode (CropBatch is `SWIFT_VERSION = 6.0`, no explicit strict-concurrency flag → defaults to complete) use `@preconcurrency import`. `SDImageWebPCoder.shared` is a stateless singleton with per-call libwebp state — safe to call off the main actor (which is where `batchCrop`'s TaskGroup runs).
- **Notarization:** no rejection reports for SDWebImageWebPCoder/SDWebImage/libwebp-Xcode; all statically compiled from source. No `com.apple.security.cs.*` entitlement expected (Sparkle already ships under CropBatch's empty-entitlements + hardened-runtime config).

## Key decisions

### 1. SDWebImageWebPCoder 0.15.0 via SPM, accepting ~2–4 MB growth

Trade-off accepted: maintenance is upstream, ICC-embed comes free, and the alternative — depending directly on `libwebp-Xcode` and owning a ~50-LOC `CGImage→RGBA→WebPEncodeRGBA` bridge — adds C-interop we'd maintain forever. **Future-shrink option logged but out of scope:** drop SDWebImage core and bridge `libwebp-Xcode` directly (~1.5–2.5 MB shrink) if binary size ever becomes a concern.

### 2. Do **not** register the coder with `SDImageCodersManager`

We call `SDImageWebPCoder.shared.encodedData(...)` directly. Registering the coder globally is only needed to teach SDWebImage's *decode* pipeline / `NSImage(data:)` about WebP — we don't use those. Skipping registration avoids an app-launch side effect and keeps the dependency's surface area to exactly one call site.

### 3. Reuse the existing Quality slider; add a Lossless toggle; relabel "Quality"→"Effort" when WebP + lossless

CropBatch already has a `quality` slider gated on `format.supportsCompression`. libwebp reuses `quality` as encoding **effort** when `lossless=1` (q=100 = slowest + smallest; q=0 = fast + larger). One slider, two semantic roles, conditional label flip. Backing variable stays `exportSettings.quality`. A `.help()` tooltip explains the dual semantics.

### 4. Hardcode `method=6` on every WebP encode — but as a tunable constant, with eyes open on batch cost

`method=6` gives the best quality/size libwebp offers at a given `q`. CPU cost ≈ 2–3× per image vs `method=4`. **CropBatch is a batch tool** (parallel `TaskGroup` across N images), so this multiplies more visibly than in SFV's short-clip case. Decision: default `method=6` for quality, defined as a **single `private static let webpMethod = 6` constant** in `WebPEncoder` so it's a one-line change. If a user reports slow large-batch WebP encodes, drop to `4` (the cwebp default) — quality delta is modest. (Revised rationale vs SFV: this is an absolute-quality choice, not a verified cwebp-parity fix — see "Verified facts".)

### 5. Convert CGImage to sRGB before handing it to the encoder

CropBatch inputs are screenshots/images, often already sRGB or Display P3. libwebp writes pixel data as-is; a Display-P3-tagged image written untagged would shift on color-managed viewers. Convert via a transient `CGContext` backed by `CGColorSpace(name: CGColorSpace.sRGB)!` before wrapping in `NSImage`. This matches what `CGImageDestination` did implicitly for the PNG/JPG/HEIC paths, so WebP output stays color-consistent with the other formats. 0.15.0 also embeds the resulting sRGB ICC profile.

### 6. `@preconcurrency import` for both modules

`@preconcurrency import SDWebImageWebPCoder` + `@preconcurrency import SDWebImage` in `WebPEncoder.swift` only. Suppresses Sendable diagnostics on the options dict and the `.shared` hop under Swift 6 mode. No other file imports these.

### 7. Thread `lossless` explicitly — `save()` is `UTType`-based and carries no quality/lossless metadata

CropBatch's central writer `save(_:to:format:quality:)` takes a `UTType`, which encodes the *format* but nothing about lossless. So the flag can't be inferred at the write boundary — it must be passed as an explicit parameter from each call site (every call site already has `exportSettings` in scope). Add `lossless: Bool = false` to both `save()` and `encode()`; non-WebP callers and tests are unaffected by the default.

### 8. Fix **both** write paths and the CLI selector gap — there are six broken flows

Recon found WebP is broken in *every* export flow, via two functions:
- `ImageCropService.save()` (`UTType` → ImageIO) backs **batch, rename, save-in-place, CLI, and folder-watcher**.
- `ImageCropService.encode()` (`ExportFormat` → ImageIO) backs **Quick Export** (single-image context menu, `ThumbnailStripView.swift:475`).

Fixing only `save()` would leave Quick Export broken. Additionally, the **CLI `--format` parser has no `webp` case** (`CLIHandler.swift:87-94`) — WebP can't even be *selected* from the command line today. All three must change.

## Knobs deliberately skipped

- **`image_hint`** — affects lossless only; default fine for varied screenshot content.
- **`method` slider** — hardcoded to 6 (decision 4); exposed as a code constant, not UI.
- **`alpha_quality` / `alpha_compression` / `alpha_filtering` / `sharp_yuv`** — defaults match cwebp; revisit only on a user color/alpha complaint.
- **`near_lossless`** — default 100 (off) is right for a crop/export tool.

## Files & changes

### 1. `01_Project/CropBatch.xcodeproj` — add SPM dependency (Xcode GUI — **user must do this**)

Claude cannot author the pbxproj package fragments headlessly with correct UUIDs, and the transitive graph (SDWebImageWebPCoder → SDWebImage + libwebp) means **three** packages' worth of fragments. Do it in Xcode:

> **File ▸ Add Package Dependencies…** → URL `https://github.com/SDWebImage/SDWebImageWebPCoder` → rule **Up to Next Major Version**, `0.15.0` → select the **`SDWebImageWebPCoder`** product → add to the **CropBatch** target.

Xcode writes the 6 pbxproj fragments (mirroring the existing **Sparkle** wiring), links the product into the Frameworks build phase, resolves SDWebImage + libwebp transitively, and updates `…/swiftpm/Package.resolved` (gains 2–3 pins; `originHash` auto-recomputed — don't hand-edit). Manual pbxproj editing is documented as a fallback but strongly discouraged here.

### 2. `01_Project/CropBatch/Services/WebPEncoder.swift` — NEW (~55 LOC)

Self-contained. The only file importing the new modules.

```swift
@preconcurrency import SDWebImageWebPCoder
@preconcurrency import SDWebImage
import AppKit
import CoreGraphics

/// Encodes images to WebP via SDWebImageWebPCoder (ImageIO cannot write WebP on macOS).
/// Lift source: SDWebImageWebPCoder 0.15.0 + sRGB-convert-before-encode pattern.
enum WebPEncoder {
    /// libwebp method 0–6 (0=fast, 6=slow/best). Quality choice, not cwebp parity.
    /// Drop to 4 if large-batch WebP encoding feels slow.
    private static let webpMethod = 6

    /// Encodes to in-memory WebP Data. Used by Quick Export.
    static func encodedData(from image: NSImage, quality: Double, lossless: Bool) throws -> Data {
        let srgb = try srgbImage(from: image)
        var opts: [SDImageCoderOption: Any] = [
            .encodeCompressionQuality: NSNumber(value: max(0, min(1, quality))),
            SDImageCoderEncodeWebPMethod: NSNumber(value: webpMethod),
        ]
        if lossless { opts[SDImageCoderEncodeWebPLossless] = NSNumber(value: true) }
        guard let data = SDImageWebPCoder.shared.encodedData(with: srgb, format: .webP, options: opts) else {
            throw ImageCropError.failedToWriteImage
        }
        return data
    }

    /// Encodes and writes to disk. Used by the batch/save() path.
    static func encode(_ image: NSImage, to url: URL, quality: Double, lossless: Bool) throws {
        let data = try encodedData(from: image, quality: quality, lossless: lossless)
        try data.write(to: url)
    }

    /// Redraws into an sRGB context so libwebp writes color-consistent, ICC-tagged pixels.
    private static func srgbImage(from image: NSImage) throws -> NSImage {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ImageCropError.failedToGetCGImage
        }
        guard let ctx = CGContext(
            data: nil, width: cg.width, height: cg.height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGImageByteOrderInfo.order32Big.rawValue
        ) else { throw ImageCropError.failedToCreateContext }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        guard let out = ctx.makeImage() else { throw ImageCropError.failedToGetCGImage }
        return NSImage(cgImage: out, size: NSSize(width: cg.width, height: cg.height))
    }
}
```

### 3. `01_Project/CropBatch/Services/ImageCropService.swift` — branch both writers (~12 LOC)

`save()` (line 738) — add param + early branch:
```swift
static func save(_ image: NSImage, to url: URL, format: UTType = .png,
                 quality: Double = 0.9, lossless: Bool = false) throws {
    if format == .webP {
        try WebPEncoder.encode(image, to: url, quality: quality, lossless: lossless)
        return
    }
    // …existing CGImageDestination path unchanged for PNG/JPG/HEIC/TIFF…
```

`encode()` (line 772) — split WebP out of the `.heic, .webp` case:
```swift
static func encode(_ image: NSImage, format: ExportFormat,
                   quality: Double = 0.9, lossless: Bool = false) -> Data? {
    …
    case .webp:
        return try? WebPEncoder.encodedData(from: image, quality: quality, lossless: lossless)
    case .heic:
        // …existing CGImageDestination-with-data path (HEIC only now)…
```

Update the internal call site `processSingleImage` (line 1019): `…, quality: exportSettings.quality, lossless: exportSettings.lossless)`.

### 4. `01_Project/CropBatch/Models/ExportSettings.swift` — add `lossless` (~12 LOC)

- `ExportSettings` (line 126): add `var lossless: Bool = false` after `quality`. All defaults preserved → memberwise-init call sites keep compiling.
- `ExportSettingsCodable` (line 429): add **`var lossless: Bool?`** (Optional → synthesized `CodingKeys` decode old profiles as `nil`, backward-compatible — mirrors the existing optional `watermarkSettings`/`gridSettings` pattern). In `init(from:)`: `self.lossless = settings.lossless ? true : nil`. In `toExportSettings()`: append `settings.lossless = lossless ?? false`.
- (Optional) add a **"WebP Lossless"** preset near line 396: `ExportSettings(format: .webp, lossless: true, suffix: "_cropped")` (icon `"square.stack.3d.up"` or similar).

### 5. `01_Project/CropBatch/Models/AppState.swift` — rename/conflict path (~2 LOC)

The direct `save()` call at **line 621** must forward the flag: `…, quality: capturedExportSettings.quality, lossless: capturedExportSettings.lossless)`. (The main `processAndExport` / save-in-place paths go through `batchCrop` → `processSingleImage`, already covered by change #3.)

### 6. `01_Project/CropBatch/Services/FolderWatcher.swift` — own write path (~3 LOC)

- Line 148: forward `lossless: exportSettings.lossless` to the direct `save()`.
- (Optional) `formatFromExtension` (line 163): add a `case "webp": return .webP` so `preserveOriginalFormat` round-trips WebP sources instead of defaulting to PNG.

### 7. `01_Project/CropBatch/Services/CLIHandler.swift` — CLI selector + flag (~10 LOC)

- `--format` parser (lines 87-94): add `case "webp": format = .webp`.
- Add a `--lossless` boolean flag, set `settings.lossless = true` when present.
- Update the `--format` help text (line 154) to list `webp` and document `--lossless`.

### 8. `01_Project/CropBatch/Views/SidebarComponents/QualityResizeView.swift` — sidebar UI (~14 LOC)

Inside the `if format.supportsCompression` block (line 12), when `format == .webp`, add a Lossless toggle and flip the slider label:
```swift
if appState.exportSettings.format == .webp {
    Toggle("Lossless", isOn: $appState.exportSettings.lossless)
        .controlSize(.small)
        .help("Lossless WebP — bit-exact pixels, usually smaller than PNG. The Quality slider becomes encoding effort: higher = smaller file, slower encode.")
}
LabeledContent(appState.exportSettings.format == .webp && appState.exportSettings.lossless ? "Effort" : "Quality") { … }
```
Slider range/step/backing var unchanged. Optionally hide the `%` readout in effort mode.

### 9. `01_Project/CropBatch/Views/ExportSettingsView.swift` — alternate/legacy UI (~14 LOC)

Same Lossless toggle + "Quality"↔"Effort" label flip in `QualitySlider` (label hardcoded at line 337; range line 346) and its gating at line 28. Optionally surface "Lossless" in the `SaveExportProfileSheet` preview (lines 192-199). *(If this view is confirmed dead/legacy, note it and skip — but recon found it live.)*

### 10. `01_Project/CropBatch/Services/FileSizeEstimator.swift` — lossless branch (~10 LOC)

- Thread `lossless` into `formatConversionFactor` (line 111).
- In the `.webp` branch (lines 156-166): when `lossless`, ignore `quality` and use a PNG-class multiplier (lossless WebP ≈ 70–90% of PNG) instead of the lossy `0.25 + quality*0.75` curve.

### 11. Tests (~70 LOC)

- `CropBatchTests/ImageCropServiceTests.swift`: `WebPEncoder.encodedData` returns data with `RIFF`/`WEBP` magic bytes for lossy + lossless; `save(…, format: .webP)` writes a re-readable file; `encode(_, format: .webp)` returns non-nil (Quick Export regression).
- `CropBatchTests/ExportSettingsTests.swift`: `ExportSettingsCodable` round-trips `lossless`; decoding a legacy JSON blob *without* the key defaults to `false`.

## Implementation sequence (waves)

**Wave A — SPM wiring (user + build green).** *User* adds the package in Xcode (change #1). Then add a stub `WebPEncoder.swift` whose methods `throw ImageCropError.failedToWriteImage`. `xcodebuild -scheme CropBatch -configuration Release -destination 'platform=macOS' build` → confirm SPM resolves (SDWebImage + libwebp pins appear), builds clean under Swift 6 mode, **no Sendable warnings** from the `@preconcurrency` imports.

**Wave B — Encoder + model plumbing.** Flesh out `WebPEncoder`. Add `lossless` to `ExportSettings` + `ExportSettingsCodable`. Branch `save()` and `encode()` (change #3). Forward `lossless` from `AppState:621`, `FolderWatcher:148`, `processSingleImage:1019`. Add CLI `webp` case + `--lossless`. Build clean.

**Wave C — UI.** Lossless toggle + Quality↔Effort label flip in both `QualityResizeView` and `ExportSettingsView`. FileSizeEstimator lossless branch. Optional WebP-Lossless preset. Build clean.

**Wave D — Smoke test** (mirror SFV's, adapted for a batch tool):
1. Export a small batch as **WebP High (90%)** → files have `.webp` ext, open in Preview, smaller than PNG. `file out.webp` → `RIFF (little-endian) data, Web/P image`.
2. Export the same batch **WebP @ q=1.0** vs **q=0.5** → 1.0 visibly higher quality / larger.
3. Toggle **Lossless** (label reads "Effort"), export → bit-exact vs a PNG export (round-trip `sips -s format png` + `shasum` the RGBA).
4. Lossless **effort=1.0 vs 0.5** → effort=1.0 smaller file.
5. **Quick Export** a single image as WebP (context menu) → confirms the `encode()` path, not just `save()`.
6. **CLI** `--format webp [--lossless]` → confirms `CLIHandler` selector.
7. **Folder watcher** with WebP output → confirms the direct-`save()` path.
8. Reopen a saved `.webp` next to a PNG baseline — no color shift = sRGB conversion working.
9. Persistence: save a profile with Lossless on, relaunch, reload profile → `lossless` restored; load a pre-existing profile → no crash, `lossless = false`.

**Wave E — Commit + ship.** CropBatch is **not currently a git repo** (per env). Decide version control first (see "Open question"). Bump `MARKETING_VERSION` (1.5 → 1.6) and `CURRENT_PROJECT_VERSION` (150 → 160). Notarize per `05_Docs/22_macos-platform.md`; re-sign Sparkle appcast per `05_Docs/sparkle-signing.md`.

## Build & sign sanity

- **Universal binary:** Release builds universal (arm64 + x86_64; no `ARCHS` override). SDWebImageWebPCoder + libwebp source-build both slices automatically — longer Release build, no config. ✓
- **Hardened runtime:** `ENABLE_HARDENED_RUNTIME = YES` untouched. Pure-source deps, no dlopen/JIT → no `cs.*` entitlement. Entitlements file stays the empty dict. Sparkle already ships dynamically under this exact config. ✓
- **Notarization:** third-party SPM sources sign with the app's Developer ID (team `FDMSRXXN73`) at bundle-sign time. No notarization-rejection reports upstream. ✓
- **Contingency:** if a *dynamic-framework* library-validation error appears at runtime after integration, add `com.apple.security.cs.disable-library-validation` to `CropBatch/CropBatch.entitlements`. Treated as a fallback, not an expected step.
- **Code size:** measure the actual `.app` delta after Wave A (estimate ~2–4 MB).

## Risks & mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| Forgetting one of the 6 broken flows → WebP still fails somewhere | High | Decision #8 enumerates all of them; Wave D steps 5–7 explicitly exercise Quick Export, CLI, and folder-watcher |
| SDWebImage core's non-Sendable headers leak warnings into the build | High | `@preconcurrency import` on both modules, confined to `WebPEncoder.swift` |
| Encoded WebP looks washed-out (Display-P3 image written untagged) | Medium | Explicit sRGB `CGContext` conversion before encode; 0.15.0 embeds the sRGB ICC profile |
| `method=6` slow on large batches | Medium | One-line `webpMethod` constant; drop to 4 if a real complaint surfaces |
| Out-of-range `method` silently fails the encode | Low | Hardcoded to 6 (in range); quality clamped to 0…1 |
| Old saved profiles fail to decode after adding `lossless` | Low | `lossless: Bool?` Optional → synthesized decoder yields `nil`; Wave D step 9 verifies |
| Binary growth unacceptable | Low | Logged fallback: drop SDWebImage core, bridge `libwebp-Xcode` directly (~50 LOC) |
| macOS 26 / Tahoe regression | Low | 0.15.0 shipped post-Tahoe (Nov 2025); no 26-specific issues reported |

## Out of scope

- **Animated WebP** (single .webp containing all frames) — CropBatch's contract is one file per crop.
- **WebP + corner radius** — corner-radius currently force-converts to PNG (`ImageCropService.swift:934`). WebP *does* support alpha, so this could be relaxed later, but it's a separate decision; keep the PNG force for now.
- **WebP decode improvements** — ImageIO already reads WebP; not touched.
- **Direct `libwebp-Xcode` bridge** to drop SDWebImage core — deferred until binary size is a concrete concern.
- **`image_hint` / `method` / `alpha_*` / `sharp_yuv` UI** — defaults fine; revisit per complaint.

## Estimated total LOC

~**150 net added** across **1 new + ~9 modified** files (plus Xcode-managed pbxproj). Larger than SFV's ~95 because CropBatch has more write paths (batch + rename + save-in-place + CLI + folder-watcher + Quick Export), two parallel format UIs, a CLI selector gap, a profile-persistence wrapper, and a file-size estimator — all of which SFV lacked.

## Open question for the user (resolve before Wave E)

CropBatch is **not a git repository** right now. Before shipping: `git init` + a `feature/webp-real-support` branch (matches the global "feature branches" discipline), or proceed without VCS? Recommend initializing — this is a multi-file change worth a revertable commit.

## Decisions to promote to `05_Docs/decisions.md` post-ship

1. REAL WebP via SDWebImageWebPCoder 0.15.0 + the ~2–4 MB binary trade-off (the prior ImageIO WebP path was non-functional on macOS).
2. Quality slider reused as effort in lossless mode (label flips; value semantic stays "0–1 → libwebp 0–100").
3. `method=6` hardcoded as a tunable constant — absolute-quality choice, **not** cwebp parity (issue #116 is about lossless; both default to method=4).
4. sRGB `CGContext` conversion before encoder handoff.
5. `@preconcurrency import` for SDWebImage modules under Swift 6 mode.
6. Coder is called directly, **not** registered with `SDImageCodersManager` (encode-only usage).
