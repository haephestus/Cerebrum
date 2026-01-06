import hashlib
import sqlite3
from dataclasses import dataclass
from pathlib import Path
from typing import List, Optional

from cerebrum_core.utils.file_util_inator import CerebrumPaths


# ==========================================================
# File Registry
# ==========================================================
class FileRegisterInator:
    """
    Registers available files, and is the source of truth for which files
    are to be processed and added to domain-specific archives in the knowledgebase
    """

    def __init__(self, db_path: str = "registry/file_registry.db"):
        self.DB_PATH = CerebrumPaths().kb_root_dir() / db_path
        self.DB_PATH.parent.mkdir(parents=True, exist_ok=True)
        self._table_initiator_inator()

    def _table_initiator_inator(self):
        conn = sqlite3.connect(self.DB_PATH)
        cursor = conn.cursor()

        cursor.execute(
            """
            CREATE TABLE IF NOT EXISTS registry (
                id INTEGER PRIMARY KEY,
                original_name TEXT UNIQUE,
                sanitized_name TEXT,
                domain TEXT,
                subject TEXT,
                file_fingerprint TEXT UNIQUE,
                converted INTEGER DEFAULT 0,
                embedded INTEGER DEFAULT 0,
                filepath TEXT,
                last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
            """
        )

        cursor.execute(
            "CREATE UNIQUE INDEX IF NOT EXISTS idx_registry_original_name ON registry(original_name)"
        )
        cursor.execute(
            "CREATE UNIQUE INDEX IF NOT EXISTS idx_registry_fingerprint ON registry(file_fingerprint)"
        )

        conn.commit()
        conn.close()

    # --------------------------------------------------
    # Register file
    # --------------------------------------------------
    def register_inator(self, original_name: str, filepath: str):
        file_fingerprint = self._file_fingerprint_inator(original_name)

        conn = sqlite3.connect(self.DB_PATH)
        cursor = conn.cursor()

        cursor.execute(
            """
            INSERT INTO registry (original_name, file_fingerprint, filepath)
            VALUES (?, ?, ?)
            ON CONFLICT(file_fingerprint) DO UPDATE SET
                last_updated = CURRENT_TIMESTAMP
            """,
            (original_name, file_fingerprint, filepath),
        )

        conn.commit()
        conn.close()

    # --------------------------------------------------
    # Status updates
    # --------------------------------------------------
    def mark_converted_inator(
        self,
        file_fingerprint: str,
        domain: Optional[str],
        subject: Optional[str],
        sanitized_name: Optional[str],
    ):
        conn = sqlite3.connect(self.DB_PATH)
        cursor = conn.cursor()

        cursor.execute(
            """
            UPDATE registry
            SET
                converted = 1,
                domain = COALESCE(?, domain),
                subject = COALESCE(?, subject),
                sanitized_name = COALESCE(?, sanitized_name),
                last_updated = CURRENT_TIMESTAMP
            WHERE file_fingerprint = ?
            """,
            (domain, subject, sanitized_name, file_fingerprint),
        )

        conn.commit()
        conn.close()

    def mark_embedded_inator(self, file_fingerprint: str):
        conn = sqlite3.connect(self.DB_PATH)
        cursor = conn.cursor()

        cursor.execute(
            """
            UPDATE registry
            SET embedded = 1,
                last_updated = CURRENT_TIMESTAMP
            WHERE file_fingerprint = ?
            """,
            (file_fingerprint,),
        )

        conn.commit()
        conn.close()

    # --------------------------------------------------
    # Fetchers
    # --------------------------------------------------
    def fetch_unconverted_file_inator(self):
        conn = sqlite3.connect(self.DB_PATH)
        cursor = conn.cursor()

        cursor.execute(
            """
            SELECT original_name, file_fingerprint, filepath
            FROM registry
            WHERE converted = 0
            """
        )

        rows = cursor.fetchall()
        conn.close()

        columns = ["original_name", "file_fingerprint", "filepath"]
        return [dict(zip(columns, row)) for row in rows]

    def fetch_unembedded_file_inator(self):
        conn = sqlite3.connect(self.DB_PATH)
        cursor = conn.cursor()

        cursor.execute(
            """
            SELECT
                original_name,
                sanitized_name,
                domain,
                subject,
                file_fingerprint,
                filepath
            FROM registry
            WHERE converted = 1 AND embedded = 0
            """
        )

        rows = cursor.fetchall()
        conn.close()

        columns = [
            "original_name",
            "sanitized_name",
            "domain",
            "subject",
            "file_fingerprint",
            "filepath",
        ]
        return [dict(zip(columns, row)) for row in rows]

    # --------------------------------------------------
    # Utilities
    # --------------------------------------------------
    def check_inator(self, file_fingerprint: str, field: str = "") -> bool:
        VALID_FIELDS = {"embedded", "converted"}

        conn = sqlite3.connect(self.DB_PATH)
        cursor = conn.cursor()

        if field:
            if field not in VALID_FIELDS:
                raise ValueError("Invalid field requested")
            cursor.execute(
                f"SELECT {field} FROM registry WHERE file_fingerprint = ?",
                (file_fingerprint,),
            )
        else:
            cursor.execute(
                "SELECT 1 FROM registry WHERE file_fingerprint = ?",
                (file_fingerprint,),
            )

        result = cursor.fetchone()
        conn.close()

        return bool(result and (result[0] if field else True))

    def show_all_inator(self):
        conn = sqlite3.connect(self.DB_PATH)
        cursor = conn.cursor()

        cursor.execute("SELECT * FROM registry")
        rows = cursor.fetchall()
        conn.close()

        columns = [
            "id",
            "original_name",
            "sanitized_name",
            "domain",
            "subject",
            "file_fingerprint",
            "converted",
            "embedded",
            "filepath",
            "last_updated",
        ]

        return [dict(zip(columns, row)) for row in rows]

    # --------------------------------------------------
    # Delete / Reset
    # --------------------------------------------------
    def remove_inator(self, filename: str, file_fingerprint: str, filepath: str):
        conn = sqlite3.connect(self.DB_PATH)
        cursor = conn.cursor()

        try:
            cursor.execute(
                """
                DELETE FROM registry
                WHERE original_name = ?
                  AND file_fingerprint = ?
                """,
                (filename, file_fingerprint),
            )

            if cursor.rowcount == 0:
                raise FileNotFoundError("Registry entry not found")

            conn.commit()
        except Exception:
            conn.rollback()
            raise
        finally:
            conn.close()

        path = Path(filepath)
        if path.exists():
            path.unlink()

    def reset_inator(self, status: str, file_fingerprint: Optional[str] = None):
        VALID_COLUMNS = {"embedded", "converted"}
        if status not in VALID_COLUMNS:
            raise ValueError("Invalid status field")

        conn = sqlite3.connect(self.DB_PATH)
        cursor = conn.cursor()

        if file_fingerprint:
            cursor.execute(
                f"""
                UPDATE registry
                SET {status} = 0
                WHERE file_fingerprint = ?
                """,
                (file_fingerprint,),
            )
        else:
            cursor.execute(f"UPDATE registry SET {status} = 0")

        conn.commit()
        count = cursor.rowcount
        conn.close()
        return count

    def _file_fingerprint_inator(self, original_name: str) -> str:
        """Deterministic fingerprint based on filename"""
        return hashlib.sha256(original_name.encode("utf-8")).hexdigest()


