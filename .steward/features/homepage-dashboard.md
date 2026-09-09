# Feature: Homepage Dashboard

> The home screen answers "where am I and what should I do now" at a glance.
>
> **Soul of this app, not a convenience:** Cerebrum exists to tell you *what you
> don't know*. The dashboard is the single place that promise is met head-on.
> Every region must answer a question with grounded, honest data — never fabricate.

> Phase: features
> Status: in progress
> Created: 2026-08-27

## Status
IN PROGRESS — gap/misunderstanding surface is the hero; shell present in main.

## The one line that defines this feature
> **The dashboard's hero is the "what you don't know" surface** — per study
> bubble, the concepts you're weak on, the concepts you confuse with each other,
> the reading that closes those gaps. Engrams/notes/library are supporting
> regions; they exist to feed and act on the gaps, not to be the story.

## Goals

### Hero: Understanding Gaps (per study bubble)
- [ ] **Consume the analysis payload's gap data on the home screen.** The daemon
      already returns `concept_map.weak_areas`, `concept_map.confused_links`,
      `knowledge_gaps_summary`, and `suggested_sources` in the note analysis
      (`editor_scaffold._formatOverviewMarkdown` proves it lands on the client).
      Build the GapCard region on THIS data — no new daemon work to start.
- [ ] **Group gaps by study bubble.** Roll up each bubble's notes' gap data into a
      bubble-level view: "Medical Terms: 3 weak areas, 2 confusions, 1 unread
      source." This is the flat projection the app is built around.
- [ ] **Each gap points at evidence, not a bare label.** For a weak area, show the
      notes it appears in; for a confused link, show `concept_a` vs `concept_b`
      with its `confusion_description`; for a gap, show the note + the last
      analysis version that found it. A suggestion with no source count is not done.
- [ ] **Grounded "Suggested reading" becomes the gap's resolution action.** The
      daemon's `suggested_sources` (title + reason) is already RAG-grounded — use
      it. Replace the static blue SuggestedReading box with gap-derived reading
      ranked by gap severity. If no grounded source exists, the region is empty —
      do NOT fall back to generic picks (the app's core rule).
- [ ] **Card is silent with no data.** No gaps → the whole region shrinks away (the
      empty-state pattern UpcomingEngramsSection already models — replicate it).

### Supporting region: Upcoming engrams (feeds mastery → gaps)
- [ ] **Real identity, not hardcoded IDs.** Remove the three literal
      bubble/note/user ids in `upcoming_engrams.dart` and source them from the
      real StudyBubbleContext + client identity. Gates everything else real.
- [ ] **Real schedule, not synthesized hours.** Delete the `slotHour: 9 + i`
      placeholder once the daemon returns due/schedule. Until then it stays
      explicitly marked as a wireframe artifact — never ship it as real.

### Supporting region: Study bubbles (entry to the gap surface)
- [ ] **Mount `StudyBubblesSummaryCard` into DHomescreen.** It is implemented and
      orphaned; wiring it is free and gives the gaps a home to open into.
- [ ] **Confirm the bubble display-name key** (`name` vs `title`) against the
      daemon payload before wiring (feature spec already flags this).

### Supporting region: Where You Left Off (recency)
- [ ] **Wire to NoteStore recency** (last modified note + its last analysis state).
      Needs no daemon round-trip — read local `_index.json`/note metadata.
- [ ] **Resume action** opens the note or, if it has gap data, its analysis.

### Supporting region: File Library (ingested knowledge)
- [ ] **Keep as-is.** Already real (KnowledgebaseApi.showFiles).

### Cross-cutting
- [ ] **Real identity in the app bar** ("Welcome Back User" is hardcoded).
- [ ] **Offline fallback per region** — last-known local data, never a loud failure.

## Out of scope (explicitly not dashboard)
- Mastery graphs / charts (single-number signal at most)
- Streak / statistics / social / share (engagement mechanics — off mission)
- Study-plan dashboard (a later, distinct feature)

## Hard requirements (gates, not aspirations)
1. **No fabricated data.** Every region renders only grounded values. A
   placeholder that survives past its wireframe purpose is a bug.
2. **Grounded suggestions.** Suggested/gap reading comes from RAG-identified
   gaps in the user's own material (`suggested_sources` etc.). A generic pick is
   a defect even if it fills the screen nicely.
3. **Silent empty states.** Nothing to show → shrink, never show junk.

## Dependencies
- `ui/screens/home/d_homescreen_page.dart` — screen container
- `ui/screens/home/gap_card.dart` — NEW hero region (gaps rollup)
- `ui/screens/home/upcoming_engrams.dart` — due/upcoming schedule
- `ui/screens/home/notes.dart` — Where You Left Off
- `ui/screens/home/study_bubbles_summary.dart` — orphaned; wiring
- `ui/screens/home/suggested_reading.dart` — repurpose to gap-derived reading
- `ui/editor/editor_scaffold.dart` + analysis payload (`note_overview`,
  `concept_map`, `suggested_sources`) — the gap data source (already on client)
- `api/learning_center_api.dart` + `models/engram_models.dart` — schedule fields (new)
- `api/bubbles_api.dart` — bubble summary payload
- `services/note_store.dart` — recency, no daemon needed
- [[cross-repo/contracts]] — due-date/schedule + suggested-reading shapes agreed daemon-side
- [[engram-generation]] — full schedule exists once engrams are generated (Phase 2)

## Schedule
| Phase | Work |
|-------|------|
| Phase 1 | Identity + mount StudyBubblesSummaryCard + wire recency + gap card prototype on the EXISTING analysis payload |
| Phase 2 | Real schedule/due-dates + suggested-reading/gap contract + cross-bubble rollup |

## Notes / decisions
- **The daemon gap data already exists** — `editor_scaffold._formatOverviewMarkdown`
  renders `weak_areas`, `confused_links`, `knowledge_gaps_summary`, and
  `suggested_sources` today. The hero region is a *rollup + presentation* problem
  first, a *new contract* problem second. Build on what's there.
- **Suggested reading is already grounded daemon-side** (`suggested_sources`
  returns `{title, reason}`). Don't invent a new source; surface it as the gap's
  resolution.
- Current engram call hardcodes `bubble_id`/`note_id`/`user_id` — must move to a
  real StudyBubbleContext + client identity before the engram region is real.
- `StudyBubblesSummaryCard` display-name key unconfirmed (`name` vs `title`) —
  verify before wiring.
- Replicate `UpcomingEngramsSection`'s shrink-away empty state across all regions.
- Notes card's "Create Note" button has no onPressed — finish it, not a design choice.
