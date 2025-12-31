import hashlib
import json
import logging
from datetime import datetime
from pathlib import Path
from typing import Optional

import yaml
from langchain_chroma import Chroma
from langchain_core.documents import Document
from langchain_ollama import OllamaEmbeddings
from langchain_ollama.llms import OllamaLLM
from langchain_text_splitters.markdown import MarkdownHeaderTextSplitter

from agents.rose import RosePrompts
from cerebrum_core.model_inator import (
    ArchivedNote,
    ArchivedNoteContent,
    NoteContent,
    NoteStorage,
    TranslatedQuery,
)
from cerebrum_core.user_inator import (
    DEFAULT_CHAT_MODEL,
    DEFAULT_EMBED_MODEL,
    ConfigManager,
)
from cerebrum_core.utils.cache_inator import RetrievalCacheInator
from cerebrum_core.utils.file_util_inator import (
    CerebrumPaths,
    knowledgebase_index_inator,
)


def diff_collapser_inator(note: NoteStorage) -> NoteStorage:
    """
    Cleans up note diffs and prevents markdonw ballooning
    """
    # load note into memory
    history = note.history.content
    if len(history) <= 1:
        return note

    latest_by_version = {}
    version_order = []

    for entry in history:
        ver = entry.version
        if ver not in latest_by_version:
            version_order.append(ver)
        latest_by_version[ver] = entry

    note.history.content = [latest_by_version[v] for v in version_order]
    return note


class ArchiveInator:
    """
    Adds historical note versions, on a chunk by chunk basis in order
    to archive the note for analysis, and progress monitoring
    """

    def __init__(
        self,
        note: NoteStorage,
        archives_path: str,
        chunks: list[Document] | None = None,
    ) -> None:
        self.note = note
        self.archives_path = archives_path
        self.chunks = chunks

    def archive_init_inator(self) -> None:
        """
        Stores snapshots of notes in a historic database
        """
        self._get_archives()

    def archive_populator_inator(self) -> None:
        """
        Add note chunks to the archive
        """

        assert self.chunks is not None
        # pass chunk object
        # chunk notes
        note = [
            Document(
                page_content=chunk.page_content,
                metadata={
                    "note_id": chunk.metadata.get("note_id"),
                    "chunk_id": chunk.metadata.get("chunk_id"),
                    "fingerprint": chunk.metadata.get("fingerprint"),
                    "generated_at": chunk.metadata.get("generated_at"),
                    "header_level": chunk.metadata.get("header_level"),
                    "content_version": chunk.metadata.get("content_version"),
                },
            )
            for chunk in self.chunks
        ]

        self._get_archives().add_documents(note)

    def archive_cleaner_inator(self) -> None:
        """
        DANGER: Deletes entire collection(note)
        """
        try:
            self._get_archives().delete_collection()
            print(f"Deleted collection: {self.note.note_id}")

        except Exception as e:
            print(f"Collection not found or error: {self.note.note_id} - {e}")

    def archive_browser_inator(self, bubble_id) -> dict | None:
        note_file = (
            CerebrumPaths().get_notes_root(bubble_id) / f"{self.note.note_id}.json"
        )

        if not Path(self.archives_path).exists():
            return None

        if not note_file.exists():
            print(
                f" \n No note: {self.note.note_id}.json found for bubble: {bubble_id}",
            )

        raw_data = self._get_archives().get()

        versions = []
        for doc_content, metadata in zip(raw_data["documents"], raw_data["metadatas"]):
            version = metadata.get("version", self.note.metadata.content_version)
            versions.append(
                ArchivedNoteContent(
                    version=float(version),
                    content=doc_content,
                )
            )

        versions.sort(key=lambda x: x.version)

        historical_note = ArchivedNote(
            note_id=self.note.note_id,
            note_name=self.note.title,
            versions=versions,
        )

        return {"filename": note_file.name, "archive": historical_note}

    def _get_archives(self) -> Chroma:
        """Helper: Get Chroma archive instance from disk"""
        embedding_model = ConfigManager().load_config().models.embedding_model
        # TODO: find a better alternative than assert
        assert embedding_model is not None
        assert self.note is not None

        # embedd notes
        return Chroma(
            collection_name=self.note.note_id,
            embedding_function=OllamaEmbeddings(model=embedding_model),
            create_collection_if_not_exists=True,
            persist_directory=str(self.archives_path),
            collection_metadata={
                "note_title": self.note.title,
                "note_id": self.note.note_id,
                "bubble_id": self.note.bubble_id,
                # "bubble_name": self.note.bubble_name
            },
        )


