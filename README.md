
# Cerebrum

#### Video Demo: https://youtu.be/d2a07zjdi3Y
---

## 1. Project Overview

### 1.1 What Is Cerebrum?

Cerebrum is a learning assistant designed to leverage artificial intelligence through the use of **Retrieval Augmented Generation (RAG)** by interfacing with **Ollama**. The goal of the project is to drive a user’s self-learning journey by directly interacting with **user-generated content**, primarily through notes.

Rather than acting as a passive note-taking tool, Cerebrum actively engages with the user’s knowledge base. It analyses notes, tests understanding by generating *engrams* (flashcards, quizzes, and mock exams), and provides feedback on learning progress. All reasoning is grounded in data embedded within vector stores, which act as the system’s source of truth.

Files used by the AI are provided entirely at the user’s discretion, allowing Cerebrum to support learning across a wide range of subjects. Compared to traditional note-taking applications such as Obsidian, Cerebrum does not merely store information — it **interacts** with the user’s knowledge base to drive learning forward.

Cerebrum is aimed at “students of life”: people who want to learn beyond the confines of formal institutions and want a system that grows with them.

---

### 1.2 Motivation and Inspirations

My motivation for building Cerebrum comes from personal difficulty during my university studies. Between 2020 and 2022, I went through some deeply troubling experiences that resulted in PTSD, which significantly affected my ability to learn consistently.

Earlier this year, I came across research detailing how PTSD and similar conditions can disrupt memory formation, recall, and learning confidence. This sparked the idea for an application that could act as a **single source of truth** for learning progress.

The core idea is that no matter the learner’s mental state, an accurate and objective evaluation of what they know — and what they do not — can restore confidence. Cerebrum is meant to provide clarity: confidence in what you understand, and the wisdom to clearly see the gaps that still exist.

---

## 2. Core Features

### 2.1 Knowledge Management

At the time of this implementation, user notes are stored as **JSON files** due to the use of **AppFlowy’s rich text editor** on the frontend.

User-uploaded documents that make up the knowledge base are converted into **Markdown**, then chunked before being embedded into vector stores. These embedded documents form the factual backbone used during analysis and retrieval.

User notes are cached as chunked Markdown to allow for fast re-analysis. Retrieved results from vector stores are cached at the **domain level** (for example: biology, chemistry, or other domains inferred from user input).

Notes are organized into **study bubbles**, which act as contextual containers for related notes. Each bubble is designed to support downstream features such as chatting with the AI about notes, analysis results, and eventually generated engrams.

---

### 2.2 Retrieval-Augmented Generation (RAG)

RAG is the primary method used for retrieval from the knowledge base. This technique was chosen specifically to reduce LLM hallucinations.

When a note is analysed, relevant document excerpts are fetched from the vector store and fed into the LLM as contextual grounding. The model is instructed to base its analysis strictly on this retrieved context, significantly reducing the likelihood of fabricated or misleading outputs.

---

### 2.3 Learning and Analysis Capabilities

In the context of Cerebrum, “learning” means **iterative understanding**. Notes are analysed against authoritative sources from the knowledge base, feedback is generated, and gaps in understanding are highlighted.

Analysis results are cached and versioned so the system can track how a learner’s understanding evolves over time. Users interact with these features through the note editor and analysis views, receiving structured feedback rather than raw AI output.

---

## 3. System Architecture

### 3.1 High-Level Architecture

At a high level:

- The **frontend** is written in Dart using the Flutter framework.
- The **backend** is written in Python and uses LangChain for orchestration.
- **AI components** are managed by Ollama, running local models.

The frontend communicates with the backend via HTTP APIs. The backend, in turn, coordinates document ingestion, retrieval, and analysis through the AI layer.

---

### 3.2 Frontend (Flutter)

Flutter was chosen so the application can eventually be used on desktop, tablet, and mobile devices without rewriting the UI.

The UI is responsible for capturing user input, managing notes, and presenting analysis results in a way that keeps the learner engaged without overwhelming them.

The most important screen is `note_editor.dart`, which captures the user’s thoughts and prepares them for downstream analysis.

---

### 3.3 Backend (Python / FastAPI)

Python was chosen due to its strong ecosystem for AI tooling and ease of integrating local models. Performance improvements can later be introduced via CPython extensions if needed.

The backend behaves like a **local daemon**, similar to Ollama itself. It exposes routes for managing the knowledge base, analysing notes, performing CRUD operations, and chatting with the AI. Future implementations will include engram generation.

---

### 3.4 AI / Embedding Layer

The project depends heavily on Ollama for local model execution and LangChain as a wrapper for interacting with those models.

LangChain simplifies embedding generation, retrieval, and prompt orchestration, allowing focus on system design rather than low-level model management.

---

## 4. Project Structure

### 4.1 Repository Layout

