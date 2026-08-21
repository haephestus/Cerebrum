# hardening — Phase spec

> Definition of done: tests, failure surfaces, security pass

## Subtasks
- [ ] Unit tests for OfflineMastery SM-2 engine
- [ ] Unit tests for NoteStore
- [ ] Unit tests for EngramSyncService
- [ ] Integration tests for note sync round-trip
- [ ] Integration tests for engram quiz flow
- [ ] Drift schema migration tests
- [ ] Daemon contract compliance tests
- [ ] Security audit of daemon API
- [ ] Image cache eviction policy
- [ ] Graceful degradation when daemon unreachable
- [ ] Offline delete tombstones

## Notes
- Cross-repo contracts are highest-risk for silent breakage
- See [[research/threat-model]] for security context
