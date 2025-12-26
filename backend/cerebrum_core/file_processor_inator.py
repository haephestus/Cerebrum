import hashlib
import json
import logging
import os
from pathlib import Path

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
        logging.StreamHandler(),  # optional: still prints to console
    ],
)
logger = logging.getLogger("cerebrum")


class IngestInator:
    """
    ingestinator converts pdf(for now) into markdown, and embeds them into
    a knowledgebase archiver
    """

    def __init__(self, filepath: Path) -> None:
        self.metatdata = {}
        self.filepath = filepath
        self.chunks: list[Document] = []
        self.registry = ChunkRegisterInator()
        self.fingerprint = self._fingerprint_inator(filepath)
        self.archives_path = CerebrumPaths().get_kb_archives()
        self.embedding_model = ConfigManager().load_config().models.embedding_model

    def embedd_inator(self, collection_name: str, chunk_fingerprint: str) -> None:
        """
        store chunks in archives
        """
        # TODO: find a better alternative than assert
        assert self.embedding_model is not None, "embedding_model is required"
        assert self.archives_path is not None, "archives_path is required"

        progress = self.registry.get_embedding_progress(
            chunk_fingerprint=chunk_fingerprint
        )

        if progress["remaining"] == 0 and progress["total"] > 0:
            print("All chunks already embedded!")
            return

        if progress["total"] > 0:
            print(
                f"Resuming: {progress['remaining']}/{progress['total']} chunks remaining"
            )

        unembedded = self.registry.get_unembedded_chunks(self.fingerprint)
        unembedded_indices = {chunk.chunk_index for chunk in unembedded}

        chunks_to_embed = [
            (i, chunk)
            for i, chunk in enumerate(self.chunks)
            if f"chunk_{i:04d}" in unembedded_indices
        ]

        if not chunks_to_embed:
            print("No chunks to embed")
            return

        # embedding
        # WARN: look into making this framework agnostic
        # (split it into a seperate embedding funcion)
        embedding_llm = OllamaEmbeddings(model=self.embedding_model)
        chromadb = Chroma(
            collection_name=collection_name,
            persist_directory=str(self.archives_path),
            embedding_function=embedding_llm,
            collection_metadata=self.metatdata,
        )

        for idx, (i, chunk) in enumerate(chunks_to_embed, 1):
            chunk_index = f"chunk_{i:04d}"
            try:
                chromadb.add_documents([chunk])
                self.registry.mark_embedded(self.fingerprint, chunk_index)
                print(f"✓ Embedded {idx}/{len(chunks_to_embed)} ({chunk_index})")
            except Exception as e:
                print(f"✗ Failed at {chunk_index}: {e}")
                print("Progress saved. Run again to resume.")
                raise
        print(f"✓ Complete! All {progress['total']} chunks embedded.")

    def sanitize_inator(self, filename: str, metadata: dict | None):
        """
        renames files to chromadb ready strings
        while also preserving or updating metadata
        offloading renaming and sanitization to llm
        """
        chat_model = (
            ConfigManager().load_config().models.chat_model or DEFAULT_CHAT_MODEL
        )
        metadata_json = json.dumps(metadata, indent=2) if metadata else "{}"
        santize_prompt = RosePrompts.get_prompt("rose_rename")
        if not santize_prompt:
            raise ValueError("Prompt 'rose_rename' not fount in RosePrompts")
        filled_prompt = santize_prompt.format(filename=filename, metadata=metadata_json)
        sanitized_prompt = OllamaLLM(model=chat_model).invoke(filled_prompt)

        try:
            parsed_prompt = json.loads(sanitized_prompt)
        except json.JSONDecodeError:
            raise ValueError(f"LLM did not return valid model: {sanitized_prompt}")

        return FileMetadata(**parsed_prompt)

    def markdown_inator(self, metadata: FileMetadata):
        """
        convert files to markdown
        """
        domain = metadata.domain
        subject = metadata.subject
        filename = metadata.title
        self.metatdata = {"filename": filename, "domain": domain, "subject": subject}

        path = CerebrumPaths()
        markdown_dir = path.get_kb_root() / "markdown" / domain / subject
        markdown_dir.mkdir(parents=True, exist_ok=True)

        md_body = pymupdf4llm.to_markdown(self.filepath, show_progress=True)

        # add yaml front matter to the documents
        yaml_front = self._yaml_inator(metadata)
        full_md = f"{yaml_front}{md_body}"

        md_output = markdown_dir / f"{filename}.md"
        md_output.write_text(full_md, encoding="utf-8")
        return self.metatdata

    def chunk_inator(self, markdown_filepath: Path) -> list[Document]:
        """
        input markdown files
        split md according at header_levels
        """
        md_text = markdown_filepath.read_text(encoding="utf-8")
        max_chunk_tokens = 4000

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
        header_chunks = header_splitter.split_text(md_text)

        tokenizer = tiktoken.get_encoding("cl100k_base")

        def len_and_overlap(text: str) -> tuple[int, int]:
            return len(tokenizer.encode(text)), 200

        recursive_splitter = RecursiveCharacterTextSplitter(
            chunk_size=max_chunk_tokens,
            chunk_overlap=200,
            length_function=len_and_overlap,
            add_start_index=True,
        )
        for idx, chunk in enumerate(header_chunks):
            if len_and_overlap(chunk.page_content)[0] <= max_chunk_tokens:
                self.chunks.append(chunk)
            else:
                sub_chunks = recursive_splitter.split_documents([chunk])
                for sub_chunk in sub_chunks:
                    sub_chunk.metadata["parent_chunk_index"] = f"chunk_{idx:04d}"
                    self.chunks.append(sub_chunk)

        self._chunk_register_inator(self.fingerprint, self.chunks)

        return self.chunks

    def _fingerprint_inator(self, filepath: Path) -> str:
        """
        Generate a unique fingerprint for a document based on its content
        """
        hasher = hashlib.sha256()
        with open(filepath, "rb") as f:
            for chunk in iter(lambda: f.read(8192), b""):
                hasher.update(chunk)
        return hasher.hexdigest()[:16]

    def _yaml_inator(self, metadata: FileMetadata) -> str:
        yaml_dump = yaml.dump(metadata.model_dump(), sort_keys=False)
        return f"---\n{yaml_dump}---\n\n"

    def _chunk_register_inator(self, fingerprint: str, chunks: list[Document]):
        """Register all chunks in the database for tracking"""
        chunk_rows = []

        for i, chunk in enumerate(chunks):
            content = chunk.page_content
            chunk_index = f"chunk_{i:04d}"

            chunk_type = "header" if chunk.metadata else "recursive"
            parent_index = chunk.metadata.get("parent_chunk_index", None)

            chunk_row = (
                fingerprint,
                chunk_index,
                chunk.metadata.get("start_index", 0),
                chunk.metadata.get("start_index", 0) + len(content),
                len(content.split()),
                chunk_type,
                parent_index,
            )
            chunk_rows.append(chunk_row)

        self.registry.register_chunks(chunk_rows)


