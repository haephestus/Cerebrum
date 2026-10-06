# Feature: Study plan week-level detail

> The detail page drops from the month-ruler gantt to a phase's week-by-week
> goals. Clicking a phase expands its weeks — current AND upcoming/inactive —
> each with focus_summary, topics, days, and checkable tasks. Replaces the
> active-week-only checklist with a full phase timeline.

> Phase: features
> Status: todo
> Created: 2026-09-10
> Revised: 2026-09-23

## Status
SHIPPED (2026-09-23) — daemon read-path fixes and the full client drill are
in.

Daemon verified: `_fetch_week_with_days` nests `week.days[].tasks[]`
(weeks.py), `fetch_week_inator` returns a single week, the phase-weeks route
returns every densified week in `week_number` order. The client route is
`GET /study_plan/{plan_id}/weeks/phase/{phase_id}` (routes_study_plan.py:246),
which matches PlannerApi.getPhaseWeeks; the port sheet in
[[cross-repo/contracts]] previously named `/phases/{phase_id}/weeks` — that
path never existed; corrected there.

Client shipped: tapping a phase on the month gantt opens the floating detail
sheet whose weeks expand to days with checkable tasks (active week lands
expanded, so "this week" stays the default view). Day/task rendering was
extracted to the shared `StudyPlanDayCard` widget and the old active-week
checklist dead code was deleted.

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
      (extracted as StudyPlanDayCard; onCompleteTask/onReopenTask callbacks on
      the gantt refetch the phase's weeks after each checkbox flip)
- [ ] CLIENT: undensified phase → keep "Generate this week" as the empty-state
      action ("Generate more week detail" once a phase has weeks)
- [ ] Contract: no shape drift between fetch_plan_progress.current_week and
      the weeks route (same week/day/task schema)

## Contract note: topics key
The daemon's read path pops `topics_json` into `topics` (weeks.py
`_fetch_week_with_days`), for BOTH `current_week` and the weeks route. Until
2026-09-23 the client read `topics_json`, so every week's topic tags rendered
empty without any error. Client now reads `topics` (with a `topics_json`
fallback for pre-contract payloads). If a daemon change ever stops popping
`topics_json`, this breaks silently again — keep the pop.

## Reference
- [[features/study-plan-annual-view]]
- [[features/study-plan-draft-review]]