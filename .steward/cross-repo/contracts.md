# Cross-repo contracts — Cerebrum-Client

> Wire shapes. In-code `CROSS-REPO CONTRACT` markers are source of truth.
> Full details: docs/cross-repo-contracts.md

## Load-bearing contracts
| Contract | Client file | Daemon file | Breaks if... |
|----------|------------|-------------|--------------|
| Whole-page-set update | bubbles_api.dart | routes_bubble.py | Partial page set sent |
| Client-owned note_id | bubbles_api.dart | routes_bubble.py | Daemon stops honouring note_id |
| Bubble id = md5(name) | bubbles_api.dart | routes_bubble.py | bubble_id missing |
| Image ref scheme | note_image_resolver.dart | image routes | Scheme changes |
| Engram submit fields | learning_center_api.py | routes_learning_center.py | Field rename |
| Question index alignment | learning_center_api.py | ai_grading.py | 0-based vs 1-based |
| Client attempt_id + dedup | engram_sync_service.dart | attempts.py | Drop id |
| Grading job poll | learning_center_api.py | get_grading_job_status | Rename route |
| Answers stripped by default | learning_center_api.py | _sanitize_for_presentation | Role-gate include_answers |
| Mastery daemon-authoritative | offline_mastery.dart | mastery_service.py | State vocabulary diverges |
| Engram content cache round-trip | engram_store.dart | list_engrams payload | Drift schema change |
