from pathlib import Path

from fastapi import HTTPException
from langchain_chroma import Chroma
from langchain_core.documents import Document
from langchain_ollama import OllamaEmbeddings

from cerebrum_core.model_inator import ArchivedNote, ArchivedNoteContent, NoteStorage
from cerebrum_core.user_inator import ConfigManager
from cerebrum_core.utils.file_manager_inator import CerebrumPaths


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
    def __init__(
        self,
        note: NoteStorage,
        # WARN: chroma needs str
        note_archives: str,
    ) -> None:
        self.note = note
        self.note_archives = note_archives

    def _get_archives(self) -> Chroma:
        """Helper: Get Chroma archive instance from disk"""
        embedding_model = ConfigManager().load_config().models.embedding_model
        assert embedding_model is not None
        assert self.note is not None

        # embedd notes
        return Chroma(
            collection_name=self.note.note_id,
            embedding_function=OllamaEmbeddings(model=embedding_model),
            create_collection_if_not_exists=True,
            persist_directory=str(self.note_archives),
            collection_metadata={
                "note_id": self.note.note_id,
            },
        )

    def archive_init_inator(self) -> None:
        """
        Stores snapshots of notes in a historic database
        """
        self._get_archives()

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

        self._get_archives().add_documents([note])

    def archive_cleaner_inator(self) -> None:
        """
        DANGER: Deletes entire collection(note)
        """
        try:
            self._get_archives().delete_collection()
            print(f"Deleted collection: {self.note.note_id}")

        except Exception as e:
            print(f"Collection not found or error: {self.note.note_id} - {e}")

    def archive_browser_inator(self, bubble_id):
        note_file = CerebrumPaths().get_notes_dir(bubble_id) / self.note.title

        if not Path(self.note_archives).exists():
            raise HTTPException(404, f"No archive found for bubble:{bubble_id}")

        if not note_file.exists():
            raise HTTPException(
                404, f"No note:{self.note.title} found for bubble:{bubble_id}"
            )

        raw_data = self._get_archives().get()

        versions = []
        for doc_content, metadata in zip(raw_data["documents"], raw_data["metadatas"]):
            version = metadata.get("version", 0.0)
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
