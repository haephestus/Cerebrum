# Libraries — Cerebrum-Client

> Suggested, evaluated, and chosen dependencies.

## Chosen

| Package | Purpose | Notes |
|---------|---------|-------|
| flutter 3.32+ | Desktop UI | Cross-platform (Linux, macOS, Windows, Web) |
| drift | SQLite ORM | Engram attempts, mastery, content cache |
| sqlite3_flutter_libs | Runtime SQLite lib | Desktop support |
| path_provider | App documents dir | Local note/image persistence |
| gpt_markdown | Markdown rendering | Analysis display |
| shared_preferences | Key-value store | Session, settings, sync outbox |
| langchain (Python) | AI orchestration | RAG pipeline, LLM calls |
| chromadb (Python) | Vector storage | Domain-specific embedding stores |
| fastapi (Python) | HTTP API | Daemon interface |
| ollama | Local LLM execution | No cloud API dependency |

## To evaluate

- Real notification plugin (replace LoggingNotificationSink)
- Stronger conflict handling (version vectors + daemon merge)
