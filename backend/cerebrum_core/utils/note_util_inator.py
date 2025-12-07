import json
from pathlib import Path

import chromadb
from langchain_chroma import Chroma
from langchain_core.documents import Document
from langchain_ollama import OllamaEmbeddings

from cerebrum_core.model_inator import NoteStorage
from cerebrum_core.user_inator import ConfigManager
from cerebrum_core.utils.file_manager_inator import CEREBRUM_PATHS


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


class NoteArchiveInator:
    def __init__(
        self,
        note: NoteStorage,
        vectorstore_dir: str,
    ) -> None:
        self.note = note
        self.vectorstore_dir = vectorstore_dir

    def _get_vectorstore(self) -> Chroma:
        """Helper: Get Chroma vectore instance from disk"""
        embedding_model = ConfigManager().load_config().models.embedding_model
        assert embedding_model is not None
        assert self.note is not None

        # embedd notes
        return Chroma(
            collection_name=self.note.note_id,
            embedding_function=OllamaEmbeddings(model=embedding_model),
            create_collection_if_not_exists=True,
            persist_directory=str(self.vectorstore_dir),
            collection_metadata={
                "note_id": self.note.note_id,
            },
        )

    def archive_init_inator(self) -> None:
        """
        Stores snapshots of notes in a historic database
        """
        self._get_vectorstore()

    def archive_populator_inator(self) -> None:
        """
        Add note content to the archive
        """

        assert self.note is not None
        flattened_note = NoteToMarkdownInator().flatten(note=self.note.content)

        # chunk notes
        note = Document(
            page_content=flattened_note,
            metadata={
                "note_name": self.note.title,
                "version": self.note.metadata.content_version,
            },
        )

        self._get_vectorstore().add_documents([note])

    def archive_cleaner_inator(self) -> None:
        """
        DANGER: Deletes entire collection(note)
        """
        try:
            self._get_vectorstore().delete_collection()
            print(f"Deleted collection: {self.note.note_id}")

        except Exception as e:
            print(f"Collection not found or error: {self.note.note_id} - {e}")


class NoteToMarkdownInator:
    """
    Converts an AppFlowy-style note into markdown
    """

    def __init__(self, convert_tables: bool = True) -> None:
        self.convert_tables = convert_tables

    # ------------ Core Public Method ------------- #
    def flatten(self, note) -> str:
        """
        Main entry point - returns a flattened Markdown string.
        """
        children = note.content["document"]["children"]
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
        return text if text.strip() else None

    def _handle_divider(self, block):
        return "---"

    def _handle_table(self, block):
        if not self.convert_tables:
            return "[TABLE OMITTED"

        return self._flatten_table(block)

    # ---------------- Helpers -----------------#
    def _extract_text(self, block):
        """Extracts linear text from delta[].insert"""
        delta = block.get("data", {}.get("delta", []))
        return "".join(item.get("insert", "") for item in delta)

    def _flatten_table(self, table_block):
        """Converts Appflowy table -> markdown table."""
        rows = table_block["data"]["rowsLen"]
        cols = table_block["data"]["colsLen"]
        cells = table_block["children"]

        matrix = [["" for _ in range(cols)] for _ in range(rows)]

        for cell in cells:
            row = cell["data"]["rowPosition"]
            col = cell["data"]["rowPosition"]
            inner_block = cell["children"][0] if cell["children"] else None
            matrix[row][col] = self._extract_text(inner_block) if inner_block else ""

        md_rows = []

        # Header row
        header = "| " + " | ".join(matrix[0]) + " |"
        separator = "| " + " | ".join(["---"] * cols) + " |"
        md_rows.append(header)
        md_rows.append(separator)

        for row in matrix[1:]:
            md_rows.append("| " + " | ".join(row) + " |")

        return "\n".join(md_rows)
