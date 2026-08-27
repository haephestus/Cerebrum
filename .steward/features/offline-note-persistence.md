# offline-note-persistence

> Local-first note storage so writes never fail, even offline.

> Phase: core feature
> Status: done
> Created: 2026-08-21

## Status
DONE — Phase 1 (shipped pre-phase formalisation)

## Goals
- Notes are always saved locally before any network attempt
- User never loses an edit due to connectivity
- Sync happens in background on reconnect

## Scope
- **In:** NoteStore (filesystem persistence), SyncService outbox (dirty tracking, auto-drain), per-note version vectors (dropped in v1)
- **Out:** Conflict resolution beyond last-writer-wins (v2), cloud sync

## Dependencies
- `path_provider` for app documents directory
- `shared_preferences` for sync metadata
- Daemon `/update` endpoint (whole-page-set diff)

## Schedule
| Phase | Work |
|-------|------|
| Phase 1 | NoteStore + SyncService outbox rewire (DONE) |

## Notes
- Notes stay as JSON files mirroring daemon folder shape (ADR-0001)
- SyncService was previously dead code — rewired to use whole-page-set `/update` contract
- `drainOutbox()` runs on app start AND resume
- See [[cross-repo/contracts]] for the `/update` wire shape
