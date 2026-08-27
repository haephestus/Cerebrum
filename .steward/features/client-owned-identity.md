# client-owned-identity

> ULIDs minted client-side so notes exist before the daemon sees them.

> Phase: core feature
> Status: done
> Created: 2026-08-21

## Status
DONE — Phase 1 (shipped pre-phase formalisation)

## Goals
- Create notes fully offline (no daemon round-trip needed)
- Client-minted note_id ensures offline-created notes don't duplicate on sync
- Attempt IDs also client-owned for idempotent replay

## Scope
- **In:** `id.dart` nanoid() (32-char hex), ULID note_id on createNote, attempt_id on engram submits
- **Out:** Client-owned page IDs (would need coordinated daemon change)

## Dependencies
- [[offline-note-persistence]] (NoteStore)
- Daemon must accept client-supplied `note_id` on create
- `INSERT OR IGNORE` for attempt dedup (daemon-side)

## Schedule
| Phase | Work |
|-------|------|
| Phase 1 | Client-owned note_id + attempt_id (DONE) |

## Notes
- `nanoid()` produces 32-char hex matching daemon's `uuid.uuid4().hex`
- Page IDs kept as `p{n}` — client-owned page IDs would need daemon change
- `createNote` is now "first push of a local note"
