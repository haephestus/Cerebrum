# Feature: Unaddressed-notes surface

> Bring the notes the person has NOT addressed to the forefront: gaps still
> open AND suggested reading still untouched — the "what you don't know and
> haven't touched" view.

> Phase: features
> Status: planned
> Created: 2026-09-10

## Status
PLANNED — needs two persisted state pieces (gap resolution + reading-opened)
before the client can distinguish "addressed" from "unaddressed". Both pieces
are daemon-work; the client display is then a filtered projection over gap
summaries.

## Goals
- [ ] DAEMON: persist gap resolution — `SET resolved/dismissed` lifecycle per gap signature (daemon spec: `note-analysis` follow-on)
- [ ] DAEMON: `opened_at`/last-accessed marker on suggested readings (daemon spec: `suggested-reading` follow-on)
- [ ] CLIENT: filtered rollup over `GapRepository` summaries — items where `resolved == false` AND `reading.openedAt == null`
- [ ] CLIENT: mark-a-gap-resolved action at the dashboard (see → address → resolved → disappears)

## Current state (verified 2026-09-10)
- CLIENT: `GapItem` (`gap_models.dart`) carries kind/title/detail/severity/
  evidence but **no resolved/dismissed flag**; `GapEvidence` carries block ids +
  page id but **no reading-opened marker**. Every gap the daemon returns is
  implicitly "still open."
- DAEMON: gap data derives from the analysis payload (no persisted
  gap-resolution state). `suggested_readings` tracks candidate/accepted/
  dismissed status and has `file_fingerprint`, but **no `opened_at` /
  last-accessed marker** — nothing records whether a suggested source was ever
  opened. (Accept→ingest→in_kb is a proxy for "engaged", not "opened".)
- The daemon's analysis cache keys on note version; a gap signature resolves to
  (gap kind + block/concept refs). A durable flag therefore needs its own table
  keyed by (user_id, note_id, gap_signature[, analysis_version]) so it survives
  re-analysis. Alternative for reading: add `opened_at` to `suggested_readings`.

## Scope
- [ ] DAEMON: persist gap resolution — `SET resolved/dismissed` lifecycle per
      gap signature (daemon spec: `note-analysis` follow-on)
- [ ] DAEMON: `opened_at`/last-accessed marker on suggested readings (daemon
      spec: `suggested-reading` follow-on)
- [ ] CLIENT: filtered rollup over `GapRepository` summaries — items where
      `resolved == false` AND `reading.openedAt == null`
- [ ] CLIENT: mark-a-gap-resolved action at the dashboard (the loop the
      surface closes: see → address → resolved → disappears)

## Dependencies
- DAEMON: `note-analysis` + `suggested-reading` follow-on state (tracked in
  `Cerebrum-Daemon/.steward/`)
- `ui/screens/home/d_homescreen_page.dart` — region anchor (TODO(agent) #2)
- `ui/screens/home/gap_models.dart` + `gap_extract.dart` — thread the two new
  fields through the models (no new architecture, per the original note)
- [[cross-repo/contracts]] — agreed wire shapes for gap-status + reading-opened
- [[features/homepage-dashboard]] — the parent hero region this surfaces under

## Out of scope
- Re-opening/rescheduling gaps (a later, distinct flow)
- Any generic "recently touched" read surface (navigation territory)

## Hard requirements
1. **No re-display of the same gap data** — an "unaddressed" view that shows
   everything is a defect; it must add the addressed/unaddressed distinction.
2. **Flags are durable** across re-analysis (version-keyed), not cosmetic
   session state.

## Notes / decisions
- Original TODO(agent) #2 (d_homescreen_page.dart) called both state pieces
  "missing" — still true, but now each has a named owning feature daemon-side.
- Client-only local flags were considered and rejected for the durable answer:
  analysis re-runs recreate the "open" set, and local flags would not survive
  a re-open on another device.