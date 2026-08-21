# Architecture — Cerebrum-Client

> System design, tech stack, and structural decisions.

## Overview

Two-process system: Flutter desktop client + Python FastAPI daemon on localhost.
Client handles UI and local persistence; daemon handles AI orchestration (RAG, LLM, embedding, grading).

**Key principles:**
- Offline-first: writes never lost, reads local-first, sync on reconnect
- Everything runs locally — no cloud, no API costs
- Client-owned identity (ULIDs minted client-side)
- Daemon-authoritative for derived state (mastery, grading)

## Tech Stack

| Layer | Technology |
|---|---|
| Frontend | Flutter 3.32+ (Dart) |
| Backend | Python, FastAPI |
| AI Orchestration | LangChain |
| Local Model Execution | Ollama |
| Vector Storage | ChromaDB |
| Structured Persistence | SQLite via Drift |
| Note Persistence | JSON files (mirror daemon shape) |
| Settings | shared_preferences |

## Components

### Client
- **EditorScaffold** — note capture screen
- **NoteStore** — local filesystem for notes + images
- **SyncService** — note sync outbox (version vectors, dirty tracking, auto-drain)
- **EngramSyncService** — engram answer queue (submit → grade poll → badge)
- **OfflineMastery** — SM-2 engine for offline flashcard/MCQ grading
- **EngramStore** — local engram content cache
- **RadialToolDial** — Concepts-inspired concentric tool wheel
- **AppDatabase** — Drift backing for engram records
- **ImageRefResolver** — handles cerebrum-image:// refs

### Daemon
- `cerebrum_inator.py` — entry point
- `ingest_inator.py` — document ingestion + chunking + embedding
- `knowledgebase_index_inator.py` — domain-specific vector store indexing
- `retrieve_inator.py` — similarity search for RAG
- `chunk_registry_inator.py` — SQLite registry preventing redundant re-embedding

## Data Flow

1. **Ingest:** Upload docs → Markdown → chunks → ChromaDB domain stores
2. **Note edit:** Write to NoteStore → mark dirty → queue sync → push on reconnect
3. **Analysis:** Send note → daemon retrieves chunks → LLM analyses → structured feedback
4. **Quiz:** Fetch engrams (or cache) → answer → queue locally → submit on reconnect → grade via job_id → badge

## Constraints
- Consumer hardware (local Ollama, no cloud)
- Drift codegen requires --force-jit
- Notes must stay JSON (daemon folder shape)
- Cross-repo wire contracts must stay in sync
