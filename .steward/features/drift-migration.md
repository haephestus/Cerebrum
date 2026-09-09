# Feature: Drift Migration

> Move engram records from JSON to Drift (SQLite) for indexed queries.

> Phase: foundation
> Status: done
> Created: 2026-08-11

## Status
DONE — Phase 0 (shipped 2026-08-11)

## Goals
- [x] Engram attempts and mastery in SQLite (indexed, queryable)
- [x] Original public APIs unchanged (drop-in replacement)
- [x] Regenable codegen via --force-jit

## Scope
- **In:** EngramAttempts table, EngramMasteryRows table, CachedEngrams table, AppDatabase, --force-jit codegen fix
- **Out:** Moving notes to Drift (stays JSON per ADR-0001), moving sync outboxes

## Dependencies
- `drift` + `sqlite3_flutter_libs` packages
- `objective_c` 9.5.0 (transitive, causes build hook issue)
- `flutter pub run build_runner build --force-jit` for codegen

## Schedule
| Phase | Work |
|-------|------|
| Phase 0 | Drift setup + migration (DONE) |

## Notes
- Plain build_runner fails: Dart 3.10.9 refuses dart compile with native-assets build hook
- Fix: JIT mode (`dart run`) skips the guard
- `app_database.g.dart` is committed (tracked, not gitignored)
- Old interim JSON files NOT auto-migrated — fine for fresh installs
- Reactivity: tables ready for `watch*` streams (not yet wired)
