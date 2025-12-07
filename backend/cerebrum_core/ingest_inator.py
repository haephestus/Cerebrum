import json
from pathlib import Path

import pymupdf4llm
import yaml
from langchain_chroma import Chroma
from langchain_core.documents import Document
from langchain_ollama import OllamaEmbeddings, OllamaLLM
from langchain_text_splitters import MarkdownHeaderTextSplitter

from agents.rose import RosePrompts
from cerebrum_core.model_inator import FileMetadata
from cerebrum_core.utils.file_manager_inator import CerebrumPaths


class IngestInator:
    """
    ingestinator is  supposed to take files from the storage dir
        1. chunk them up
        2. index information
        3. embed information
    """

    def __init__(
        self, filepath: Path, embedding_model=None, vectorstores_path=None
    ) -> None:
        self.vectorstores_path = vectorstores_path
        self.filepath = filepath
        self.embedding_model = embedding_model
        self.chunks: list[Document] = []
        self.metatdata = {}

    def _yaml_inator(self, metadata: FileMetadata) -> str:
        yaml_dump = yaml.dump(metadata.model_dump(), sort_keys=False)
        return f"---\n{yaml_dump}---\n\n"

    def sanitize_inator(self, filename: str, metadata: dict | None, llm_model: str):
        """
        renames files to chromadb ready strings
        while also preserving or updating metadata
        offloading renaming and sanitization to llm
        """
        metadata_json = json.dumps(metadata, indent=2) if metadata else "{}"
        model = OllamaLLM(model=llm_model)
        santize_prompt = RosePrompts.get_prompt("rose_rename")
        if not santize_prompt:
            raise ValueError("Prompt 'rose_rename' not fount in RosePrompts")
        filled_prompt = santize_prompt.format(filename=filename, metadata=metadata_json)
        sanitized_prompt = model.invoke(filled_prompt)

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
        store chunks in vectorstores
        """
        assert self.embedding_model is not None, "embedding_model is required"
        assert self.vectorstores_path is not None, "vectorstores_path is required"

        # embedding
        # WARN: look into making this framework agnostic
        # (split it into a seperate embedding funcion)
        embedding_llm = OllamaEmbeddings(model=self.embedding_model)
        chromadb = Chroma(
            collection_name=collection_name,
            persist_directory=str(self.vectorstores_path),
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
