import hashlib
import json
import logging
import os
import re
from pathlib import Path
from typing import List

import pymupdf4llm
import tiktoken
import yaml
from langchain_chroma import Chroma
from langchain_core.documents import Document
from langchain_ollama import OllamaEmbeddings, OllamaLLM
from langchain_text_splitters import (
    MarkdownHeaderTextSplitter,
    RecursiveCharacterTextSplitter,
)

from agents.rose import RosePrompts
from cerebrum_core.model_inator import FileMetadata, TranslatedQuery
from cerebrum_core.user_inator import DEFAULT_CHAT_MODEL, ConfigManager
from cerebrum_core.utils.file_util_inator import (
    CerebrumPaths,
    ChunkRegisterInator,
    knowledgebase_index_inator,
)

os.makedirs("./logs", exist_ok=True)
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    handlers=[
        logging.FileHandler("logs/cerebrum_debug.log"),
        logging.StreamHandler(),
    ],
)
logger = logging.getLogger("cerebrum")


class MarkdownConverter:
    """
    Converts PDF files to Markdown with LLM-enriched YAML frontmatter.
    Handles file sanitization and metadata generation.
    """

    def __init__(self, filepath: Path):
        self.filepath = filepath
        self.fingerprint = self._fingerprint_inator(filepath)
        self.pdf_metadata = self._extract_pdf_metadata(filepath)

    def convert(self, metadata: dict | None = None) -> tuple[Path, FileMetadata]:
        """
        Convert PDF to markdown with LLM-sanitized metadata.

        Returns:
            tuple[Path, FileMetadata]: Path to markdown file and enriched metadata
        """
        # Merge PDF metadata with any provided metadata
        combined_metadata = {**self.pdf_metadata, **(metadata or {})}

        # Use LLM to sanitize filename and generate metadata
        sanitized_metadata = self.sanitize_inator(
            filename=self.filepath.name, metadata=combined_metadata
        )

        # Clean the title to remove filesystem-unsafe characters
        sanitized_metadata.title = self._sanitize_filename(sanitized_metadata.title)

        domain = sanitized_metadata.domain
        subject = sanitized_metadata.subject
        filename = sanitized_metadata.title

        # Setup output path
        path = CerebrumPaths()
        markdown_dir = path.get_kb_artifacts() / domain / subject
        markdown_dir.mkdir(parents=True, exist_ok=True)

        # Convert PDF to markdown
        md_body = pymupdf4llm.to_markdown(self.filepath, show_progress=True)

        # Add YAML frontmatter
        yaml_front = self._yaml_inator(sanitized_metadata)
        full_md = f"{yaml_front}{md_body}"

        # Write to file
        md_output = markdown_dir / f"{filename}.md"
        md_output.write_text(full_md, encoding="utf-8")

        logger.info(f"Converted {self.filepath.name} → {md_output}")
        return md_output, sanitized_metadata

    def sanitize_inator(self, filename: str, metadata: dict | None) -> FileMetadata:
        """
        Use LLM to sanitize filename and enrich metadata.
        Offloading renaming and sanitization to LLM for consistent categorization.
        """
        chat_model = (
            ConfigManager().load_config().models.chat_model or DEFAULT_CHAT_MODEL
        )

        metadata_json = json.dumps(metadata, indent=2) if metadata else "{}"
        sanitize_prompt = RosePrompts.get_prompt("rose_rename")

        if not sanitize_prompt:
            raise ValueError("Prompt 'rose_rename' not found in RosePrompts")

        filled_prompt = sanitize_prompt.format(
            filename=filename, metadata=metadata_json
        )

        sanitized_response = OllamaLLM(model=chat_model).invoke(filled_prompt)
        logger.info(f"LLM sanitization response: {sanitized_response}")

        try:
            parsed_response = json.loads(sanitized_response)
        except json.JSONDecodeError:
            raise ValueError(f"LLM did not return valid JSON: {sanitized_response}")

        return FileMetadata(**parsed_response)

    def _fingerprint_inator(self, filepath: Path) -> str:
        """Generate unique fingerprint for document based on content."""
        hasher = hashlib.sha256()
        with open(filepath, "rb") as f:
            for chunk in iter(lambda: f.read(8192), b""):
                hasher.update(chunk)
        return hasher.hexdigest()[:16]

    def _yaml_inator(self, metadata: FileMetadata) -> str:
        """Generate YAML frontmatter from metadata."""
        yaml_dump = yaml.dump(metadata.model_dump(), sort_keys=False)
        return f"---\n{yaml_dump}---\n\n"

    def _sanitize_filename(self, filename: str) -> str:
        """
        Remove or replace filesystem-unsafe characters from filename.
        Preserves hyphens and underscores for readability.
        """
        # Replace common problematic characters
        replacements = {
            "/": "-",
            "\\": "-",
            ":": "-",
            "*": "",
            "?": "",
            '"': "",
            "<": "",
            ">": "",
            "|": "-",
        }

        sanitized = filename
        for old, new in replacements.items():
            sanitized = sanitized.replace(old, new)

        # Remove multiple consecutive hyphens
        while "--" in sanitized:
            sanitized = sanitized.replace("--", "-")

        # Remove leading/trailing hyphens
        sanitized = sanitized.strip("-")

        return sanitized

    def _extract_pdf_metadata(self, filepath: Path) -> dict:
        """Extract metadata from PDF file using PyMuPDF."""
        import pymupdf

        try:
            doc = pymupdf.open(filepath)
            metadata = doc.metadata
            doc.close()

            # Clean up metadata - remove None values and empty strings
            cleaned_metadata = {}

            if metadata:
                if metadata.get("author"):
                    # Split multiple authors if separated by common delimiters
                    authors = metadata["author"]
                    if ";" in authors:
                        cleaned_metadata["authors"] = [
                            a.strip() for a in authors.split(";")
                        ]
                    elif "," in authors and " and " not in authors.lower():
                        cleaned_metadata["authors"] = [
                            a.strip() for a in authors.split(",")
                        ]
                    else:
                        cleaned_metadata["authors"] = [authors.strip()]

                if metadata.get("title"):
                    cleaned_metadata["title"] = metadata["title"].strip()

                if metadata.get("subject"):
                    cleaned_metadata["subject"] = metadata["subject"].strip()

                if metadata.get("keywords"):
                    # Keywords might be comma-separated
                    keywords = metadata["keywords"]
                    if "," in keywords:
                        cleaned_metadata["keywords"] = [
                            k.strip() for k in keywords.split(",")
                        ]
                    else:
                        cleaned_metadata["keywords"] = [keywords.strip()]

                # Additional metadata that might be useful
                if metadata.get("creator"):
                    cleaned_metadata["creator"] = metadata["creator"].strip()

                if metadata.get("producer"):
                    cleaned_metadata["producer"] = metadata["producer"].strip()

            logger.info(f"Extracted PDF metadata: {cleaned_metadata}")
            return cleaned_metadata

        except Exception as e:
            logger.warning(f"Failed to extract PDF metadata: {e}")
            return {}


