# foundation — Phase spec

> Definition of done: core tech exists: data model, API service, storage, auth

## Subtasks
- [x] Flutter project setup with desktop targets
- [x] Daemon project setup (Python, FastAPI)
- [x] Local SQLite via Drift for structured data
- [x] NoteStore for local JSON file persistence
- [x] SyncService outbox pattern for note sync
- [x] Client-owned identity (ULID note_id, attempt_id)
- [x] Cross-repo wire contracts established
- [ ] Auth layer (if needed for multi-user local)

## Notes
- Drift codegen requires --force-jit (objective_c build hook issue)
- Notes stay JSON files, not Drift
- See [[research/architecture]] and [[cross-repo/contracts]]
