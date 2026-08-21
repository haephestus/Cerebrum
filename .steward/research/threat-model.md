# Threat Model — Cerebrum-Client

> Security considerations, attack surfaces, and mitigations.

## Assets

- User study notes and uploaded documents (privacy-sensitive)
- Engram answers and mastery data (reveals knowledge gaps)
- Local SQLite database (cerebrum.db)
- Daemon API on localhost (no auth by default)

## Trust boundaries

- User <-> Client: trusted
- Client <-> Daemon (HTTP localhost): trusted but should be validated
- Daemon <-> Ollama (local LLM): trusted
- User documents <-> LLM: RAG grounds responses in user docs only

## Threats

| Threat | Severity | Likelihood | Mitigation |
|--------|----------|------------|------------|
| LLM hallucination in feedback | High | Medium | RAG grounding — responses cite source material |
| Unauthorised daemon access | Medium | Low | Localhost only; no external binding |
| Data leakage via sync | Medium | Low | Offline-first; no cloud by design |
| Corrupted local DB | Medium | Low | Drift schema versioning + migration |
| Engram answer manipulation | Low | Low | Daemon-authoritative mastery |

## Open questions

- Should daemon require bearer token on localhost?
- How to handle device loss / backup?
- Image cache eviction policy needed