class MarkdownChunker:
    """
    Splits markdown into semantic chunks with byte-coordinate tracking.
    Generates .chunked.md files with HTML comment annotations.
    """

    def __init__(self):
        self.registry = ChunkRegisterInator()
        self.tokenizer = tiktoken.get_encoding("cl100k_base")
        self.chunks: List[Document] = []

    def chunk(self, markdown_path: Path, doc_fingerprint: str) -> Path:
        """
        Split markdown by headers and token limits, annotate with HTML comments.

        Args:
            markdown_path: Path to .md file with YAML frontmatter
            doc_fingerprint: Unique identifier for the document

        Returns:
            Path to .chunked.md file with HTML comment annotations
        """
        full_text = markdown_path.read_text(encoding="utf-8")
        max_chunk_tokens = 4000

        # Extract YAML frontmatter
        yaml_pattern = re.compile(r"^(---\n.*?\n---\n\n)", re.S)
        yaml_match = yaml_pattern.match(full_text)

        if yaml_match:
            yaml_frontmatter = yaml_match.group(1)
            text = full_text[len(yaml_frontmatter) :]  # Content after YAML
        else:
            yaml_frontmatter = ""
            text = full_text

        # Split by markdown headers
        header_levels = [
            ("#", "Header 1"),
            ("##", "Header 2"),
            ("###", "Header 3"),
            ("####", "Header 4"),
            ("#####", "Header 5"),
            ("######", "Header 6"),
        ]

        header_splitter = MarkdownHeaderTextSplitter(
            headers_to_split_on=header_levels, strip_headers=False
        )
        header_chunks = header_splitter.split_text(text)

        # Recursive splitter for oversized chunks
        recursive_splitter = RecursiveCharacterTextSplitter(
            chunk_size=max_chunk_tokens,
            chunk_overlap=200,
            length_function=lambda t: len(self.tokenizer.encode(t)),
            add_start_index=True,
        )

        # Process chunks
        processed_chunks = []
        for idx, chunk in enumerate(header_chunks):
            token_count = self._token_count(chunk.page_content)

            if token_count <= max_chunk_tokens:
                processed_chunks.append(chunk)
            else:
                # Split oversized chunks recursively
                sub_chunks = recursive_splitter.split_documents([chunk])
                for sub_chunk in sub_chunks:
                    sub_chunk.metadata["parent_chunk_index"] = idx
                    # Preserve header metadata from parent chunk
                    for key, value in chunk.metadata.items():
                        if key not in sub_chunk.metadata:
                            sub_chunk.metadata[key] = value
                    processed_chunks.append(sub_chunk)

        # Build annotated markdown with byte coordinates
        output_lines = []
        registry_rows = []
        byte_cursor = 0

        for chunk_idx, chunk in enumerate(processed_chunks):
            content = chunk.page_content
            content_bytes = content.encode("utf-8")
            byte_length = len(content_bytes)

            parent_idx = chunk.metadata.get("parent_chunk_index", None)
            chunk_type = "recursive" if parent_idx is not None else "header"
            token_count = self._token_count(content)

            # Build HTML comment metadata block with header information
            metadata_lines = [
                "<!-- CHUNK_START",
                f"chunk_index: {chunk_idx}",
                f"chunk_type: {chunk_type}",
                f"parent_chunk_index: {parent_idx}",
                f"byte_start: {byte_cursor}",
                f"byte_end: {byte_cursor + byte_length}",
                f"token_count: {token_count}",
            ]

            # Add header hierarchy metadata
            for key, value in chunk.metadata.items():
                if key.startswith("Header") and value:
                    metadata_lines.append(f"{key.lower().replace(' ', '_')}: {value}")

            metadata_lines.append("-->")
            metadata_block = "\n".join(metadata_lines)

            output_lines.append(metadata_block)
            output_lines.append(content)
            output_lines.append("<!-- CHUNK_END -->")
            output_lines.append("")  # Blank line separator

            # Register chunk in database
            registry_rows.append(
                (
                    doc_fingerprint,
                    chunk_idx,
                    byte_cursor,
                    byte_cursor + byte_length,
                    token_count,
                    chunk_type,
                    parent_idx,
                )
            )

            byte_cursor += byte_length

        # Write chunked markdown (same directory as original .md)
        # Include YAML frontmatter at the top
        chunked_path = markdown_path.with_name(markdown_path.stem + ".chunked.md")

        final_output = yaml_frontmatter + "\n".join(output_lines)
        chunked_path.write_text(final_output, encoding="utf-8")

        # Register all chunks in database
        self.registry.register_chunks(registry_rows)
        logger.info(f"Chunked {len(processed_chunks)} chunks → {chunked_path}")

        return chunked_path

    def _token_count(self, text: str) -> int:
        """Count tokens in text."""
        return len(self.tokenizer.encode(text))


