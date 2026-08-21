# Decisions — Cerebrum

> Managed by Steward. Record the reasons behind the shape of this project.

## ADR-0001 — Notes stay JSON files, not Drift
- **Status**: accepted
- **Date**: 2026-08-11
- **Context**: Notes need to mirror the daemon folder shape (product requirement). Drift was introduced for engram records.
- **Decision**: Notes remain as JSON files via NoteStore. Only structured records (engram attempts, mastery, content cache) move to Drift.
- **Consequences**: Notes don't get indexed queries or watch-streams. SyncService outbox stays in shared_preferences.

## ADR-0002 — Drift codegen via --force-jit
- **Status**: accepted
- **Date**: 2026-08-11
- **Context**: Dart 3.10.9 refuses dart compile when a native-assets build hook is in the graph (objective_c 9.5.0). build_runner AOT-compiles with dart compile, so it dies.
- **Decision**: Run build_runner in JIT mode: `flutter pub run build_runner build --force-jit`
- **Consequences**: All codegen must use --force-jit. Documented in docs/drift-migration.md.

## ADR-0003 — Offline-first with last-writer-wins
- **Status**: accepted
- **Date**: 2026-08-10
- **Context**: App is meant to be offline-first but was online-only. Needed a conflict model for v1.
- **Decision**: Last-writer-wins per page (matches /update's per-page_id diff). Version vectors dropped for v1.
- **Consequences**: Simpler implementation. Stronger conflict handling explicitly out of scope for v1.

## ADR-0004 — Client-minted identity (ULIDs)
- **Status**: accepted
- **Date**: 2026-08-10
- **Context**: Notes need to exist locally before the daemon sees them for offline create.
- **Decision**: Mint note_id (ULID) and attempt_id client-side. createNote becomes "first push of a local note".
- **Consequences**: Daemon must accept client-supplied note_id. Attempt dedup via INSERT OR IGNORE.

## ADR-0005 — EngramSyncService separate from SyncService
- **Status**: accepted
- **Date**: 2026-08-11
- **Context**: Engram answers are a two-phase flow (submit, then fetch grade) that note sync isn't.
- **Decision**: Separate service with its own queue, drain, and grade-poll logic.
- **Consequences**: Two sync services driven independently on app start/resume.

See [[todo]] for what's open.