# modify to allow for chunking and chunk by chunk analysis
class NoteToMarkdownInator:
    """
    Converts an AppFlowy-style note into markdown
    """

    def __init__(self, convert_tables: bool = True) -> None:
        self.convert_tables = convert_tables

    # ------------ Core Public Method ------------- #
    def flatten(self, note: NoteContent) -> str:
        """
        Main entry point - returns a flattened Markdown string.
        """
        children = note.document["children"]
        lines = []

        for block in children:
            handler = getattr(self, f"_handle_{block['type'].replace('/','_')}", None)
            if handler:
                result = handler(block)
                if result:
                    lines.append(result)
            lines.append("")

        return "\n".join(lines).strip()

    # ------------ Block Handlers --------------#
    def _handle_heading(self, block):
        level = block["data"]["level"]
        text = self._extract_text(block)
        return f"{'#' * level} {text}"

    def _handle_paragraph(self, block):
        text = self._extract_text(block)
        return text.strip() if text else None

    def _handle_divider(self, block):
        return "---"

    def _handle_table(self, block):
        if not self.convert_tables:
            return "[TABLE OMITTED]"

        return self._flatten_table(block)

    # ---------------- Helpers -----------------#
    def _extract_text(self, block):
        """Extracts linear text from delta[].insert"""
        if not block:
            return ""

        delta = block.get("data", {}).get("delta", [])
        text = ""
        for item in delta:
            if isinstance(item, dict):
                text += item.get("insert", "")
            elif isinstance(item, str):
                text += item
            return text

    def _flatten_table(self, table_block):
        """Converts Appflowy table -> markdown table."""
        rows = table_block["data"]["rowsLen"]
        cols = table_block["data"]["colsLen"]
        cells = table_block.get("children", [])

        matrix = [["" for _ in range(cols)] for _ in range(rows)]

        for cell in cells:
            data = cell.get("data", [])
            row = data.get("rowPosition")
            col = data.get("colPosition")

            # Defensive checks
            if row is None or col is None:
                continue
            if row < 0 or row >= rows or col < 0 or col >= cols:
                continue

            inner = cell["children"][0] if cell.get("children") else None
            matrix[row][col] = self._extract_text(inner)

        md = []
        md.append("| " + " | ".join(matrix[0]) + " |")
        md.append("| " + " | ".join(["---"] * cols) + " |")

        for row in matrix[1:]:
            md.append("| " + " | ".join(row) + " |")

        return "\n".join(md)