class EmbeddInator:
    """
    Handles resumable embedding of document chunks using byte-coordinate access.
    Reads chunks directly from .chunked.md files without loading entire file.
    """

    def __init__(self, fingerprint: str):
        self.fingerprint = fingerprint
        self.registry = ChunkRegisterInator()
        self.archives_path = str(CerebrumPaths().get_kb_archives())

        embedding_model = ConfigManager().load_config().models.embedding_model
        if not embedding_model:
            raise ValueError("Embedding model not configured in config")

        self.embedding_model = embedding_model

    def embed_from_chunked_markdown(
        self,
        chunked_markdown: Path,
        collection_name: str,
    ) -> None:
        """
        Embed chunks from .chunked.md file using byte coordinates.
        Safe to restart - only embeds unembedded chunks.

        Args:
            chunked_markdown: Path to .chunked.md file
            collection_name: Chroma collection name (typically subject)
        """
        # Check progress
        progress = self.registry.get_embedding_progress(self.fingerprint)

        if progress["total"] == 0:
            logger.warning("No chunks registered - aborting")
            return

        if progress["remaining"] == 0:
            logger.info("✓ All chunks already embedded")
            return

        logger.info(
            f"Resuming: {progress['completed']}/{progress['total']} completed "
            f"({progress['progress_pct']:.1f}%)"
        )

        # Get unembedded chunks from registry
        unembedded = self.registry.get_unembedded_chunks(self.fingerprint)

        # Read file once as bytes
        with open(chunked_markdown, "rb") as f:
            file_bytes = f.read()

        # Parse YAML frontmatter for metadata
        yaml_metadata = self._extract_yaml_metadata(chunked_markdown)

        # Extract domain and subject from YAML metadata
        domain = yaml_metadata.get("domain", "default")
        subject = yaml_metadata.get("subject", "default")

        # Initialize Chroma with correct path
        chromadb = self._get_archives(collection_name, yaml_metadata, domain, subject)

        # Embed each unembedded chunk
        for record in unembedded:
            chunk_index = record.chunk_index
            byte_start = record.byte_start
            byte_end = record.byte_end

            # Extract chunk content using byte coordinates
            chunk_bytes = file_bytes[byte_start:byte_end]
            chunk_content = chunk_bytes.decode("utf-8")

            # Parse chunk metadata from the chunked file to get headers
            chunk_headers = self._extract_chunk_headers(
                chunked_markdown, int(chunk_index)
            )

            # Create document with metadata
            doc_metadata = {
                "fingerprint": self.fingerprint,
                "chunk_index": chunk_index,
                "chunk_type": record.chunk_type,
                "parent_chunk_index": (
                    record.parent_chunk_index if record.parent_chunk_index else ""
                ),
                "filename": yaml_metadata.get("title", "unknown"),
                "domain": yaml_metadata.get("domain", "unknown"),
                "subject": yaml_metadata.get("subject", "unknown"),
            }

            # Add header hierarchy to metadata
            doc_metadata.update(chunk_headers)

            # Convert list values to strings for Chroma compatibility
            for key, value in doc_metadata.items():
                if isinstance(value, list):
                    doc_metadata[key] = ", ".join(str(v) for v in value)
                elif value is None:
                    doc_metadata[key] = ""

            doc = Document(
                page_content=chunk_content,
                metadata=doc_metadata,
            )

            try:
                chromadb.add_documents([doc])
                self.registry.mark_embedded(self.fingerprint, int(chunk_index))
                logger.info(f"✓ Embedded chunk {chunk_index}")
            except Exception as e:
                logger.error(f"✗ Failed at chunk {chunk_index}: {e}")
                logger.info("Progress saved. Re-run to resume.")
                raise

        logger.info("✓ Embedding complete")

    def delete_by_fingerprint(
        self,
        collection_name: str,
        fingerprint: str,
        domain: str = "default",
        subject: str = "default",
    ) -> None:
        """Delete all chunks for a document from vector database."""
        chromadb = self._get_archives(collection_name, {}, domain, subject)
        chunks = self.registry.get_unembedded_chunks(fingerprint)
        ids = [str(c.chunk_index) for c in chunks]

        if not ids:
            logger.warning(f"No chunks found for fingerprint: {fingerprint}")
            return

        chromadb.delete(ids=ids)
        logger.info(f"✓ Deleted {len(ids)} chunks for fingerprint {fingerprint}")

    def list_collections(self) -> List[str]:
        """List all Chroma collections."""
        chromadb = self._get_archives("default", {}, "default", "default")
        return [c.name for c in chromadb._client.list_collections()]

    def get_collection_count(
        self, collection_name: str, domain: str = "default", subject: str = "default"
    ) -> int:
        """Get number of documents in collection."""
        chromadb = self._get_archives(collection_name, {}, domain, subject)
        return chromadb._collection.count()

    def delete_collection(
        self, collection_name: str, domain: str = "default", subject: str = "default"
    ) -> None:
        """Delete entire collection."""
        chromadb = self._get_archives(collection_name, {}, domain, subject)
        chromadb.delete_collection()
        logger.info(f"✓ Collection '{collection_name}' deleted successfully")

    def _get_archives(
        self,
        collection_name: str,
        metadata: dict,
        domain: str = "default",
        subject: str = "default",
    ):
        """Initialize Chroma client with proper directory structure."""
        # Build path: archives_root/domain/subject
        collection_path = Path(self.archives_path) / domain / subject
        collection_path.mkdir(parents=True, exist_ok=True)

        return Chroma(
            collection_name=collection_name,
            embedding_function=OllamaEmbeddings(model=self.embedding_model),
            persist_directory=str(collection_path),
            collection_metadata=metadata,
        )

    def _extract_yaml_metadata(self, markdown_path: Path) -> dict:
        """Extract YAML frontmatter from markdown file."""
        text = markdown_path.read_text(encoding="utf-8")

        # Match YAML frontmatter
        yaml_pattern = re.compile(r"^---\n(.*?)\n---\n", re.S)
        match = yaml_pattern.match(text)

        if not match:
            logger.warning("No YAML frontmatter found")
            return {}

        yaml_content = match.group(1)
        try:
            metadata = yaml.safe_load(yaml_content)

            # Convert lists to strings for Chroma compatibility
            if metadata:
                for key, value in metadata.items():
                    if isinstance(value, list):
                        metadata[key] = ", ".join(str(v) for v in value)
                    elif value is None:
                        metadata[key] = ""

            return metadata
        except yaml.YAMLError as e:
            logger.error(f"Failed to parse YAML: {e}")
            return {}

    def _extract_chunk_headers(self, markdown_path: Path, chunk_index: int) -> dict:
        """Extract header metadata from a specific chunk in the .chunked.md file."""
        text = markdown_path.read_text(encoding="utf-8")

        # Find the specific chunk's metadata block
        pattern = rf"<!-- CHUNK_START\n.*?chunk_index: {chunk_index}\n(.*?)-->"
        match = re.search(pattern, text, re.S)

        if not match:
            return {}

        metadata_block = match.group(1)
        headers = {}

        # Extract header_N fields
        for line in metadata_block.split("\n"):
            line = line.strip()
            if line.startswith("header_"):
                key, value = line.split(":", 1)
                headers[key.strip()] = value.strip()

        return headers


