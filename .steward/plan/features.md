# features — Phase spec

> Definition of done: secondary capabilities added

## Subtasks
- [ ] Engram generation (flashcards, quizzes, mock exams) grounded in RAG
- [ ] Hierarchical retrieval for large knowledge bases
- [ ] Improved summarisation before LLM context injection
- [ ] Broader document format support
- [ ] Real local notifications (replace LoggingNotificationSink)
- [ ] Opacity control for highlighter
- [ ] Customisable tool/brush slots
- [ ] Brush/colour library sheet
- [ ] Homepage dashboard — gap-surface hero (see [[features/homepage-dashboard]])
- [ ] Engram performance & results report — daemon endpoint first, then dashboard card (see [[features/engram-performance-report]])
- [ ] Unaddressed-notes surface — daemon gap-resolution + reading-opened state, then filtered rollup (see [[features/unaddressed-notes-surface]])

## Notes
- Engram generation is highest priority (see README)
- Tool Wheel phases 4-5 are polish
- Homepage gap-surface hero: gap data (weak areas/confused links/gaps/suggested sources)
  already lands on the client via the existing analysis payload — the hero can be built on it
  now. Full cross-bubble rollup and the real engram schedule wait on engram generation.
  See [[features/homepage-dashboard]].
- [ ] Study plan annual/portfolio view — portfolio timeline: approved-plan gantt (predicted start) + upcoming drafts staging + engrams beneath (tabs collapsed) (see [[features/study-plan-annual-view]])
- [ ] Study plan week-level detail — daemon weeks read-path fixes first, then client phase → weeks drill (see [[features/study-plan-week-detail]])
- [ ] Study plan draft review/approval — daemon status route + client Approve (see [[features/study-plan-draft-review]])