The repository is split into two primary components:

- `backend/`  
  Contains the API server, ingestion pipeline, RAG logic, vector store management, and registries.

- `frontend/`  
  Contains the Flutter application responsible for all user interaction.

Supporting directories handle lightweight persistence, cached data, and registries, primarily using SQLite.

---

### 4.2 Key Files Explained

#### `cerebrum_inator.py`
The main backend entry point. It initializes the API server and wires together ingestion, retrieval, and analysis components.

#### `ingest_inator.py`
Handles document ingestion, Markdown conversion, chunking, and passing data to the embedding layer.

#### `knowledgebase_index_inator.py`
Manages indexing and registration of embedded documents into domain-specific vector stores.

#### `retrieve_inator.py`
Handles similarity search and retrieval during RAG queries.

#### `markdown_converter.py` & `markdown_chunker.py`
Which handle markdown conversion, metadata handling, and chunk preparation.

#### `chunk_registry_inator.py`
Tracks embedded chunks using SQLite to prevent unnecessary re-embedding and enable future versioning.

#### `note_editor.dart`
Core frontend file responsible for capturing user notes and serializing them for backend analysis.

---

## 5. Data Flow and APIs

### 5.1 API Design

The API is designed around **learning intent**, not pure CRUD semantics.

Routes exist for:
- Knowledge ingestion
- Note analysis
- Retrieval and chat
- Note management

Query parameters such as `bubble_id`, `note_id`, and `version` are used to preserve learning context and support caching.

---

### 5.2 Caching and Versioning

Caching is used extensively to reduce unnecessary computation:

- Notes are cached as chunked Markdown.
- Retrieval results are cached per domain.
- Analysis outputs are versioned.

The tradeoff is added complexity in cache invalidation, but this was accepted to ensure responsiveness and scalability.

---

## 6. Design Decisions and Tradeoffs

### 6.1 Architectural Decisions

Earlier designs tightly coupled multiple responsibilities within single classes. This became difficult to reason about and debug. The current architecture separates concerns explicitly to improve clarity and maintainability.

---

### 6.2 Technology Choices

Python, Flutter, SQLite, vector stores, and local models were chosen to balance flexibility, accessibility, and performance. These choices introduce limitations, but they allow the project to remain local-first and privacy-respecting.

---

### 6.3 Performance vs Simplicity

Optimization was avoided where it introduced unnecessary complexity. The priority was correctness and clarity over premature performance tuning.

---

## 7. Challenges and Solutions

### 7.1 Technical Challenges

Major challenges included managing large documents, designing effective chunking strategies, and preventing LLM context overload.

---

### 7.2 Debugging and Problem-Solving

Issues were diagnosed using logging, REPL experimentation, and iterative refactoring.

---

### 7.3 What I Would Do Differently

With more time, I would refine hierarchical retrieval, improve summarization before context injection, and simplify early design decisions further.

---

## 8. Limitations

The largest limitation is my own lack of experience. The system is functional but incomplete, and many ideas remain unimplemented.

---

## 9. Future Work

Cerebrum will continue to evolve until it is feature-complete and optimized to run on common consumer hardware so that it is accessible to as many students as possible — or until it dies trying.

---

## 10. How to Run the Project

### 10.1 Requirements

- Latest version of Ollama  
- Python 3.12  
- Dependencies listed in `requirements.txt`  
- Flutter 3.32  

### 10.2 Setup Instructions

```bash
git clone <repo>
python -m venv venv
source venv/bin/activate
cd backend
pip install -r requirements.txt
python3 cerebrum_inator.py
cd frontend/cerebrum_desktop
flutter run -d linux
```

## 11. Acknowledgements

A big thank you to my little brother for sitting there and letting me use him as my rubber-duck debugger and helping me laugh through the confusion.

Libraries used include LangChain and Ollama.
CS50 provided the foundation that allowed me to take a real step toward becoming a machine learning engineer.

LangChain’s own AI tooling was also used to understand the framework and explore implementation strategies.

I also want to explicitly acknowledge ChatGPT and Claude, I used both throughout this project in the role of a senior developer mentor. Which helped me reason through architectural decisions, debug complex issues, refine the RAG pipeline, and significantly improve the structure and clarity of this README. While all implementation decisions and code are my own, having access to guided technical feedback played a major role in my development.

## 12. Final Thoughts

This project is incomplete, but I will continue to iterate and improve it.

In its current state, I learned a great deal about how applications interact behind the UI. This project is evidence of my ability to learn, adapt, and improve.

I experienced firsthand why the KISS principle matters — keep your code simple and stupid. I lost count of how many times I had to refactor code that was complex for no good reason.

I am proud that my first real piece of software is designed to address a problem I saw many students struggle with silently: the feeling of helplessness when effort does not translate into results because your brain simply refuses to cooperate.

