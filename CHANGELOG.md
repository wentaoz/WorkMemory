# Changelog

## 1.1.0 - 2026-07-10

### Added

- Aggregated work sessions that turn passive capture events into a readable daily timeline.
- Local hybrid Ask Memory search with semantic ranking, full-text matching, project filters, and clickable citations.
- Projects, pinned focus memories, richer action items, and explicit Apple Reminders export.
- Structured PDF, DOCX, XLSX, PPTX, CSV, Markdown, and text document indexing with source locators.
- AI summary progress, cancellation, run history, configurable scheduling, and model connection testing.
- First-run capture onboarding and a data health view.

### Changed

- Existing passive-capture rows are preserved as archived activities during the v2 database migration.
- Passive capture now waits for a stable context and groups updates into ten-minute sessions.
- Memory and activity lists load bounded recent data instead of loading the entire database at launch.

### Fixed

- Prevented repeated full-text index rows during memory updates.
- Recovered interrupted summary runs with a visible failed state.
- Added backward-compatible decoding for existing memories and action items.
- Preserved existing databases with a pre-migration backup.
