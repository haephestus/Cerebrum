# homepage-dashboard

> The home screen answers "where am I and what should I do now" at a glance.

> Phase: features
> Status: todo
> Created: 2026-08-27

## Status
PLANNED — Phase 2 (shell present in main; data surface stubbed)

## Goals
- Home opens to a scannable data surface that answers two questions in ~5 seconds:
  "Where am I?" (study bubbles, ingested files, where I left off, engram schedule)
  and "What should I do next?" (engrams due today/upcoming, suggested reading)
- Every region is silent when there is nothing to show: empty states instead of
  fake data, and regions shrink away rather than showing junk
- All dashboard data stays grounded in the user's own knowledge base — suggested
  reading must come from RAG-identified gaps in the user's material, never generic picks
- Offline-tolerant: regions fall back to last-known local data instead of failing loudly

## Data surface (per region)

| Region | Immediate data to display | Renders today | Gap to planned |
|--------|--------------------------|---------------|----------------|
| Upcoming engrams | Engrams due today + upcoming, grouped by real day, each with type + title | Fetches API but hardcodes bubble/note/user IDs and invents hours (`9 + i`) | Daemon must return real due/schedule; client needs real identity instead of hardcoded IDs |
| Where You Left Off (Notes) | Most recent note + its status (drafted / analysed / has gaps), resume action into note or its analysis | Static empty-state card; Create Note button is a TODO | Wire to notes recency + last analysis state |
| Study bubbles | Top N bubbles by name + source count, hand-off to bubble page / full list | Implemented (`StudyBubblesSummaryCard`) but **not wired into any screen** — orphaned | Mount on DHomescreen; confirm bubble payload key (`name` vs `title`) |
| File Library | Ingested file registry with converted/embedded status | Real (KnowledgebaseApi.showFiles) | Done — keep |
| Suggested reading | Gap-derived reading list grounded in user's own sources, ranked by gap severity | Static blue title box | Needs daemon gap/recommendation source; grounded in RAG, no hallucination |

## Scope
- **In:** DHomescreen layout + all five regions above, real identity in the app bar,
  offline fallback behaviour per region
- **Out:** Mastery graphs, streak/statistics, social/share, study plan dashboard

## Dependencies
- `ui/screens/home/d_homescreen_page.dart` — screen container
- `ui/screens/home/upcoming_engrams.dart` — due/upcoming schedule
- `ui/screens/home/notes.dart` — Where You Left Off
- `ui/screens/home/study_bubbles_summary.dart` — orphaned; needs wiring
- `ui/screens/home/file_library.dart` — finished region
- `ui/screens/home/suggested_reading.dart` — gap-grounded recommendations
- `api/learning_center_api.dart` + `models/engram_models.dart` — engram schedule fields (new)
- `api/bubbles_api.dart` — bubble summary payload
- [[cross-repo/contracts]] — due-date/schedule + suggested-reading shapes must be agreed daemon-side
- [[engram-generation]] — real schedule only exists once engrams are generated (Phase 2)
- Notes recency from local NoteStore (no daemon round-trip needed for recency)

## Schedule
| Phase | Work |
|-------|------|
| Phase 1 | Dashboard shell + File Library + engram section with placeholder scheduling (present in main) |
| Phase 2 | Real engram due/schedule + identity, wire StudyBubblesSummaryCard, Where You Left Off recency |
| Phase 2 | Suggested reading from RAG gap analysis + daemon recommendation contract |

## Notes
- Current engram call hardcodes `bubble_id`, `note_id`, `user_id` — must move to
  real StudyBubbleContext + client identity before the schedule is real
- "Welcome Back User" is hardcoded; pull display name from identity/api when available
- `Engram` model has no due-date field; `listEngrams` shape needs a schedule addition
  (cross-repo contract change — check `docs/cross-repo-contracts.md` first)
- `StudyBubblesSummaryCard` is fully implemented but unreferenced; its display-name
  key is unconfirmed (falls back name → title), verify against daemon payload before wiring
- Empty-state behaviour is already a good model here: UpcomingEngramsSection shrinks
  away when there are no engrams and keeps last data on background-refresh failure —
  replicate that pattern across the other regions
- Notes card's "Create Note" button has no onPressed — unfinished, not by design