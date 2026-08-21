# Cerebrum-Client — Roadmap

> Phase source of truth. One numbering scheme everywhere.

## Phase 0 — foundation

> core tech exists: data model, API service, storage, auth

See [[plan/foundation]] for detailed spec.

- [x] Flutter project setup (Linux, macOS, Windows, Web)
- [x] Daemon project setup (Python, FastAPI)
- [x] Drift (SQLite) for structured data
- [x] NoteStore for local JSON persistence
- [x] SyncService outbox pattern
- [x] Client-owned identity (ULID)
- [x] Cross-repo wire contracts established

## Phase 1 — core feature

> the main capability works end to end

See [[plan/core-feature]] for detailed spec.

- [x] Note editor with rich-text capture
- [x] Note sync (local-first, daemon on reconnect)
- [x] Image handling (cerebrum-image:// refs)
- [x] Analysis mode (RAG-grounded feedback)
- [x] Engram quiz flow (fetch → answer → submit → results)
- [x] Offline-first engram answers
- [x] SM-2 offline mastery
- [x] Engram content cache
- [x] Badge + notification scaffolding
- [ ] Engram generation (flashcards, quizzes grounded in RAG)

## Phase 2 — features

> secondary capabilities added

See [[plan/features]] for detailed spec.

- [ ] Engram generation
- [ ] Hierarchical retrieval
- [ ] Improved summarisation before context injection
- [ ] Broader document format support
- [ ] Real local notifications
- [ ] Tool Wheel polish (opacity, custom slots, library)

## Phase 3 — hardening

> tests, failure surfaces, security pass

See [[plan/hardening]] for detailed spec.

- [ ] Unit + integration tests
- [ ] Daemon contract compliance tests
- [ ] Security audit
- [ ] Error handling / graceful degradation
- [ ] Offline delete tombstones

## Phase 4 — ship

> deployable and backed up

See [[plan/ship]] for detailed spec.

- [ ] Platform builds + packaging
- [ ] Daemon installation
- [ ] Data backup/restore
- [ ] Release CI/CD


## What to resist

- **Don't put environment work ahead of product.**
- **Don't let the LLM invent project structure.** Deterministic, always.
- **Don't let the LLM compute money.** Ever.
- **Don't reintroduce a second phase numbering.**
