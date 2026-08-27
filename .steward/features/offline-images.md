# offline-images

> Stable image references that work offline and across base URL changes.

> Phase: core feature
> Status: done
> Created: 2026-08-21

## Status
DONE — Phase 1 (shipped pre-phase formalisation)

## Goals
- Images render offline when cached locally
- Image refs don't break when daemon base URL changes
- Upload queue for images inserted while offline

## Scope
- **In:** `cerebrum-image://<note_id>/<name>` ref scheme, NoteStore.writeImage, image resolver widget
- **Out:** Image cache eviction policy (v2), cross-device image serving

## Dependencies
- [[offline-note-persistence]] (NoteStore)
- `note_image_resolver.dart` — ref → local file if cached, else daemon URL
- Daemon image routes

## Schedule
| Phase | Work |
|-------|------|
| Phase 1 | cerebrum-image:// refs + local cache + resolver (DONE) |

## Notes
- Transforms happen at load/save boundaries (AppFlowy image component untouched)
- Fixes "absolute URL breaks when baseUrl changes" bug
- Image cache eviction needed eventually (not v1)
