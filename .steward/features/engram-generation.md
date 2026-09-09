# Feature: Engram Generation

> Generate flashcards, quizzes, and mock exams grounded in RAG context.

> Phase: features
> Status: todo
> Created: 2026-08-21

## Status
CANDIDATE — Phase 2

## Goals
- [ ] Auto-generate study materials from user's knowledge base
- [ ] All generated content grounded in retrieved source material (no hallucination)
- [ ] Support multiple engram types: flashcards, MCQs, short questions, long questions

## Scope
- **In:** LLM-powered generation pipeline, engram creation from notes + source docs, engram storage in daemon
- **Out:** Human-in-the-loop editing of generated content (v2), batch generation

## Dependencies
- Daemon generation endpoints (new)
- [[offline-note-persistence]] (notes must be accessible)
- LangChain + Ollama for generation
- [[cross-repo/contracts]] — new generation contract needed

## Schedule
| Phase | Work |
|-------|------|
| Phase 2 | Engram generation pipeline |

## Notes
- Highest-priority feature per README "What's Next"
- Needs cross-repo contract for generation request/response shape
- Generated engrams should flow through existing engram content cache
