import json
import logging
import os
from pathlib import Path

import pymupdf4llm
import yaml
from langchain_chroma import Chroma
from langchain_core.documents import Document
from langchain_ollama import OllamaEmbeddings, OllamaLLM
from langchain_text_splitters import MarkdownHeaderTextSplitter

from agents.rose import RosePrompts
from cerebrum_core.model_inator import FileMetadata, TranslatedQuery
from cerebrum_core.user_inator import DEFAULT_CHAT_MODEL, ConfigManager
from cerebrum_core.utils.file_util_inator import (
    CerebrumPaths,
    knowledgebase_index_inator,
)


class IngestInator:
    """
    ingestinator is  supposed to take files from the storage dir
        1. chunk them up
        2. index information
        3. embed information
    """

    def __init__(self, filepath: Path, archives_path=None) -> None:
        self.archives_path = archives_path
        self.filepath = filepath
        self.embedding_model = ConfigManager().load_config().models.embedding_model
        self.chunks: list[Document] = []
        self.metatdata = {}

    def _yaml_inator(self, metadata: FileMetadata) -> str:
        yaml_dump = yaml.dump(metadata.model_dump(), sort_keys=False)
        return f"---\n{yaml_dump}---\n\n"

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
        markdown_dir = path.get_kb_dir() / "markdown" / domain / subject
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
        # TODO: work on chunking,
        # dynamic chunking -> auto adjust to embedding models context window
        # or manual chunking ->  4k tokens (find a normalized and fair tokenizer)
        md_text = markdown_filepath.read_text()

        header_levels = [
            ("#", "Header 1"),
            ("##", "Header 2"),
            ("###", "Header 3"),
            ("####", "Header 4"),
            ("#####", "Header 5"),
            ("######", "Header 6"),
        ]

        splitter = MarkdownHeaderTextSplitter(
            headers_to_split_on=header_levels, strip_headers=False
        )

        self.chunks = splitter.split_text(md_text)
        return self.chunks

    def embedd_inator(self, chunk, collection_name) -> None:
        """
        store chunks in archives
        """
        # TODO: find a better alternative than assert
        assert self.embedding_model is not None, "embedding_model is required"
        assert self.archives_path is not None, "archives_path is required"

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

        # TODO: add legible chunk ids for each documents
        # probably in a style that matches filemeta data
        chromadb.add_documents([chunk])

    # WARN: for later if chroma stores are too big
    def index_inator(self):
        pass

    def token_inator(self):
        pass


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
archives_path = CerebrumPaths()


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
