# offline-engram-answers

> Answer quizzes offline — queue locally, submit + grade on reconnect.

> Phase: core feature
> Status: done
> Created: 2026-08-21

## Status
DONE — Phase 1 (shipped pre-phase formalisation)

## Goals
- Engram answers saved on-device first (never lost)
- Walked through `queued → submitted → graded` pipeline
- Badge + notification when grade lands
- Works for MCQ, flashcard, short, and long questions

## Scope
- **In:** EngramAttemptStore (filesystem queue + durable record), answer queuing, submit to daemon, grade poll via job_id, badge + notifications scaffolding
- **Out:** Real notification plugin (v2), daemon-side `attempt_id` dedup (follow-up)

## Dependencies
- [[client-owned-identity]] (attempt_id)
- `EngramSyncService` — submit(), drain(), grade poll, auto-drain poll (20s)
- Daemon submit endpoints + grading job endpoint

## Schedule
| Phase | Work |
|-------|------|
| Phase 1 | Queue → submit → grade pipeline + badge (DONE) |

## Notes
- Separate service from SyncService (two-phase submit+poll flow)
- MCQ/flashcard grade synchronously online → straight to `graded`
- Offline they queue and resolve on reconnect
- Idempotency via client-minted `attempt_id` (ULID) in submit body
