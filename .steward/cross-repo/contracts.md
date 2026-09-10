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
| Engram schedule fields | engram_models.dart | list_engrams payload | `scheduled_at`/`state` renamed or dropped — client must keep the no-synthesized-time honesty rule (absent schedule → "Upcoming / no due time yet") |
| Plan progress payload | planner_api.dart / study_plan_detail_page.dart | routes_study_plan.py `GET /{plan_id}/progress` → progress_service.fetch_plan_progress | key rename/type change. Client reads: `current_week` (dict-or-null, carries `phase_id` + `week_number` + `days[]`), `current_week_task_progress.{total,completed}`, `incomplete_phases`, `unachieved_metrics[].{month_marker,checkpoint}`. Client identifies the active phase by matching `current_week.phase_id` against `incomplete_phases`, NOT by list position — phases are returned `ORDER BY phase_id ASC` but a `skipped`/`not_started` earlier phase would otherwise steal the "In Progress" label |
| Plan progress auto_resolved | study_plan_detail_page.dart | weeks.py SELECT task list | `auto_resolved` is INTEGER `0/1` (schema default 0) — client reads `(as num?) == 1`; a bool breaks at runtime |
| Plan progress task vocabulary | study_plan_detail_page.dart | schema.py plan_task_registry.task_type | task_type diverges from `study\|practice\|build\|review\|milestone_check` — client switch has a default so unknown types degrade, but the 5 known ones must stay |
| Plan progress month_marker | study_plan_detail_page.dart | plans.py register_inator (metrics insert) | `month_marker` is free-form LLM text, only parsed as `M<n>` for phase-badge attachment; any other shape must still be *rendered*, not dropped. Metrics rows can carry an explicit `phase_id` later instead of relying on the range+regex match |

## Planned contracts (gated by phase)
| Contract | Client file | Daemon file | Breaks if... |
|----------|------------|-------------|--------------|
| Engram performance/results endpoint | learning_center_api.dart (new method) | engrams performance route (new) | route or response shape renamed after the card ships — data source is `engram_attempts` + per-type response tables (daemon: [[features/engram-performance-api]]) |
| Gap-resolution flag + reading-opened marker | gap_models.dart / gap_extract.dart | note-analysis + suggested-reading state | fields dropped or moved — the unaddressed-notes surface filters on them (daemon: `note-analysis` + `suggested-reading` follow-ons) |
| Plan weeks payload | planner_api.dart (new getPhaseWeeks) | routes_study_plan.py `GET /{plan_id}/phases/{phase_id}/weeks` → fetch_weeks_for_phase_inator | weeks[] shape drifts from `fetch_plan_progress.current_week` (same week/day/task schema). NOTE: daemon read path currently defective (weeks.py `day["days"] = day`, fetch_week_inator returns all weeks, `_fetch_weeks_inner` missing conn) — fix before client consumes |
| Plan status transition | planner_api.dart (new method) | routes_study_plan.py `POST /{plan_id}/status` (NEW route) → mark_status_inator | draft → active transition dropped or renamed; 404 handling; lazy promotion in fetch_active_plans_inator must not conflict |
| Plans list payload | planner_api.dart getPlans | routes_study_plan.py `GET /user/all` → fetch_all_plans_inator | `created_at` or `total_duration_months` dropped — portfolio gantt renders bars from these two fields. Load-bearing: query returns EVERY status (verified plans.py:195-215, no status filter) — drafts feed the upcoming staging pane |
| Plan KPI payload (v2) | planner_api.dart / plan_portfolio_gantt.dart | `/user/all` rows carry `kpi` (or new `/user/kpis`) | v1 derives KPI client-side via N × getProgress calls; v2 aggregates daemon-side — renames/drops break the gantt chips |
