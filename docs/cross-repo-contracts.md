# Cross-repo contracts (client ⇄ daemon)

The Flutter client (`Cerebrum/src`) and the Python daemon (`Cerebrum-Daemon/src`)
share **wire contracts**: request/response shapes and identity/ordering rules
that both sides are built around. Change one side without the other and things
break *silently* (dropped answers, duplicate records, un-renderable images, notes
losing pages).

Every coupling point is annotated in-code with a greppable marker:

```
grep -rn "CROSS-REPO CONTRACT" src/lib          # here (client)
grep -rn "CROSS-REPO CONTRACT" ../Cerebrum-Daemon/src   # daemon
```

**Read the annotation next to the code before changing any sync/submit shape.**
This file is just an index; the annotations are the source of truth.

## The load-bearing contracts

| Contract | Client | Daemon | Breaks if… |
|---|---|---|---|
| Whole-page-set update (absent `page_id` = DELETE) | `api/bubbles_api.dart` `updateNote`, `services/sync_service.dart` | `api/routes_bubble.py` `update_note` | client sends a partial page set → omitted pages deleted |
| Client-owned `note_id` → server filename `<note_id>.json` | `bubbles_api.dart` `createNote`, `ui/editor/editor_scaffold.dart` | `routes_bubble.py` `create_note` | daemon stops honouring `note.note_id` → offline-created notes duplicate on sync |
| Bubble id = `md5(name)` query param; identity from auth, not body | `bubbles_api.dart` `createBubble` | `routes_bubble.py` `create_study_bubble` | `bubble_id` required-without-default → 422; `user_id` required on the *request* model → 422 |
| Empty bubble → 404 → `[]` | `bubbles_api.dart` `fetchNotes` | `routes_bubble.py` `list_notes_in_bubble` | client treats 404 as an error instead of empty |
| Images: daemon URL in, `cerebrum-image://` ref stored/pushed | `ui/editor/blocks/image/note_image_resolver.dart` | `routes_bubble.py` image routes | ref scheme or image route changes → offline render / cross-mode URLs break |
| Engram submit body field names + sync-vs-async by `job_id` | `api/learning_center_api.dart` submit\* | `routes_learning_center.py` submit models/handlers | field rename → wrong shape sent; changing which types are async → client mis-branches |
| Daemon `/engrams` route registration order | `api/learning_center_api.dart` submit\*, `fetchGradingJob` | `routes_learning_center.py` | concrete routes (`mcq|flashcard|short_question|long_question` `/submit`, `grading/jobs/{id}`, `next/{type}`, `list`) must be registered BEFORE the catch-alls `{engram_type}/{bubble_id}/{note_id}` + `{bubble_id}/{topic}` — Starlette is first-match-wins, a swallowed route 404s or returns the wrong payload |
| Short-question `question_index == question_number` | `learning_center_api.dart` `submitShortQuestion`, `models/engram_models.dart`, `.../completion/short_question.dart` | `cerebrum_core/engrams/grading/ai_grading.py` (`questions_by_index`) | client sends 0-based index → answer silently scored 0 |
| Client-owned `attempt_id` + `attempted_at`; replay dedup | `services/engram_sync_service.dart`, `services/id.dart` `nanoid()` | `routes_learning_center.py` models → `mastery_service.py` → `database/.../attempts.py` (`INSERT OR IGNORE`) | drop the id → duplicate attempts + double LLM grading on offline replay |
| Grading job poll: path + status vocabulary | `learning_center_api.dart` `fetchGradingJob` | `routes_learning_center.py` `get_grading_job_status` | rename route or a status value → grades never resolve |
| Answers stripped by default; offline needs `include_answers=true` | `learning_center_api.dart` `listEngrams`, `models/engram_models.dart`, `.../completion/*.dart` | `routes_learning_center.py` `_sanitize_for_presentation` | role-gate `include_answers` → offline compare + offline MCQ grading break |
| Mastery is daemon-authoritative; client SM-2 is provisional | `services/offline_mastery.dart` | `cerebrum_core/engrams/core/mastery_service.py` (`MasteryState`, `_update_mastery`) | state strings diverge, or client treats its schedule as authoritative |
| Engram content cache round-trips via `Engram.fromJson` | `services/engram_store.dart`, `services/db/app_database.dart` | `routes_learning_center.py` `list_engrams` payload | daemon payload drifts from `fromJson`; Drift schema change without `--force-jit` regen + migration |
| Open-reading resolve: citation → KB doc by fingerprint + best-hit page | `api/suggested_reading_api.dart` `forNote`, `ui/screens/home/quickview.dart` `_openReading` | `routes_suggested_reading.py` `suggest_for_note` → `sources/kb_source_inator.py` (page from chunk `pdf_page_start`; GET is read-through — persist only on seed-hash change or `refresh=true`) | response field rename (`suggestions[].file_fingerprint`/`in_kb`/`page`) → reader silently never opens; `page` becomes 0-indexed → opens one page off; read-through broken (every GET re-searches) → wrong-doc redirects + wasted embed calls |

## Notes

- **Drift codegen** on this SDK must use `flutter pub run build_runner build
  --force-jit` (plain build_runner fails — a native-assets build hook trips
  `dart compile`). Any schema change needs a regen + a migration bump.
- **Notes are JSON files** mirroring the daemon folder shape (a product
  requirement); **records/queues are Drift** (engram attempts, mastery, engram
  content cache). Don't move notes into Drift.
