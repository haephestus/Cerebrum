# Feature: Engram performance & results report

> The home screen shows how the learner is actually doing on engrams over time —
> accuracy trends, completion rate, per-type breakdowns — from real attempt
> outcomes, never fabricated statistics.

> Phase: features
> Status: planned
> Created: 2026-09-10

## Status
PLANNED — daemon work ordered first (client card is blocked on the results
endpoint). The daemon already persists every raw fact the report needs
(`engram_attempts` plus the per-type response tables in `note_engram_repository/
attempts.py`), but no route exposes it to this client. Own chain: daemon
`engram-performance-api` spec → client card below.

## Goals
- [ ] Client API method + model for the daemon performance endpoint
- [ ] Dashboard card ("Engram performance") with silent-empty-state: no attempts → shrink away, never a fabricated chart
- [ ] Offline fallback per the dashboard rule: last-known data, never a loud failure

## Current state (verified 2026-09-10)
- CLIENT: `LearningCenterApi` exposes `listEngrams` (the upcoming/scheduled
  queue), the four submit endpoints, `fetchGradingJob`, `runActiveAnalysis`,
  `getAnalysisStatus` — **no results/performance endpoint**. `EngramStore`
  caches only the `listEngrams` payload.
- DAEMON: `engram_attempts(id, engram_id, user_id, attempted_at, score, grader,
  time_spent_ms, target_cognitive_level, context_snapshot)` with indexes on
  (engram_id, user), (user_id, attempted_at), (grader); per-type response
  tables carry `is_correct`, `self_rating`, open-response scores/feedback;
  `get_recent_attempt_scores` already reads back through `engram_attempts` for
  mastery ordering. Every raw datum exists server-side; only a route is missing.

## Scope
- [ ] Client API method + model for the daemon performance endpoint (shape
      per [[cross-repo/contracts]])
- [ ] Dashboard card ("Engram performance") with silent-empty-state: no
      attempts → shrink away, never a fabricated chart
- [ ] Offline fallback per the dashboard rule: last-known data, never a loud
      failure

## Dependencies
- DAEMON: `engram-performance-api` spec (new route over `engram_attempts` +
  response tables) — tracked in `Cerebrum-Daemon/.steward/`
- `ui/screens/home/d_homescreen_page.dart` — the card slots between the gap
  carousel and the file library launcher (the TODO(agent) #1 anchor)
- `api/learning_center_api.dart` + `models/engram_models.dart` — new endpoint
  call + result model
- [[cross-repo/contracts]] — agreed wire shape
- [[features/real-notifications]] — grade-landed events are the same
  outcome stream; keep the two features loosely coupled (this card reads the
  endpoint; notifications read queue events)

## Out of scope
- Mastery graphs/charts beyond a single-number signal (homepage spec rule;
  mastery state itself stays daemon-authoritative via the SM-2 path)
- Streak/statistics/engagement mechanics

## Hard requirements
1. **No fabricated data.** Every number renders only from daemon attempt rows.
   Zero attempts → the card does not exist.
2. **Daemon-authoritative.** The report reads the endpoint; it never recomputes
   mastery from local SM-2 estimates.

## Notes / decisions
- The original TODO(agent) #1 comment (d_homescreen_page.dart) described this as
  "blocked on" a performance API. Half the blocker is already resolved by
  existing daemon storage — the missing piece is a route, not a data model.