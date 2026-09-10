# Feature: Study plan week-level detail

> The detail page drops from the month-ruler gantt to a phase's week-by-week
> goals. Clicking a phase expands its weeks — current AND upcoming/inactive —
> each with focus_summary, topics, days, and checkable tasks. Replaces the
> active-week-only checklist with a full phase timeline.

> Phase: features
> Status: planned
> Created: 2026-09-10
> Revised: 2026-09-11

## Status
PLANNED — mostly client work, with a daemon corrective pass first. The daemon
already persists inactive weeks (densify_phase inserts the whole weeks array
and marks only week_ids[0] active — progress_service.py:84) and already exposes
`GET /study_plan/{plan_id}/phases/{phase_id}/weeks` (routes_study_plan.py:92).
The weeks read path has defects that must be fixed before the client consumes it.

## Goals
- [ ] DAEMON: fix weeks read path — weeks.py `day["days"] = day`
      self-reference, fetch_week_inator returning all weeks instead of one,
      `_fetch_weeks_inner` with no conn binding
- [ ] DAEMON: pin weeks payload shape in [[cross-repo/contracts]] (week fields +
      days[] + tasks[] types)
- [ ] CLIENT: PlannerApi.getPhaseWeeks(planId, phaseId) method
- [ ] CLIENT: phase card affordance on the detail gantt → week timeline for
      that phase
- [ ] CLIENT: week cards (week_number, focus_summary, topics) expand to days
      with checkable tasks; reuse _buildDayCard / _completeTask flows
- [ ] CLIENT: undensified phase → keep "Generate this week" as the empty-state
      action
- [ ] Contract: no shape drift between fetch_plan_progress.current_week and
      the weeks route (same week/day/task schema)

## Current state (verified 2026-09-11)
- DAEMON: route exists — routes_study_plan.py `GET /{plan_id}/phases/{phase_id}/weeks`.
- fetch_weeks_for_phase_inator returns ALL weeks (pending/active/complete) in
  week_number order with days[] and tasks[] nested (weeks.py:96-109).
- Progress payload carries only the active week — all other weeks come
  exclusively through the weeks route.
- CLIENT: study_plan_detail_page.dart renders the active-week checklist only;
  no weeks fetch exists in PlannerApi.

## Reference
- [[features/study-plan-annual-view]]
- [[features/study-plan-draft-review]]
