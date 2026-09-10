# Feature: Bubble notes view

> Phase: features
> Status: planned

## Goals
- [ ] Notes displayed as cards (not bare ListTiles) with title, snippet, analysis status, gap count, last edited
- [ ] Sort by attention: needs-analysis first, then by gap count, then by recency
- [ ] Context sidebar (right pane) showing selected note's analysis summary and quick actions
- [ ] Promote "Add New Note" from list item to a FAB or header button
- [ ] Offline-first sync indicator in the header

## Current state (verified 2026-09-10)
DStudyBubblePage uses a desktop split-pane Row with ListView.builder of ListTiles on the left (flex: 2) and a static name+description panel on the right (width: 400). ListTiles show only title (editable) + filename + delete. No analysis status, no snippet, no gap data. The right pane is wasted on static info that could be a header. "Add New Note" is index-0 in the list, making it look like a note.

## Scope
- Bubble notes list (DStudyBubblePage left pane) card redesign
- Context sidebar (right pane) with analysis summary and quick actions
- Sort logic: attention-first ordering
- Offline-first sync indicator

## Dependencies
- BubbleNotesApi.fetchNotes
- NoteStore.listNotes
- EditorScaffold (note detail)
- Analysis data from daemon

## Hard requirements
1. Cards must show real analysis status from the daemon, not fabricated states
2. Context sidebar must update on selection, not be static
3. Offline-first rendering must remain (NoteStore.listNotes first, background sync)
