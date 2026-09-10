# Feature: Study plan draft review / approval

> Draft plans are visible in the Learning Center's upcoming staging pane but
> there is no official approve/activate path. Add a daemon route to transition
> plan status (draft → active) and an Approve action on draft cards.

> Phase: features
> Status: planned
> Created: 2026-09-10
> Revised: 2026-09-11

## Status
PLANNED — small daemon route + small client action. Drafts DO flow through
`GET /study_plan/user/all` (fetch_all_plans_inator returns every status —
verified 2026-09-11); what is missing is the status transition. The daemon has
`mark_status_inator(plan_id, status)` (plans.py:137) behind no route, and
fetch_active_plans_inator lazily promotes drafts on read, but the client calls
`/user/all` which never promotes.

## Goals
- [ ] DAEMON: `POST /study_plan/{plan_id}/status` (body `{"status": "active"}`),
      404 on missing plan, validates draft/active/completed/archived
- [ ] CLIENT: Approve action on draft cards in the upcoming pane → route →
      refresh (draft leaves staging; bar appears on the timeline)
- [ ] Contract row in [[cross-repo/contracts]] (Plan status transition)
- [ ] Decide interaction with lazy promotion in fetch_active_plans_inator
      (explicit approval supersedes just-in-time promotion)

## Current state (verified 2026-09-11)
- DAEMON: mark_status_inator exists on PlansMixin (plans.py:137) but no route.
- DAEMON: fetch_active_plans_inator promotes draft → active on read (plans.py).
- CLIENT: PlannerApi has no status-change method; upcoming pane shows no
  approve affordance yet.

## Reference
- [[features/study-plan-annual-view]]
- [[features/study-plan-week-detail]]
