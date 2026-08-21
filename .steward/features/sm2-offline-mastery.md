# sm2-offline-mastery

> Anki-style spaced repetition that works with no server.

## Status
DONE — Phase 1 (shipped pre-phase formalisation)

## Goals
- Flashcards and MCQs give immediate offline feedback
- SM-2 engine grades answer and schedules next review locally
- State vocabulary matches daemon (new/learning/review/mastered/lapsed/suspended)
- Server mastery overwrites local estimate on sync

## Scope
- **In:** OfflineMastery (SM-2 engine), MasteryRecord (ease/interval/reps/dueAt/state), applyFlashcard/applyMcq, adoptServerState
- **Out:** Daemon's own (non-SM-2) scheduler with cognitive-level promotion

## Dependencies
- [[offline-engram-answers]] (attempt submission)
- `engram_models.dart` McqContent.correctOption (for offline MCQ grading)
- Daemon mastery_service.py (authoritative state)

## Schedule
| Phase | Work |
|-------|------|
| Phase 1 | SM-2 engine + adoption of server state (DONE) |

## Notes
- Local SM-2 is **provisional** — daemon is mastery-authoritative
- `adoptServerState` overwrites local estimate whenever submit returns `mastery_state`
- Flashcard "next review" labelled as offline estimate
- State vocabulary: new/learning/review/mastered/lapsed/suspended
