# local-first-reads

> Read from local store first, refresh from daemon in background.

> Phase: core feature
> Status: done
> Created: 2026-08-21

## Status
DONE — Phase 1 (shipped pre-phase formalisation)

## Goals
- Note list loads instantly from local _index.json
- Background refresh from daemon when reachable keeps local state current
- Works for both note list and individual note open

## Scope
- **In:** `_index.json` local-first reads, background `fetchNoteByFileName` refresh
- **Out:** Real-time push sync, conflict UI

## Dependencies
- [[offline-note-persistence]] (NoteStore must exist)
- `d_study_bubble_page.loadNotes` (reads local first)
- `EditorScaffold._openNote` (local first, background refresh)

## Schedule
| Phase | Work |
|-------|------|
| Phase 1 | Local-first reads + background refresh (DONE) |

## Notes
- Keeps local-only/unsynced notes visible
- Background refresh is best-effort — doesn't block UI
