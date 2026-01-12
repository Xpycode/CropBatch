# Project State

## Quick Facts
- **Project:** CropBatch
- **Started:** ~December 2025
- **Current Phase:** implementation
- **Last Session:** 2026-01-12
- **Version:** 1.1
- **Downloads:** 61 (GitHub releases)

## What Is This?
A macOS app for batch cropping images. Born from needing to crop iOS screenshots for pdf2calendar.eu documentation — apply the same top/bottom crop to 20-30 images at once.

**Core use:** Batch crop screenshots with consistent settings.

## Who Uses It
- **Primary user:** You (scratching your own itch)
- **Secondary:** 61 public downloaders
- **Polish level:** "Works for me" — not obsessing over edge cases

## Feature Origin
| Feature | Origin |
|---------|--------|
| Crop handles, batch apply | Core need |
| Watermarks | User requested |
| Snap-to-edge | User requested |
| Blur (sensitive info) | Your wishlist |
| Corner radius | Your wishlist |

## Current Focus
Merge two feature branches, then continue development.

## Branches in Flight
| Branch | Status | Description |
|--------|--------|-------------|
| `corner-radius` | Ready to merge | Transparent corner cropping |
| `blur-again` | Ready to merge | Blur with working intensity slider |

## Technical Notes
- **Platform:** macOS 15.0+ / Swift 6.0 / Xcode 16+
- **Distribution:** Notarized, GitHub releases (not MAS yet)
- **Sandbox:** Not sandboxed (empty entitlements)
- **Persistence:** Not needed — "use and close" tool

## On Hold
- Folder watching (shelved)
- Mac App Store (setup complexity)

## Next Actions
1. [ ] Merge `corner-radius` to main
2. [ ] Merge `blur-again` to main
3. [ ] Verify both features work together
4. [ ] Continue development

---
*Updated: 2026-01-12*
