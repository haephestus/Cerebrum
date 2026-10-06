# Feature: Homepage Dashboard

> The home screen answers "where am I and what should I do now" at a glance.
>
> **Soul of this app, not a convenience:** Cerebrum exists to tell you *what you
> don't know*. The dashboard is the single place that promise is met head-on.
> Every region must answer a question with grounded, honest data — never fabricate.

> Phase: features
> Status: todo
> Created: 2026-08-27

## Status
IN PROGRESS — Phase 1 done (real identity, bubbles card, recency/resume, file
library, gap card on the existing analysis payload) and Phase 2 client done:
real schedule contract (user-level `list_engrams`, `scheduled_at` parsing, no
synthesized hours) and cross-bubble rollup (attention-ordered bubbles, severity
chips, grounded Priority lead). Remaining: daemon side of
[[engram-generation]] (generate engrams + populate `scheduled_at` + "N due"
mastery deltas).

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
      DONE via real `UserSession` identity + daemon user-level scope (the
      dashboard is the global view; `list_engrams` supports "none → all").
- [ ] **Real schedule, not synthesized hours.** Delete the `slotHour: 9 + i`
      placeholder and render the daemon's real `scheduled_at`. DONE
      (2026-09-14, revised 2026-09-15) as the **horizontal schedule rail** —
      the section is a scrollable 24h gantt window, not a full-view timeline:
      - the viewport is a fixed **6-hour window** — hour width is derived as
        viewport/6, so the 24h day is exactly 4 viewports wide and the rest
        is reached by drag OR mouse wheel (wheel is captured while the
        pointer hovers the rail — the outer page only scrolls once the mouse
        physically leaves the rail);
      - items are GANTT BARS anchored at their real due instant, spanning
        `duration` (nominal 30min review span; a daemon-side end time
        replaces it when it exists) — the anchor is real data, the tail is
        presentation so overlaps are visible;
      - bars that start in the same hour STACK vertically: `layoutGantt`
        (greedy interval partitioning) assigns overlapping bars to separate
        rows, touching bars share a row, and the rail grows with the stack —
        **capped at 3 visible rows**, above which the rail stops growing and
        a "+N more" hint strips in beneath the last row;
      - a fixed right-side **counters column** (mirror of the date column)
        shows user-global overdue (red, tap → Learning Center) and
        unscheduled counts, always visible regardless of pan position;
      - dragging past 23:59 wraps to the next day, past 00:00 to the
        previous (300ms cooldown prevents flip storms); explicit ‹ › day
        arrows sit in the date column;
      - a red now-cursor marks the current system time, only on today;
      - tapping the date opens a mini calendar with per-day overdue badges
        (custom dialog — `showDatePicker` can't decorate day cells);
      - an overdue banner jumps to the Learning Center.
      Today-only for now; the generic `ScheduleItem` model (id/title/due/
      duration/type) is the extension point for future reviews/tasks on the
      same rail. Remaining dependency: daemon must generate engrams and
      populate `scheduled_at` ([[engram-generation]]); the contract allows
      absent schedule by design.

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
      DONE via `UserSession.getUsername()` — greets the real name.
- [ ] **Offline fallback per region** — last-known local data, never a loud failure.
      Partial: GapCard + UpcomingEngramsSection keep last-known data across a
      failed background refresh. Not persisted across sessions yet.

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
- **Schedule rail design (2026-09-14 / revised 09-15 / revised 09-16):** three
  earlier client designs were rejected in sequencing — first, a grouped-day
  list with `IntrinsicHeight` inside the card caused an infinite layout loop
  ("Cannot hit test a render box that has never been laid out",
  `upcoming_engrams.dart` rewritten from scratch at HEAD); second, a rewrite
  at HEAD was reverted wholesale; third, a narrow (~58px/hr) chip rail read as
  "full view" with fixed 3-row stagger. The current rail is the fourth design
  and the second to land: wide gantt bars + `layoutGantt` interval rows
  (tested pure function), a **6-hour viewport window** (hourWidth =
  viewport/6), right-side overdue/unscheduled counters, hover-scoped wheel
  pan, dynamic height capped at 3 rows + "+N more" hint, day arrows.
  `ScheduleRail` widget tests prove filled/empty/today/other-day render with
  zero layout exceptions, same-hour bars stack vertically (and cap), counters
  render, and the timeline is a ~4-viewport scroll window with hover-scoped
  wheel capture.
  Edge-wrapped day flips live in the rail's drag handler only — calendar
  taps snap to a day without wrapping.
- **Rail overflow proofing (2026-09-15, live bug from DevTools):** the date
  column overflowed in the running app even though Ahem-font widget tests
  passed. Root cause was NOT the rail height: at display text scales ≥ ~1.25,
  a month like "SEP" is wider than the 64px date column and wraps glyph-by-
  glyph into 3 lines ("S"/"E"/"P") — one Text line at a time, each ~40px →
  the Column overflowed by dozens of px. Fixes: (1) day/month numerals are
  `FittedBox(scaleDown)` + `softWrap: false` — one line at natural width,
  scaled down, never wrapped; (2) the bottom block (day arrows + TODAY) sits
  in an `OverflowBox` so it clips instead of throwing. The rail is now
  overflow-proof at any font scale; a textScaleFactor=1.5 (and 2.0) widget
  test guards it — constant-bumping `_minBodyHeight` to chase font metrics
  is explicitly the WRONG fix (it only ever moves the threshold).
- **The daemon gap data already exists** — `editor_scaffold._formatOverviewMarkdown`
  renders `weak_areas`, `confused_links`, `knowledge_gaps_summary`, and
  `suggested_sources` today. The hero region is a *rollup + presentation* problem
  first, a *new contract* problem second. Build on what's there.
- **Suggested reading is already grounded daemon-side** (`suggested_sources`
  returns `{title, reason}`). Don't invent a new source; surface it as the gap's
  resolution.
- **Phase 2 schedule contract (2026-09-09, verified):** `Engram` parses
  `scheduled_at` (ISO-8601 UTC → local) and `state` (daemon vocabulary, display
  only). `list_engrams` is called at USER level (no hardcoded bubble/note ids).
  The dashboard groups days from real due dates; absent schedule → "Upcoming /
  no due time yet", never a fake hour. FALLBACK: `EngramStore.cacheRaw` row
  subset (Drift) drops schedule fields by design — offline listings show the
  honest unscheduled bucket until a migration adds the columns.
- **Cross-bubble rollup (Phase 2):** bubbles are attention-ordered (most severe
  gaps lead); a single grounded "Priority" lead renders only when a gap carries
  a REAL daemon severity (`high`/`medium`/`low` vocabulary); unrecognized
  severity vocabulary sorts low and never invents a rank.
- `StudyBubblesSummaryCard` display-name key unconfirmed (`name` vs `title`) —
  verify before wiring.
- Replicate `UpcomingEngramsSection`'s shrink-away empty state across all regions.
- Notes card's "Create Note" button has no onPressed — finish it, not a design choice.
- **Related planned dashboard regions (not part of this hero):**
  [[features/engram-performance-report]] (TODO(agent) #1) and
  [[features/unaddressed-notes-surface]] (TODO(agent) #2). Both are Phase 2
  siblings with their own specs; neither is blocked on this feature.
