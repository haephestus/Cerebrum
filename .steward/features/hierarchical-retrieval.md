# hierarchical-retrieval

> Better retrieval for large knowledge bases by organising docs hierarchically.

> Phase: features
> Status: todo
> Created: 2026-08-21

## Status
CANDIDATE — Phase 2

## Goals
- Retrieve relevant chunks more accurately as knowledge base grows
- Organise documents by domain/topic hierarchy
- Reduce noise in RAG context injection

## Scope
- **In:** Domain-specific vector stores (already exists), hierarchical indexing, multi-level retrieval
- **Out:** Automatic topic clustering (v2), cross-domain retrieval

## Dependencies
- ChromaDB vector stores
- `knowledgebase_index_inator.py` (daemon)
- `retrieve_inator.py` (daemon)

## Schedule
| Phase | Work |
|-------|------|
| Phase 2 | Hierarchical retrieval implementation |

## Notes
- Current system already uses domain-specific stores
- This builds on that foundation with deeper hierarchy
- Helps when user has many documents across different subjects
