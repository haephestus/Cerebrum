import hashlib
import json
import sqlite3
from typing import Any, Optional

from langchain_chroma import Chroma

from cerebrum_core.utils.file_manager_inator import CerebrumPaths


class CacheInator:
    def __init__(self, vectorstore: Chroma):
        """
        vectorstore: Chroma instance where each cached analysis is stored
        Metadata fields:
            - note_id
            - semantic_version
            - operation
            - prompt_hash
        Embedding used for semantic similarity
        """
        self.vs = vectorstore

    @staticmethod
    def _hash(text: str) -> str:
        return hashlib.sha256(text.encode("utf-8")).hexdigest()

    def get_deterministic(
        self, note_id: str, semantic_version: float, operation: str, prompt: str
    ) -> Optional[Any]:
        prompt_hash = self._hash(prompt)
        # exact metadata filter
        result = self.vs.similarity_search(
            query="",  # query is irrelevant for exact filter
            filter={
                "note_id": note_id,
                "semantic_version": semantic_version,
                "operation": operation,
                "prompt_hash": prompt_hash,
            },
            k=1,
        )
        if result:
            return json.loads(result[0].metadata["response"])
        return None

    def get_semantic(self, embedding, k=3):
        # approximate search
        result = self.vs.similarity_search_by_vector(vector=embedding, k=k)
        return [json.loads(r.metadata["response"]) for r in result]

    def set(
        self,
        note_id: str,
        semantic_version: float,
        operation: str,
        prompt: str,
        embedding,
        response: Any,
    ):
        prompt_hash = self._hash(prompt)
        metadata = {
            "note_id": note_id,
            "semantic_version": semantic_version,
            "operation": operation,
            "prompt_hash": prompt_hash,
            "response": json.dumps(response),
        }
        self.vs.add_texts(texts=[prompt], embedding=embedding, metadatas=[metadata])


class SQLiteBackupCache:
    def __init__(self, in_memory: bool = False):
        self.cache_path = CerebrumPaths().get_cache_dir()
        self.conn = sqlite3.connect(":memory:" if in_memory else self.cache_path)
        self._init_tables()

    def _init_tables(self):
        self.conn.execute(
            """
        CREATE TABLE IF NOT EXISTS analysis_backup (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            note_id TEXT NOT NULL,
            semantic_version REAL NOT NULL,
            operation TEXT NOT NULL,
            prompt_hash TEXT NOT NULL,
            response TEXT NOT NULL,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            UNIQUE(note_id, semantic_version, operation, prompt_hash)
        )
        """
        )
        self.conn.commit()

    @staticmethod
    def _hash(text: str) -> str:
        return hashlib.sha256(text.encode("utf-8")).hexdigest()

    def get(
        self, *, note_id: str, semantic_version: float, operation: str, prompt: str
    ) -> Optional[Any]:
        prompt_hash = self._hash(prompt)
        row = self.conn.execute(
            """
            SELECT response FROM analysis_backup
            WHERE note_id=? AND semantic_version=? AND operation=? AND prompt_hash=?
            """,
            (note_id, semantic_version, operation, prompt_hash),
        ).fetchone()
        return json.loads(row[0]) if row else None

    def set(
        self,
        *,
        note_id: str,
        semantic_version: float,
        operation: str,
        prompt: str,
        response: Any
    ):
        prompt_hash = self._hash(prompt)
        self.conn.execute(
            """
            INSERT OR IGNORE INTO analysis_backup
            (note_id, semantic_version, operation, prompt_hash, response)
            VALUES (?, ?, ?, ?, ?)
            """,
            (note_id, semantic_version, operation, prompt_hash, json.dumps(response)),
        )
        self.conn.commit()
