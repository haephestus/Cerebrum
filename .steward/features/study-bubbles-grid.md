# Feature: Study bubbles grid

> Phase: features
> Status: done

## Goals
- [x] Responsive grid layout (LayoutBuilder, 180-240px card minimum, not hardcoded 6 columns)
- [x] Attention-sensing cards with ring accent colors from gap severity data (port from StudyBubblesSummaryCard._ringColor logic)
- [x] Surface note count, domains, and last-studied timestamp on each card
- [x] "Resume last bubble" hero row at top showing the most recently opened bubble with a Resume action
- [x] Search/filter field above grid to filter bubbles by name or domains

## Current state (shipped 2026-09-10)
DStudyBubbleHome now: LayoutBuilder grid (200px minimum card, 2-6 columns clamped
to bubble count); CardView carries an attention rail (neutral #B9B4CC / amber
#C9A24B / red #B3261E from GapRepository.cached()) plus note count and
last-updated chips from NoteStore.listNotes and domain tags from the bubble
payload; a "Continue where you left off" row renders the last bubble opened
(UserSession.getLastOpenedBubble, hidden when the bubble no longer exists); a
search field filters by name/domains. RefreshIndicator + empty/error/no-match
states included. Analyzer clean; test suite unchanged (3 pre-existing
gap_card_test failures only).

## Scope
- Bubbles list page (DStudyBubbleHome) grid view
- Card widget with attention ring, note count, domains, last-studied
- Hero resume row persisted via local storage or NoteStore
- Search/filter bar above grid

## Dependencies
- BubblesApi.fetchBubbles
- StudyBubblesSummaryCard (ring color logic)
- desktop_main.dart navigation shell

## Hard requirements
1. Grid must be responsive to window resize (desktop app, not fixed)
2. Cards with open gaps MUST show attention accent — this is a learning app, not a file manager
3. Resume row must track last-opened bubble (persist in local storage or NoteStore)