class RetrieverInator:
    """
    Loads Chroma databases and retrieves relevant chunks for RAG queries.
    """

    def __init__(
        self, archives_root: str, embedding_model: str, chat_model: str
    ) -> None:
        self.archives_root = archives_root
        self.embedding_model = OllamaEmbeddings(model=embedding_model)

        if not chat_model:
            raise ValueError("Chat model must be configured")
        self.chat_model = OllamaLLM(model=chat_model)

        self.constructed_query = {}
        self.subqueries = []

    def translator_inator(self, user_query: str, translation_prompt: str):
        """Translate user query into structured archive queries."""
        if not translation_prompt:
            raise ValueError("Prompt 'rose_query_translator' not found in RosePrompts")

        available_stores = knowledgebase_index_inator(Path(self.archives_root))

        filled_prompt = translation_prompt.format(
            user_query=user_query, available_stores=available_stores
        )
        translated_query = self.chat_model.invoke(filled_prompt)
        logger.info(f"Raw translated query: {translated_query!r}")

        try:
            parsed_query = json.loads(translated_query)
        except json.JSONDecodeError:
            raise ValueError(f"LLM did not return valid JSON: {translated_query}")

        return TranslatedQuery(**parsed_query)

    def constructor_inator(self, translated_query: TranslatedQuery):
        """Construct archive paths from translated query."""
        available_stores, _ = knowledgebase_index_inator(Path(self.archives_root))
        valid_paths = set()

        for domain in available_stores["domains"]:
            for subject in available_stores["subjects"]:
                valid_paths.add((domain, subject))

        self.constructed_query = {"routes": []}

        for subquery in translated_query.subqueries:
            domain = subquery.domain
            subject = subquery.subject

            if not domain or not subject:
                logger.warning("Skipping subquery with missing domain/subject")
                continue

            if (domain, subject) not in valid_paths:
                logger.warning(
                    f"Invalid domain/subject pair: ({domain}, {subject}) - skipping"
                )
                continue

            path = Path(self.archives_root) / domain / subject
            self.constructed_query["routes"].append(
                {"subquery": subquery, "path": str(path)}
            )

        return self.constructed_query

    def retrieve_inator(self, k: int = 3):
        """Query archives and retrieve relevant chunks."""
        for route in self.constructed_query["routes"]:
            store = Chroma(
                collection_name=route["subquery"].subject,
                persist_directory=route["path"],
                embedding_function=self.embedding_model,
            )
            retriever = store.as_retriever(
                search_type="mmr", search_kwargs={"k": k, "fetch_k": 15}
            )
            result = retriever.invoke(route["subquery"].text)
            self.subqueries.append(result)

        return self.subqueries

    def generate_inator(self, user_query: str, top_k_chunks: int = 5):
        """Generate response using retrieved documents."""
        # Flatten and deduplicate
        flat_docs = [doc for docs in self.subqueries for doc in docs]

        seen = set()
        dedup_docs = []
        for doc in flat_docs:
            if doc.page_content not in seen:
                seen.add(doc.page_content)
                dedup_docs.append(doc)

        selected_docs = dedup_docs[:top_k_chunks]

        # Summarize each chunk
        chunk_summaries = []
        for doc in selected_docs:
            summary_prompt = f"""
            Summarize the following text in 1–2 sentences, keeping only the key factual information:
            {doc.page_content}
            """
            summary = self.chat_model.invoke(summary_prompt)
            chunk_summaries.append(summary.strip())

        context_text = "\n\n".join(chunk_summaries)

        # Generate answer
        base_prompt = RosePrompts.get_prompt("rose_answer")
        if not base_prompt:
            raise ValueError("Prompt 'rose_answer' not found in RosePrompts")

        final_prompt = (
            base_prompt + "\n\nAdditional Instructions:\n"
            "- First give a 1–2 sentence summary answer.\n"
            "- Then, if relevant, provide a more detailed explanation under 'Further Explanation:'.\n"
            "- Condense overlapping info and avoid repeating facts.\n"
            "- Only use the provided context; do not hallucinate."
        )

        final_prompt = final_prompt.format(question=user_query, context=context_text)
        response = self.chat_model.invoke(final_prompt)

        return response