# ==========================================================
# Chunk Registry
# ==========================================================
@dataclass
class ChunkRecordInator:
    file_fingerprint: str
    chunk_fingerprint: str
    chunk_index: int
    byte_start: int
    byte_end: int
    token_count: int
    chunk_type: str
    parent_chunk_index: Optional[int]
    embedded: int


class ChunkRegisterInator:
    def __init__(self, db_path: str = "registry/chunk_registry.db"):
        self.db_path = CerebrumPaths().kb_root_dir() / db_path
        self._init_table()

    def _init_table(self):
        conn = sqlite3.connect(self.db_path)
        cur = conn.cursor()

        cur.execute(
            """
            CREATE TABLE IF NOT EXISTS chunks (
                id INTEGER PRIMARY KEY,
                file_fingerprint TEXT NOT NULL,
                chunk_fingerprint TEXT NOT NULL,
                chunk_index INTEGER NOT NULL,
                byte_start INTEGER NOT NULL,
                byte_end INTEGER NOT NULL,
                token_count INTEGER,
                chunk_type TEXT NOT NULL,
                parent_chunk_index INTEGER,
                embedded INTEGER DEFAULT 0,
                UNIQUE (file_fingerprint, chunk_fingerprint, chunk_index)
            )
            """
        )

        conn.commit()
        conn.close()

    # --------------------------------------------------
    # Register chunks
    # --------------------------------------------------
    def register_chunks(self, chunk_rows: List[tuple]):
        conn = sqlite3.connect(self.db_path)
        cur = conn.cursor()

        cur.executemany(
            """
            INSERT INTO chunks (
                file_fingerprint,
                chunk_fingerprint,
                chunk_index,
                byte_start,
                byte_end,
                token_count,
                chunk_type,
                parent_chunk_index
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(file_fingerprint, chunk_fingerprint, chunk_index)
            DO UPDATE SET
                byte_start = excluded.byte_start,
                byte_end = excluded.byte_end,
                token_count = excluded.token_count,
                chunk_type = excluded.chunk_type,
                parent_chunk_index = excluded.parent_chunk_index
            """,
            chunk_rows,
        )

        conn.commit()
        conn.close()

    # --------------------------------------------------
    # Embedding progress
    # --------------------------------------------------
    def get_embedding_progress(self, file_fingerprint: str) -> dict:
        conn = sqlite3.connect(self.db_path)
        cur = conn.cursor()

        cur.execute(
            """
            SELECT
                COUNT(*),
                COALESCE(SUM(embedded), 0)
            FROM chunks
            WHERE file_fingerprint = ?
            """,
            (file_fingerprint,),
        )

        total, completed = map(int, cur.fetchone())
        conn.close()

        remaining = total - completed
        progress_pct = (completed / total) * 100 if total > 0 else 0

        return {
            "total": total,
            "completed": completed,
            "remaining": remaining,
            "progress_pct": progress_pct,
        }

    # --------------------------------------------------
    # Chunk updates
    # --------------------------------------------------
    def mark_embedded(self, file_fingerprint: str, chunk_fingerprint: str):
        conn = sqlite3.connect(self.db_path)
        cur = conn.cursor()

        cur.execute(
            """
            UPDATE chunks
            SET embedded = 1
            WHERE file_fingerprint = ?
              AND chunk_fingerprint = ?
            """,
            (file_fingerprint, chunk_fingerprint),
        )

        conn.commit()
        conn.close()

    # --------------------------------------------------
    # Fetch unembedded chunks
    # --------------------------------------------------
    def get_unembedded_chunks(self, file_fingerprint: str) -> List[ChunkRecordInator]:
        conn = sqlite3.connect(self.db_path)
        cur = conn.cursor()

        cur.execute(
            """
            SELECT
                file_fingerprint,
                chunk_fingerprint,
                chunk_index,
                byte_start,
                byte_end,
                token_count,
                chunk_type,
                parent_chunk_index,
                embedded
            FROM chunks
            WHERE file_fingerprint = ?
              AND embedded = 0
            ORDER BY chunk_index ASC
            """,
            (file_fingerprint,),
        )

        rows = cur.fetchall()
        conn.close()

        return [ChunkRecordInator(*row) for row in rows]

    def show_all_inator(self):
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()

        cursor.execute("SELECT * FROM chunks")
        rows = cursor.fetchall()
        conn.close()

        columns = [
            "id",
            "file_fingerprint",
            "chunk_fingerprint",
            "chunk_index",
            "byte_start",
            "byte_end",
            "token_count",
            "chunk_type",
            "parent_chunk_index",
            "embedded",
        ]

        return [dict(zip(columns, row)) for row in rows]