# Claude helped big time T_T (review it though)
class NoteAnalyserInator:
    """
    Ingests notes and converts them into queries for knowledgebase retrieval.
    Handles chunking, archiving, and semantic analysis of notes.
    """

    def __init__(
        self, note: NoteStorage, notes_path: Path, generate_artifact: bool = True
    ) -> None:
        """
        Initialize the note analyzer.

        Args:
            note: Pre-loaded NoteStorage object
            notes_path: Path to notes directory
            generate_artifact: Whether to generate markdown artifacts
        """
        self.note = note
        self.notes_path = notes_path
        self.generate_artifact = generate_artifact

        # Initialize state
        self.markdown_artifact: str = ""
        self.chunks: list[Document] = []
        self.translation_results: list[TranslatedQuery] = []
        self.constructed_query: dict = {"routes": []}
        self.retrieved_docs: list[Document] = []

        # Paths
        self.kb_archives = CerebrumPaths().get_kb_archives()
        self.bubble_cache_path = (
            CerebrumPaths().get_cache_dir() / "bubble_cache" / "notes"
        )
        self.archive_path = CerebrumPaths().get_note_archives(
            bubble_id=self.note.bubble_id
        )

        # LLM configs
        config = ConfigManager().load_config()
        self.embedding_model = config.models.embedding_model or DEFAULT_EMBED_MODEL
        self.chat_model = config.models.chat_model or DEFAULT_CHAT_MODEL

        # Initialize on creation
        self._initialize()

    def _initialize(self) -> None:
        """Initialize chunks and translations on instantiation."""
        self.chunks = self._note_chunker()
        if self.generate_artifact:
            self._generate_markdown_artifact(self.chunks)
        self.translation_results = self._note_to_query()

    def analyser_inator(self, prompt: str, top_k_chunks: int = 5) -> str:
        """
        Main analysis method. Analyzes note content against knowledge base.

        Args:
            prompt: Analysis prompt template with placeholders for:
                    {archived_data}, {current_note}, {context}
            top_k_chunks: Number of top chunks to use for context

        Returns:
            LLM analysis response
        """
        # Load archived data
        archived_data = self._load_archived_data()
        if not archived_data:
            return "No analysis for this note"

        # Check if note already archived
        if self.note.note_id not in archived_data:
            logging.info(f"Note {self.note.note_id} not in archive, will archive")
            self._archive_note()
        else:
            logging.info(f"Note {self.note.note_id} found in archive")

        # Construct queries and retrieve context
        cache_manager = RetrievalCacheInator(
            self._retrieve_inator(k=top_k_chunks),
            note_id=self.note.note_id,
            bubble_id=self.note.bubble_id,
        )
        cached_docs = cache_manager.deterministic_cache_fetcher()

        if cached_docs is not None:
            logging.info(
                f"Using cache retrieval results for analysis of note: f's{self.note.note_id}'"
            )
            self.retrieved_docs = cached_docs
        else:
            logging.info("No cache found, perfoming fresh retrieval")
            self._constructor_inator()
            self._retrieve_inator(k=top_k_chunks)
            RetrievalCacheInator(
                self._retrieve_inator(k=top_k_chunks),
                note_id=self.note.note_id,
                bubble_id=self.note.bubble_id,
            ).cache_populator_inator()

        # Build context from retrieved documents
        context_text = self._build_context(top_k_chunks)

        # Prepare note content
        flattened_note = NoteToMarkdownInator().flatten(self.note.content)

        # Generate analysis
        final_prompt = prompt.format(
            archived_data=archived_data,
            current_note=flattened_note,
            context=context_text,
        )

        response = OllamaLLM(model=self.chat_model).invoke(final_prompt)
        # cache anaylisis
        return response

    def _load_archived_data(self) -> dict | None:
        """Load archived note data for this bubble."""
        archive_manager = ArchiveInator(
            note=self.note,
            archives_path=str(self.archive_path),
            chunks=self.chunks,
        )
        if not archive_manager:
            return None
        return archive_manager.archive_browser_inator(self.note.bubble_id)

    def _archive_note(self) -> None:
        """Archive the current note with its chunks."""
        ArchiveInator(
            note=self.note,
            archives_path=str(self.archive_path),
            chunks=self.chunks,
        ).archive_populator_inator()

        logging.info(f"Archived note {self.note.note_id}")

    def _build_context(self, top_k: int) -> str:
        """
        Build context string from retrieved documents.

        Args:
            top_k: Number of top documents to include

        Returns:
            Formatted context string with summaries
        """
        # deduplicate results
        seen = set()
        dedup_docs = []

        for doc in self.retrieved_docs:
            if doc.page_content not in seen:
                seen.add(doc.page_content)
                dedup_docs.append(doc)

        context_docs = dedup_docs[:top_k]

        # Summarize chunks
        context_summaries = []
        for doc in context_docs:
            summary_prompt = f"""
            Summarize the following text in 1-2 sentences, keeping only the key factual information:
            {doc.page_content}
            """
            summary = OllamaLLM(model=self.chat_model).invoke(summary_prompt)
            context_summaries.append(summary.strip())

        return "\n\n".join(context_summaries)

    def _note_chunker(self) -> list[Document]:
        """
        Chunk note content into semantic Document objects.

        Returns:
            List of Document chunks with rich metadata
        """
        flat_note = NoteToMarkdownInator().flatten(self.note.content)

        splitter = MarkdownHeaderTextSplitter(
            headers_to_split_on=[
                ("#", "h1"),
                ("##", "h2"),
                ("###", "h3"),
                ("####", "h4"),
                ("#####", "h5"),
                ("######", "h6"),
            ],
            strip_headers=False,
        )

        chunks: list[Document] = splitter.split_text(flat_note)

        # Enhance each chunk with metadata
        for i, chunk in enumerate(chunks):
            header_metadata = chunk.metadata or {}
            header_level = max(
                (int(k[1:]) for k in header_metadata.keys() if k.startswith("h")),
                default=1,
            )
            header_text = header_metadata.get(f"h{header_level}", "Untitled")

            # Generate unique fingerprina
            chunk_fingerprint = self._generate_chunk_fingerprint(
                chunk.page_content.strip()
            )

            # Enrich metadata
            chunk.metadata.update(
                {
                    "note_id": self.note.note_id,
                    "bubble_id": self.note.bubble_id,
                    "chunk_id": i,
                    "fingerprint": chunk_fingerprint,
                    "header": header_text,
                    "header_level": header_level,
                    "chunk_length": len(chunk.page_content),
                    "content_version": self.note.metadata.content_version,
                    "chunker_version": "1.0",
                    "total_chunks": len(chunks),
                    "generated_at": datetime.now().isoformat(),
                }
            )

        return chunks

    def _generate_chunk_fingerprint(self, content: str) -> str:
        """Generate SHA256 fingerprint for content."""
        payload = {
            "note_id": self.note.note_id,
            "bubble_id": self.note.bubble_id,
            "content": content.strip(),
        }
        return hashlib.sha256(
            json.dumps(payload, separators=(",", ":")).encode("utf-8")
        ).hexdigest()

    def _generate_markdown_artifact(self, chunks: list[Document]) -> None:
        """
        Generate markdown artifact from chunks.

        Args:
            chunks: List of Document chunks to convert
        """
        if not chunks:
            logging.warning("No chunks to generate artifact from")
            return

        artifact: list[str] = []

        # Global metadata
        note_metadata = chunks[0].metadata
        artifact.append(
            "<!--\n"
            f"note_id: {note_metadata['note_id']}\n"
            f"bubble_id: {note_metadata['bubble_id']}\n"
            f"total_chunks: {len(chunks)}\n"
            f"chunker_version: {note_metadata['chunker_version']}\n"
            f"generated_at: {note_metadata['generated_at']}\n"
            "-->\n"
        )

        artifact.extend(
            [
                "# Chunked Note Artifact",
                f"**Note:** {self.note.title}",
                f"**Chunks:** {len(chunks)}",
                "",
            ]
        )

        # Add each chunk
        for chunk in chunks:
            content = chunk.page_content.strip()
            metadata_comment = self._generate_chunk_metadata_comment(chunk.metadata)

            artifact.extend(
                [
                    f"## Chunk {chunk.metadata['chunk_id'] + 1} (H{chunk.metadata['header_level']})",
                    f"**{chunk.metadata['header']}**",
                    metadata_comment,
                    content,
                    "",
                    "---",
                    "",
                ]
            )

        self.markdown_artifact = "\n".join(artifact)

    def _generate_chunk_metadata_comment(self, metadata: dict) -> str:
        """Generate YAML metadata comment for a chunk."""
        meta_subset = {
            "chunk_id": metadata.get("chunk_id"),
            "fingerprint": metadata.get("fingerprint"),
            "header": metadata.get("header"),
            "header_level": metadata.get("header_level"),
            "chunk_length": metadata.get("chunk_length"),
            "content_version": metadata.get("content_version"),
            "generated_at": metadata.get("generated_at"),
        }
        return "<!--\n" + yaml.dump(meta_subset, sort_keys=False) + "-->\n"

    def _note_to_query(self) -> list[TranslatedQuery]:
        """
        Translate note chunks into knowledge base queries.

        Returns:
            List of translated queries with routing information
        """
        translation_prompt_template = RosePrompts().get_prompt("rose_note_to_query")
        if not translation_prompt_template:
            raise ValueError("Prompt 'rose_note_to_query' not found in RosePrompts")

        available_stores = knowledgebase_index_inator(Path(self.kb_archives))
        translated_queries: list[TranslatedQuery] = []

        for chunk in self.chunks:
            try:
                filled_prompt = translation_prompt_template.format(
                    user_query=chunk.page_content, available_stores=available_stores
                )

                raw_output = OllamaLLM(model=self.chat_model).invoke(filled_prompt)
                logging.info(
                    f"Translated chunk {chunk.metadata['chunk_id']}: {raw_output[:100]}..."
                )

                parsed_query = self._parse_llm_json_output(raw_output)
                parsed_query.update(
                    {
                        "chunk_id": chunk.metadata["chunk_id"],
                        "chunk_fingerprint": chunk.metadata["fingerprint"],
                        "header": chunk.metadata["header"],
                        "header_level": chunk.metadata["header_level"],
                    }
                )

                tq = TranslatedQuery(**parsed_query)
                translated_queries.append(tq)

            except Exception as e:
                logging.warning(
                    f"Failed to translate chunk {chunk.metadata.get('chunk_id', 'unknown')}: {e}"
                )
                continue

        return translated_queries

    def _constructor_inator(self) -> dict:
        """
        Construct query routes from translated queries.

        Returns:
            Dictionary with validated routes
        """
        available_stores, _ = knowledgebase_index_inator(Path(self.kb_archives))

        # Build valid path set
        valid_paths = set()
        for domain in available_stores["domains"]:
            for subject in available_stores["subjects"]:
                valid_paths.add((domain, subject))

        # Construct routes
        for query in self.translation_results:
            for route in query.subqueries:
                if not route.domain or not route.subject:
                    logging.warning(
                        f"Skipping subquery with missing domain/subject: {route}"
                    )
                    continue

                if (route.domain, route.subject) not in valid_paths:
                    logging.warning(
                        f"Invalid path ({route.domain}, {route.subject}), skipping"
                    )
                    continue

                path = self.kb_archives / route.domain / route.subject
                self.constructed_query["routes"].append(
                    {
                        "subquery": route,
                        "path": str(path),
                        "domain": route.domain,
                        "subject": route.subject,
                    }
                )

        logging.info(f"Constructed {len(self.constructed_query['routes'])} routes")
        return self.constructed_query

    def _retrieve_inator(self, k: int = 3) -> list[Document]:
        """
        Retrieve relevant documents from knowledge base.

        Args:
            k: Number of documents to retrieve per query

        Returns:
            List of retrieved document sets
        """
        for route in self.constructed_query["routes"]:
            try:
                store = Chroma(
                    collection_name=route["subject"],
                    persist_directory=route["path"],
                    embedding_function=OllamaEmbeddings(model=self.embedding_model),
                )

                retriever = store.as_retriever(
                    search_type="mmr", search_kwargs={"k": k, "fetch_k": 15}
                )

                results = retriever.get_relevant_documents(route["subquery"].text)
                for result in results:
                    self.retrieved_docs.append(result)

                logging.info(
                    f"Retrieved {len(results)} docs for {route['domain']}/{route['subject']}"
                )

            except Exception as e:
                logging.error(f"Failed to retrieve from {route['path']}: {e}")
                continue

        return self.retrieved_docs

    def _parse_llm_json_output(self, output: str) -> dict:
        """
        Safely parse JSON from LLM output.

        Args:
            output: Raw LLM output string

        Returns:
            Parsed dictionary

        Raises:
            ValueError: If JSON cannot be parsed
        """
        try:
            return json.loads(output)
        except json.JSONDecodeError:
            import re

            match = re.search(r"\{.*\}", output, re.DOTALL)
            if match:
                return json.loads(match.group())
            raise ValueError(f"Could not parse JSON from: {output[:200]}...")

    def refresh_note(self, updated_note: NoteStorage) -> None:
        """
        Refresh analyzer with updated note content.

        Args:
            updated_note: New NoteStorage object
        """
        self.note = updated_note
        self.markdown_artifact = ""
        self.chunks = []
        self.translation_results = []
        self.constructed_query = {"routes": []}
        self.retrieved_docs = []
        self._initialize()
        logging.info(f"Refreshed analyzer with note {updated_note.note_id}")

    def get_chunk_by_id(self, chunk_id: int) -> Optional[Document]:
        """Get specific chunk by ID."""
        for chunk in self.chunks:
            if chunk.metadata.get("chunk_id") == chunk_id:
                return chunk
        return None

    def get_chunks_by_header(self, header: str) -> list[Document]:
        """Get all chunks matching a header."""
        return [
            chunk for chunk in self.chunks if chunk.metadata.get("header") == header
        ]

    def export_artifact(self, output_path: Path) -> None:
        """
        Export markdown artifact to file.

        Args:
            output_path: Where to save the artifact
        """
        if not self.markdown_artifact:
            raise ValueError("No artifact generated yet")

        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(self.markdown_artifact, encoding="utf-8")
        logging.info(f"Exported artifact to {output_path}")

    def __repr__(self) -> str:
        return (
            f"NoteAnalyserInator(note_id={self.note.note_id}, "
            f"chunks={len(self.chunks)}, "
            f"queries={len(self.translation_results)})"
        )
