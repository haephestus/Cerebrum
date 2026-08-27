# core feature — Phase spec

> Definition of done: the main capability works end to end

## Subtasks
- [x] Note editor with rich-text capture
- [x] Note sync (local-first, daemon on reconnect)
- [x] Image handling (cerebrum-image:// refs, local cache)
- [x] Analysis mode (RAG-grounded feedback)
- [x] Engram quiz flow (fetch → answer → submit → results)
- [x] Offline-first engram answers
- [x] SM-2 offline mastery for flashcards/MCQs
- [x] Engram content cache for cold-start offline
- [x] Badge + notification scaffolding

## Notes
- EngramSyncService separate from SyncService (two-phase submit+poll)
- Mastery is daemon-authoritative; client SM-2 is provisional
- See [[cross-repo/contracts]] for submit/grading wire shapes
