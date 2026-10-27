# Changelog

## 1.2.0 - 2026-10-27

### Added

- Recoverable database error screen with retry and backup restore when SQLite fails to open.
- Keychain storage for model API keys, with one-time migration from plaintext UserDefaults.
- Configurable privacy rules (bundle IDs, keywords, domains, URL path segments) and capture pause for 15 minutes or 1 hour.

### Changed

- Stores share one SQLite connection opened with `FULLMUTEX` and a busy timeout.
- Ask Memory ranks on a background queue: FTS first, then a bounded candidate set, with at most 48 new embeddings per question.
- Privacy matching uses word boundaries and exact URL path segments instead of brittle substrings such as `auth` or `private`.

### Fixed

- Startup no longer wipes full-text rows for every archived activity on each launch.
- Database open failures no longer `fatalError`.
- `NLEmbedding` is loaded lazily and falls back to lexical search if the model is unavailable.

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
