# Tasks

> **Persistent task tracker.** Lives in `docs/`. Progress syncs to PROJECT_STATE.md.

## Backlog
<!-- Ideas and future work. Added by /interview, user input, or discovered during development. -->
<!-- Priority: top = highest, bottom = lowest -->

- [ ] Wire up test target in Xcode (File > New > Target > Unit Testing Bundle → CropBatchTests/)
- [ ] Manual test grid split end-to-end (GUI 3×3 + CLI --grid-rows 3 --grid-cols 3)
- [ ] v1.4 release prep (version bump, appcast, notarize)

## Current Sprint
<!-- Active work. Populated by /plan or /execute. Keep focused (3-7 tasks). -->
<!-- When done: /log moves to tasks-archive.md -->

- [ ] Fix 1: DRY grid URL construction (ExportSettings, ImageCropService, AppState)
- [ ] Fix 2: Simplify result index tracking in processAndExportWithRename
- [ ] Fix 3: Delete _Unused/ dead code folder

---

## Progress Calculation

```
Sprint Progress = checked in Current Sprint / total in Current Sprint
Overall Progress = (archived count + checked) / (backlog + current + archived)
```

Archived task count is read from `tasks-archive.md` header.

## Workflow Integration

| Command | Action |
|---------|--------|
| `/interview` | Adds tasks to Backlog |
| `/plan` | Moves Backlog → Current Sprint |
| `/execute` | Checks off tasks as waves complete |
| `/log` | Archives checked tasks, updates PROJECT_STATE.md progress bar |
| `/status` | Reports progress from checkbox counts |

---
*Location: `docs/TASKS.md`. Parsed by Directions app.*
