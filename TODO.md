# Cerebrum — Immediate todos

> Working todos for today or this session. Phase structure lives in
> [[roadmap]] and syncs to the PM tracker. Keep this file for ad-hoc
> items that don't belong in a phase.

## foundation

- [x] Flutter project setup (Linux, macOS, Windows, Web)
- [x] Daemon project setup (Python, FastAPI)
- [x] Drift (SQLite) for structured data
- [x] NoteStore for local JSON persistence
- [x] SyncService outbox pattern
- [x] Client-owned identity (ULID)
- [x] Cross-repo wire contracts established
- [x] Drift Migration — Engram attempts and mastery in SQLite (indexed, queryable) [[features/drift-migration]]
- [x] Drift Migration — Original public APIs unchanged (drop-in replacement) [[features/drift-migration]]
- [x] Drift Migration — Regenable codegen via --force-jit [[features/drift-migration]]

## core feature

- [x] Note editor with rich-text capture
- [x] Note sync (local-first, daemon on reconnect)
- [x] Image handling (cerebrum-image:// refs)
- [x] Analysis mode (RAG-grounded feedback)
- [x] Engram quiz flow (fetch → answer → submit → results)
- [x] Offline-first engram answers
- [x] SM-2 offline mastery
- [x] Engram content cache
- [x] Badge + notification scaffolding
- [x] Client Owned Identity — Create notes fully offline (no daemon round-trip needed) [[features/client-owned-identity]]
- [x] Client Owned Identity — Client-minted note_id ensures offline-created notes don't duplicate on sync [[features/client-owned-identity]]
- [x] Client Owned Identity — Attempt IDs also client-owned for idempotent replay [[features/client-owned-identity]]
- [x] Engram Content Cache — Open app offline → start a fresh quiz (not just resume mid-session) [[features/engram-content-cache]]
- [x] Engram Content Cache — listEngrams is local-first: caches what it fetches, falls back on failure [[features/engram-content-cache]]
- [x] Engram Content Cache — Engram content (questions + cached answers) stored in Drift [[features/engram-content-cache]]
- [x] Local First Reads — Note list loads instantly from local _index.json [[features/local-first-reads]]
- [x] Local First Reads — Background refresh from daemon when reachable keeps local state current [[features/local-first-reads]]
- [x] Local First Reads — Works for both note list and individual note open [[features/local-first-reads]]
- [x] Offline Engram Answers — Engram answers saved on-device first (never lost) [[features/offline-engram-answers]]
- [x] Offline Engram Answers — Walked through `queued → submitted → graded` pipeline [[features/offline-engram-answers]]
- [x] Offline Engram Answers — Badge + notification when grade lands [[features/offline-engram-answers]]
- [x] Offline Engram Answers — Works for MCQ, flashcard, short, and long questions [[features/offline-engram-answers]]
- [x] Offline Images — Images render offline when cached locally [[features/offline-images]]
- [x] Offline Images — Image refs don't break when daemon base URL changes [[features/offline-images]]
- [x] Offline Images — Upload queue for images inserted while offline [[features/offline-images]]
- [x] Offline Note Persistence — Notes are always saved locally before any network attempt [[features/offline-note-persistence]]
- [x] Offline Note Persistence — User never loses an edit due to connectivity [[features/offline-note-persistence]]
- [x] Offline Note Persistence — Sync happens in background on reconnect [[features/offline-note-persistence]]
- [x] Sm2 Offline Mastery — Flashcards and MCQs give immediate offline feedback [[features/sm2-offline-mastery]]
- [x] Sm2 Offline Mastery — SM-2 engine grades answer and schedules next review locally [[features/sm2-offline-mastery]]
- [x] Sm2 Offline Mastery — State vocabulary matches daemon (new/learning/review/mastered/lapsed/suspended) [[features/sm2-offline-mastery]]
- [x] Sm2 Offline Mastery — Server mastery overwrites local estimate on sync [[features/sm2-offline-mastery]]
- [x] Tool Wheel — Evolve ToolDialHub from fixed ring to concentric wheel with colour + tool control [[features/tool-wheel]]
- [x] Tool Wheel — User can draw in any colour with clear tool/colour readout [[features/tool-wheel]]
- [x] Tool Wheel — Movable and resizable [[features/tool-wheel]]

## features

- [ ] Engram generation
- [ ] Hierarchical retrieval
- [ ] Improved summarisation before context injection
- [ ] Broader document format support
- [ ] Real local notifications
- [ ] Tool Wheel polish (opacity, custom slots, library)
- [ ] Homepage dashboard — gap-surface hero (see [[features/homepage-dashboard]])
- [ ] Engram Generation — Auto-generate study materials from user's knowledge base [[features/engram-generation]]
- [ ] Engram Generation — All generated content grounded in retrieved source material (no hallucination) [[features/engram-generation]]
- [ ] Engram Generation — Support multiple engram types: flashcards, MCQs, short questions, long questions [[features/engram-generation]]
- [ ] Hierarchical Retrieval — Retrieve relevant chunks more accurately as knowledge base grows [[features/hierarchical-retrieval]]
- [ ] Hierarchical Retrieval — Organise documents by domain/topic hierarchy [[features/hierarchical-retrieval]]
- [ ] Hierarchical Retrieval — Reduce noise in RAG context injection [[features/hierarchical-retrieval]]
- [ ] Homepage Dashboard — **Consume the analysis payload's gap data on the home screen.** The daemon [[features/homepage-dashboard]]
- [ ] Homepage Dashboard — **Group gaps by study bubble.** Roll up each bubble's notes' gap data into a [[features/homepage-dashboard]]
- [ ] Homepage Dashboard — **Each gap points at evidence, not a bare label.** For a weak area, show the [[features/homepage-dashboard]]
- [ ] Homepage Dashboard — **Grounded "Suggested reading" becomes the gap's resolution action.** The [[features/homepage-dashboard]]
- [ ] Homepage Dashboard — **Card is silent with no data.** No gaps → the whole region shrinks away (the [[features/homepage-dashboard]]
- [ ] Homepage Dashboard — **Real identity, not hardcoded IDs.** Remove the three literal [[features/homepage-dashboard]]
- [ ] Homepage Dashboard — **Real schedule, not synthesized hours.** Delete the `slotHour: 9 + i` [[features/homepage-dashboard]]
- [ ] Homepage Dashboard — **Mount `StudyBubblesSummaryCard` into DHomescreen.** It is implemented and [[features/homepage-dashboard]]
- [ ] Homepage Dashboard — **Confirm the bubble display-name key** (`name` vs `title`) against the [[features/homepage-dashboard]]
- [ ] Homepage Dashboard — **Wire to NoteStore recency** (last modified note + its last analysis state). [[features/homepage-dashboard]]
- [ ] Homepage Dashboard — **Resume action** opens the note or, if it has gap data, its analysis. [[features/homepage-dashboard]]
- [ ] Homepage Dashboard — **Keep as-is.** Already real (KnowledgebaseApi.showFiles). [[features/homepage-dashboard]]
- [ ] Homepage Dashboard — **Real identity in the app bar** ("Welcome Back User" is hardcoded). [[features/homepage-dashboard]]
- [ ] Homepage Dashboard — **Offline fallback per region** — last-known local data, never a loud failure. [[features/homepage-dashboard]]
- [ ] Real Notifications — OS-native notifications when a grade lands [[features/real-notifications]]
- [ ] Real Notifications — App-icon badge shows unseen graded count [[features/real-notifications]]
- [ ] Real Notifications — Notification tap opens the relevant engram [[features/real-notifications]]

## hardening

- [ ] Unit + integration tests
- [ ] Daemon contract compliance tests
- [ ] Security audit
- [ ] Error handling / graceful degradation
- [ ] Offline delete tombstones

## ship

- [ ] Platform builds + packaging
- [ ] Daemon installation
- [ ] Data backup/restore
- [ ] Release CI/CD
## Tasks
- Populate vault with project content
- Run graphify on repo

## Notes
- Project notes, questions, and context go here
- Link to [[decisions]] for architecture choices
- Link to [[roadmap]] for phase structure
