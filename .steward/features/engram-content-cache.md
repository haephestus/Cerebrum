# engram-content-cache

> Local engram storage for cold-start offline quizzing.

> Phase: core feature
> Status: done
> Created: 2026-08-11

## Status
DONE — Phase 1 (shipped 2026-08-11)

## Goals
- Open app offline → start a fresh quiz (not just resume mid-session)
- listEngrams is local-first: caches what it fetches, falls back on failure
- Engram content (questions + cached answers) stored in Drift

## Scope
- **In:** CachedEngrams Drift table, EngramStore (cacheRaw + cachedResponse), listEngrams cache/fallback
- **Out:** Cache invalidation策略, cache size limits

## Dependencies
- `app_database.dart` — CachedEngrams table (schema version 2)
- `engram_store.dart` — new module
- `learning_center_api.dart` — listEngrams cache-on-success + serve-cache-on-failure
- [[drift-migration]] (Drift must be set up)

## Schedule
| Phase | Work |
|-------|------|
| Phase 1 | Engram content cache (DONE) |

## Notes
- Offline listing scoped by user + bubble/note (mirrors daemon)
- `bubble_id` per engram comes from answers-included payload
- Schema version bumped to 2 with migration
- Offline attempts still queue via EngramSyncService
