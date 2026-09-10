# Feature: Study plan annual/portfolio view

> The Learning Center becomes a portfolio timeline: approved plans render as
> calendar-anchored bars (predicted start = plan created_at, span =
> total_duration_months), upcoming drafts sit in a staging pane left of the
> timeline with a divider, and per-bubble engrams display beneath the same
> page — the two tabs collapse into one.

> Phase: features
> Status: planned
> Created: 2026-09-10
> Revised: 2026-09-11

## Status
PLANNED — client-only. `/study_plan/user/all` already returns every plan (any
status) with created_at + total_duration_months; drafts already flow through
(verified 2026-09-11: fetch_all_plans_inator plans.py:195-215 has no status
filter). No daemon change required for v1. Wheel-pan calendar gantt reuses the
study_plan_detail_page pattern.

## Goals
- [ ] Collapse the tabs in global mode: one page — portfolio timeline on top,
      per-bubble engrams beneath (scoped note view keeps its two tabs)
- [ ] Split pane with a divider between the timeline (right) and an upcoming
      staging space (left) where draft plans are placed
- [ ] NO kanban: the staging pane is a flat draft list — no upcoming/in-progress
      columns
- [ ] Gantt shows APPROVED plans only (status != 'draft'), each bar from
      predicted start (created_at) to created_at + total_duration_months over a
      real calendar month ruler with a today marker
- [ ] Tap bar or draft card → StudyPlanDetailPage (existing navigation)
- [ ] KPI per plan exposed on the gantt (see KPI section)
- [ ] Silent empty states: no plans / no drafts / no engrams → nothing
      fabricated, no fake timeline

## KPI (planned data path)
- v1 client-derived: per approved plan call PlannerApi.getProgress (existing
  `/study_plan/{id}/progress`) → chips under the bar:
  `W{n} · done/total`, `{n} phases`, `{n} ckpts`. Degrades silently per-plan
  on failure (recorded as CROSS-REPO CONTRACT in plan_portfolio_gantt.dart).
- v2 daemon-aggregated: `kpi` embedded in /user/all rows (or new /user/kpis)
  so the portfolio renders without N round-trips. Pinned as a planned contract
  in [[cross-repo/contracts]] "Plan KPI payload".

## Current state (verified 2026-09-11)
- DAEMON: fetch_all_plans_inator returns plan_id, user_id, target_role,
  total_duration_months, status, version, superseded_by_plan_id, created_at,
  last_updated — EVERY status (drafts included), ordered by last_updated DESC.
- CLIENT: PlannerApi.getPlans + getProgress exist. DLearningCenterPage is
  tabbed (Study Plans list / Engrams), status chips + flat list.
  study_plan_detail_page.dart holds the reusable month-ruler gantt pattern
  (horizontal scroll, wheel pan, month shading, today marker).

## Open questions
- Superseded plans (superseded_by_plan_id): render as grey stub or collapse
  into the successor bar? v1 renders them as a normal (grey) bar.

## Reference
- [[features/study-plan-week-detail]]
- [[features/study-plan-draft-review]]
