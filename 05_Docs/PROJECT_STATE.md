# Project State

> **Size limit: <100 lines.** This is a digest, not an archive.

## Identity
- **Project:** CropBatch
- **One-liner:** macOS app for batch cropping images with consistent settings
- **Started:** December 2025

## Current Position
- **Phase:** polish
- **Focus:** v1.2 released — monitoring, minor improvements
- **Status:** shipped
- **Last updated:** 2026-02-04

## Progress
```
[##############......] 70% - v1.2 released with corner radius, blur, auto-update
```

| Phase | Status | Notes |
|-------|--------|-------|
| Discovery | done | Born from iOS screenshot cropping need |
| Planning | done | Feature set defined, 61+ public downloads |
| Implementation | done | v1.2 shipped |
| Polish | **active** | "Works for me" level — no edge case obsession |

## Tech Stack
- macOS 15.0+ / Swift 6.0 / SwiftUI / Xcode 16+
- Notarized for distribution (not sandboxed)
- Processing pipeline: Blur → Transform → Crop → Corner Mask → Resize → Watermark
- Auto-update: Sparkle 2.8.1

## Active Decisions
- 2026-01-12: v1.2 released (corner radius, blur intensity, Sparkle auto-update)
- ~Dec 2025: No persistence needed — "use and close" tool
- ~Dec 2025: No Mac App Store yet (setup complexity)
- ~Dec 2025: PNG required for transparency features
- ~Dec 2025: Folder watching shelved

## Blockers
[None]

---
*Updated by Claude. Source of truth for project position.*