class RetrieverInator:
    """
    Loads chroma dbs into memory
    retrieves relevant info for rag query
    grades retrieved data on relevance to query
    """

    def __init__(
        self, archives_root: str, embedding_model: str, chat_model: str
    ) -> None:
        self.archives_root = archives_root
        self.embedding_model = OllamaEmbeddings(model=embedding_model)
        self.chat_model = OllamaLLM(model=chat_model)
        self.constructed_query = {}
        self.subqueries = []

    def translator_inator(self, user_query: str, translation_prompt: str):
        """
        translates user input into archives queries
        """

        # WARN: look into question(query) specific translation
        #       match each subquery to its relevant domain/subject
        #       step back / rewrite / sub-question / HyDE

        translation_prompt = translation_prompt
        if not translation_prompt:
            raise ValueError("Prompt 'rose_query_translator' not found in RosePrompts")

        available_stores = knowledgebase_index_inator(Path(self.archives_root))

        filled_prompt = translation_prompt.format(
            user_query=user_query, available_stores=available_stores
        )
        translated_query = self.chat_model.invoke(filled_prompt)
        logging.info(f"Raw translated query: {translated_query!r}")

        try:
            parsed_query = json.loads(translated_query)
        except json.JSONDecodeError:
            raise ValueError(f"LLM did not return valid JSON: {translated_query}")

        return TranslatedQuery(**parsed_query)

    def constructor_inator(self, translated_query: TranslatedQuery):
        """
        constructs archives queries from user input
        """
        # WARN: archives matching has not been implemented
        # the constructor returns subqueries and routes to relevant archives

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
                logging.warning("skipping subquery with missing domain/subject")
                continue

            if (domain, subject) not in valid_paths:
                logging.warning(
                    f"Invalid domain/subject pair: ({domain}, {subject}) skippng subquery"
                )
                continue
            path = Path(self.archives_root) / domain / subject
            self.constructed_query["routes"].append(
                {"subquery": subquery, "path": str(path)}
            )

        return self.constructed_query

    def retrieve_inator(self, k: int = 3):
        """
        queries archives using constructed_query
        and passes results to generate_inator for final response
        """

        # TODO: similarity_search vs as_retriever
        for route in self.constructed_query["routes"]:
            store = Chroma(
                collection_name=route["subquery"].subject,
                persist_directory=route["path"],
                embedding_function=self.embedding_model,
            )
            retrieve = store.as_retriever(
                search_type="mmr", search_kwargs={"k": k, "fetch_k": 15}
            )
            result = retrieve.invoke(route["subquery"].text)
            self.subqueries.append(result)

        return self.subqueries

    def generate_inator(self, user_query: str, top_k_chunks: int = 5):
        """
        Generates a response to user_query using retrieved documents,
        summarizing and deduplicating chunks, and producing tiered output.
        """
        # Flatten retrieved documents
        flat_docs = [doc for docs in self.subqueries for doc in docs]

        # Deduplicate chunks based on page_content
        seen = set()
        dedup_docs = []
        for doc in flat_docs:
            if doc.page_content not in seen:
                seen.add(doc.page_content)
                dedup_docs.append(doc)

        # Optionally limit to top_k_chunks
        selected_docs = dedup_docs[:top_k_chunks]

        # Step 1: Summarize each chunk individually to reduce noise
        chunk_summaries = []
        for doc in selected_docs:
            summary_prompt = f"""
            Summarize the following text in 1–2 sentences, keeping only the key factual information:
            {doc.page_content}
            """
            summary = self.chat_model.invoke(summary_prompt)
            chunk_summaries.append(summary.strip())

        # Step 2: Combine summaries as context
        context_text = "\n\n".join(chunk_summaries)

        # Step 3: Tiered answer prompt
        base_prompt = RosePrompts.get_prompt("rose_answer")
        if not base_prompt:
            raise ValueError("Prompt 'rose_answer' not found in RosePrompts")

        # Modify prompt to include tiered instructions
        final_prompt = (
            base_prompt + "\n\nAdditional Instructions:\n"
            "- First give a 1–2 sentence summary answer.\n"
            "- Then, if relevant, provide a more detailed explanation under 'Further Explanation:'.\n"
            "- Condense overlapping info and avoid repeating facts.\n"
            "- Only use the provided context; do not hallucinate."
        )

        final_prompt = final_prompt.format(question=user_query, context=context_text)

        # Step 4: Invoke LLM
        response = self.chat_model.invoke(final_prompt)
        return response
