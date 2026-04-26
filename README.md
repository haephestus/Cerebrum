# Cerebrum

> A learning assistant that actually engages with what you know — and what you don't.

**Video Demo:** https://youtu.be/d2a07zjdi3Y

---

## 1. What Is Cerebrum?

Cerebrum is a RAG-powered study tool built to make self-directed learning more honest and more effective.

Most note-taking apps store your knowledge. Cerebrum interrogates it. It analyses your notes against authoritative sources you've provided, identifies gaps in your understanding, and generates feedback grounded strictly in your own knowledge base — not in whatever an LLM decides to hallucinate.

The core idea is simple: if you can't trust what you know, you can't build on it confidently. Cerebrum is designed to give you that trust.

It does this through **Retrieval-Augmented Generation (RAG)** — a technique that forces the AI to ground its responses in retrieved source material rather than generating freely. Every analysis, every piece of feedback, every gap it identifies is anchored to documents you've deliberately chosen. That's the whole point.

---

## 2. Why I Built This

Between 2020 and 2022, I went through some deeply difficult experiences that left me with PTSD. One of the quieter effects of that was that learning became genuinely hard — not because I wasn't trying, but because my brain simply wasn't cooperating with memory formation and recall the way it used to.

I came across research showing how trauma disrupts these processes, and it reframed a lot of my frustration. The problem wasn't effort. The problem was I had no reliable way to know what I actually understood versus what I only thought I understood.

Cerebrum is my answer to that. An objective, consistent, patient system that tells you exactly where you stand — regardless of how your brain feels that day.

I built it for myself first. But I think it's useful for anyone who takes learning seriously outside of formal institutions.

---

## 3. Core Features

### Knowledge Management

User-uploaded documents are converted to Markdown, chunked, embedded into vector stores, and indexed by domain. Notes are cached as chunked Markdown to enable fast re-analysis without redundant embedding.

Notes are organised into **study bubbles** — contextual containers that group related material and anchor all downstream features: analysis, chat, and eventually engram generation.

### RAG Pipeline

The retrieval pipeline fetches relevant document chunks from domain-specific vector stores and injects them as grounding context before any LLM call is made. The model is instructed to reason strictly from retrieved material. This is the primary mechanism for reducing hallucination.

### Analysis and Feedback

Notes are analysed against embedded source material. The system generates structured feedback highlighting what's well understood and where the gaps are. Analysis outputs are versioned so you can track how your understanding evolves over time.

### Caching and Versioning

Retrieval results are cached at the domain level. Analysis outputs are versioned. This reduces redundant computation and makes the system fast enough to be practical on consumer hardware.

---

## 4. Architecture

| Layer | Technology |
|---|---|
| Frontend | Flutter (Dart) |
| Backend | Python, FastAPI |
| AI Orchestration | LangChain |
| Local Model Execution | Ollama |
| Vector Storage | ChromaDB |
| Lightweight Persistence | SQLite |

The backend runs as a local daemon — similar in spirit to Ollama itself. It exposes routes for knowledge ingestion, note analysis, retrieval, CRUD operations, and AI chat. The frontend communicates with it entirely over HTTP.

Everything runs locally. No cloud dependency. No API costs. No data leaving your machine.

---

## 5. Key Files

**Backend**

- `cerebrum_inator.py` — Main entry point. Initialises the API server and wires together all components.
- `ingest_inator.py` — Handles document ingestion, Markdown conversion, chunking, and embedding handoff.
- `knowledgebase_index_inator.py` — Manages indexing into domain-specific vector stores.
- `retrieve_inator.py` — Executes similarity search and retrieval during RAG queries.
- `markdown_converter.py` / `markdown_chunker.py` — Handle conversion, metadata, and chunk preparation.
- `chunk_registry_inator.py` — SQLite-backed registry that tracks embedded chunks to prevent redundant re-embedding.

**Frontend**

- `note_editor.dart` — Core note capture screen. Serialises rich-text input for backend analysis.

---

## 6. How to Run

**Requirements**
- Ollama (latest)
- Python 3.12
- Flutter 3.32

**Setup**

```bash
git clone https://github.com/haephestus/Cerebrum.git
python -m venv venv
source venv/bin/activate
cd backend
pip install -r requirements.txt
python3 cerebrum_inator.py
```

```bash
cd frontend/cerebrum_desktop
flutter run -d linux
```

---

## 7. Design Decisions

**Why local-only?**
Privacy and accessibility. Running on consumer hardware means no subscription, no data exposure, and no dependency on external services. The tradeoff is performance — but that's a solvable problem over time.

**Why RAG instead of pure prompting?**
Hallucination is the enemy of a learning tool. If the system fabricates feedback, it actively harms the learner. RAG grounds every output in material the user has deliberately chosen as authoritative.

**Why SQLite for registries?**
Simplicity. The chunk registry doesn't need a full database — it needs to be fast, local, and queryable. SQLite is the right tool.

**Why separate concerns so explicitly?**
Earlier versions tightly coupled responsibilities and became impossible to reason about. The current architecture is more verbose but far easier to debug and extend. I lost count of how many refactors it took to get here.

---

## 8. Current Limitations

The system is functional but incomplete. Many planned features — engram generation, hierarchical retrieval, summarisation before context injection — are not yet implemented. The knowledge base ingestion supports JSON-serialised rich text (AppFlowy format) and standard documents, but other formats require manual conversion.

This is an honest project in honest shape. It works. It will keep improving.

---

## 9. What's Next

- Engram generation (flashcards, quizzes, mock exams) grounded in retrieved context
- Hierarchical retrieval for large knowledge bases
- Improved summarisation before LLM context injection
- Broader document format support

---

## 10. Acknowledgements

To my little brother — for sitting there and letting me rubber-duck debug at him, and for helping me laugh through the confusion.

To CS50 — for providing the foundation that made this possible.

To LangChain and Ollama — for being genuinely excellent tools.

And to Claude and ChatGPT — I used both throughout this project as a kind of senior developer mentor. They helped me reason through architectural decisions, debug complex issues, and significantly improve the structure of this README. All implementation decisions and code are my own. But having access to guided technical feedback played a real role in how much I learned.
