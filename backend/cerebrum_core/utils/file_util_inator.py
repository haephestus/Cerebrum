import hashlib
import re
import sqlite3
from dataclasses import dataclass
from pathlib import Path
from typing import List, Optional

from platformdirs import PlatformDirs

"""
file_util_inator.py

Purpose: 
    Exposes file paths, and handles all file related manipulations
    regarding what is available in the knowledgebase.
"""


# init dirs for server
class CerebrumPaths:
    """
    Exposes necesary file paths and makes it easier to define
    config level control concerning default file locations.
    """

    def __init__(self, app_name: str = "cerebrum"):
        dirs = PlatformDirs(app_name)
        self.DATA_ROOT = Path(dirs.user_data_dir)
        self.CONFIG_ROOT = Path(dirs.user_config_dir)
        self.CACHE_ROOT = Path(dirs.user_cache_dir)

        # Cerebrum paths
        self.KB_ROOT = self.DATA_ROOT / "knowledgebase"
        self.BUBBLES_ROOT = self.DATA_ROOT / "study_bubbles"
        self.LOGS_ROOT = self.DATA_ROOT / "logs"

    def init_cerebrum_dirs(self):
        """Ensure all top-level directories exist"""
        for d in [
            self.DATA_ROOT,
            self.KB_ROOT,
            self.BUBBLES_ROOT,
            self.LOGS_ROOT,
        ]:
            d.mkdir(exist_ok=True)

    # ------------- HANDLE BUBBLES PATHS ---------------------------
    def init_bubble_dirs(self, bubble_id):
        """
        Handles creation of bubble specific folders when a new study bubble
        is created
        """
        bubble_dir = self.get_bubble_path(bubble_id) / bubble_id

        # Create sub-dirs
        chat_dir = bubble_dir / "chat"
        notes_dir = bubble_dir / "notes"
        assesments_dir = bubble_dir / "assesments"

        for d in [chat_dir, notes_dir, assesments_dir]:
            d.mkdir(parents=True, exist_ok=True)
            (d / ".archives").mkdir(parents=True, exist_ok=True)

    def get_bubbles_root(self) -> Path:
        """Return bubbles root directory"""
        return self.BUBBLES_ROOT

    def get_bubble_path(self, bubble_id):
        """Return the path of a single bubble"""
        BUBBLE_PATH = self.BUBBLES_ROOT / bubble_id
        return BUBBLE_PATH

    def get_notes_root(self, bubble_id):
        """Return notes root directory"""
        return self.get_bubble_path(bubble_id) / "notes"

    def get_note_path(self, bubble_id: str, filename: str):
        """Return path to a sinlge note"""
        return self.get_bubble_path(bubble_id) / "notes" / filename

    def get_note_archives(self, bubble_id):
        """Return bubble specific note archives directory"""
        return self.get_bubble_path(bubble_id) / "notes" / ".archives"

    def get_chats_dir(self, bubble_id):
        """Return  bubble specific chats directory"""
        return self.get_bubble_path(bubble_id) / "chat"

    def get_chats_archives(self, bubble_id):
        """Return  bubble specific chat archives directory"""
        return self.get_bubble_path(bubble_id) / "chat" / ".archives"

    def get_assesment_dir(self, bubble_id):
        """Returns bubble specific assesment directory"""
        return self.get_bubble_path(bubble_id) / "assesments"

    def get_assesment_archives(self, bubble_id):
        """Returns bubble specific assesment archives directory"""
        return self.get_bubble_path(bubble_id) / "assesments" / ".archives"

    # ------------- HANDLE KNOWLEDGEBASE PATHS ---------------------------
    def get_kb_root(self) -> Path:
        KB_DIR = self.DATA_ROOT / "knowledgebase"
        return KB_DIR

    def get_kb_source_files(self) -> Path:
        return self.get_kb_root() / "source_files"

    def get_kb_artifacts(self) -> Path:
        return self.get_kb_root() / "markdown_artifacts"

    def get_kb_archives(self):
        return self.get_kb_root() / "archives"

    def get_logs_dir(self) -> Path:
        LOGS_DIR = self.DATA_ROOT / "logs"
        return LOGS_DIR

    def get_config_dir(self) -> Path:
        return self.CONFIG_ROOT

    def get_cache_root(self) -> Path:
        return self.CACHE_ROOT

    def get_cache_dir(self, bubble_id) -> Path:
        CACHE_DIR = self.CACHE_ROOT / "analysis_cache" / bubble_id
        return CACHE_DIR


# init so functions in this file can use it
CEREBRUM_PATHS = CerebrumPaths()


def file_walker_inator(root: Path, max_depth: int = 4):
    """
    walks the  knowledgebase root directory, in order to give context
    of the available domains to the llm, so it can determinstically
    classify documents
    """

    def recurse_inator(path: Path, parts: list[str]):
        for file in path.glob("*"):
            if file.is_file():
                yield {
                    "domain": parts[0] if len(parts) > 0 else None,
                    "subject": parts[1] if len(parts) > 1 else None,
                    "topic": parts[2] if len(parts) > 2 else None,
                    "subtopic": parts[3] if len(parts) > 3 else None,
                    "filepath": file,
                    "filename": file.name,
                    "filestem": file.stem,
                    "file-ext": file.suffix,
                }
            elif file.is_dir() and len(parts) < max_depth:
                yield from recurse_inator(file, parts + [file.name])

    yield from recurse_inator(root, [])


UUID_PATTERN = re.compile(
    r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
)


def knowledgebase_index_inator(root: Path):
    domains, subjects, topics, subtopics = set(), set(), set(), set()
    available_files = []

    for info in file_walker_inator(root):
        # skip if any part is a UUID
        skip = False
        for part in [info["domain"], info["subject"], info["topic"], info["subtopic"]]:
            if part and UUID_PATTERN.fullmatch(part):
                skip = True
                break
        if skip:
            continue

        available_files.append(info["filestem"])
        if info["domain"]:
            domains.add(info["domain"])
        if info["subject"]:
            subjects.add(info["subject"])
        if info["topic"]:
            topics.add(info["topic"])
        if info["subtopic"]:
            subtopics.add(info["subtopic"])

    return {
        "domains": sorted(domains),
        "subjects": sorted(subjects),
        "topics": sorted(topics),
        "subtopics": sorted(subtopics),
    }, available_files


class FileRegisterInator:
    """
    Registers available files, and is the source of truth for which files
    are to be processed and added to domain specific archives in the knowledgebase
    """

    def __init__(self, db_path: str = "registry/file_registry.db"):
        self.DB_PATH = CEREBRUM_PATHS.get_kb_root() / db_path
        self.DB_PATH.parent.mkdir(parents=True, exist_ok=True)

        # self init functions
        self._table_iniatior_inator()

    def _table_iniatior_inator(self):
        conn = sqlite3.connect(self.DB_PATH)
        cursor = conn.cursor()

        # table if none exists
        cursor.execute(
            """
        CREATE TABLE IF NOT EXISTS registry (
            id INTEGER PRIMARY KEY,
            original_name TEXT UNIQUE,
            sanitized_name TEXT,
            domain TEXT,
            subject TEXT,
            fingerprint TEXT UNIQUE,
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
            "CREATE UNIQUE INDEX IF NOT EXISTS idx_registry_hash ON registry(fingerprint)"
        )

        conn.commit()
        conn.close()

    def register_inator(self, original_name: str, filepath: str):
        fingerprint = self._fingerprint_inator(original_name)
        conn = sqlite3.connect(self.DB_PATH)
        cursor = conn.cursor()

        cursor.execute(
            """
        INSERT INTO registry (original_name, fingerprint, filepath)
        VALUES (?,?,?)
        ON CONFLICT(fingerprint) DO UPDATE SET
            last_updated = CURRENT_TIMESTAMP
        """,
            (original_name, fingerprint, filepath),
        )

        conn.commit()
        conn.close()

    def mark_converted_inator(
        self,
        fingerprint: str,
        domain: str | None,
        subject: str | None,
        sanitized_name: str | None,
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
            WHERE fingerprint = ?
            """,
            (domain, subject, sanitized_name, fingerprint),
        )

        conn.commit()
        conn.close()

    def mark_embedded_inator(
        self,
        fingerprint: str,
    ):

        conn = sqlite3.connect(self.DB_PATH)
        cursor = conn.cursor()

        cursor.execute(
            """
            UPDATE registry
            SET 
                embedded = 1,
                last_updated = CURRENT_TIMESTAMP
            WHERE fingerprint = ?
            """,
            (fingerprint,),
        )

        conn.commit()
        conn.close()

    def fetch_unconverted_file_inator(self):
        """Fetch all files not converted to markdown"""
        conn = sqlite3.connect(self.DB_PATH)
        cursor = conn.cursor()
        cursor.execute(
            """
        SELECT
            original_name,
            fingerprint,
            filepath
        FROM registry
        WHERE converted = 0
        """
        )
        rows = cursor.fetchall()
        conn.close()

        columns = ["original_name", "fingerprint", "filepath"]
        data = [dict(zip(columns, row)) for row in rows]
        return data

    def fetch_unembedded_file_inator(self):
        """Fetch all files that are converted but not embedded"""
        conn = sqlite3.connect(self.DB_PATH)
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT
                original_name,
                sanitized_name,
                domain,
                subject,
                fingerprint,
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
            "fingerprint",
            "filepath",
        ]
        data = [dict(zip(columns, row)) for row in rows]
        return data

    def check_inator(self, fingerprint: str, field: str = "") -> bool:
        """
        Check if a file exists or if a flag is set.
        """

        conn = sqlite3.connect(self.DB_PATH)
        cursor = conn.cursor()

        if field:
            cursor.execute(
                f"SELECT {field} FROM registry WHERE fingerprint = ?", (fingerprint,)
            )
        else:
            cursor.execute(
                "SELECT 1 FROM registry WHERE fingerprint = ?", (fingerprint,)
            )

        result = cursor.fetchone()
        conn.close()
        return bool(result and (result[0] if field else True))

    def show_all_inator(self):
        """Print all rows in the registry table for debugging"""
        conn = sqlite3.connect(self.DB_PATH)
        cursor = conn.cursor()
        cursor.execute("SELECT * FROM registry")
        rows = cursor.fetchall()
        conn.close()

        columns = [
            "ids",
            "original_name",
            "sanitized_name",
            "domain",
            "subject",
            "fingerprint",
            "converted",
            "embedded",
            "filepath",
        ]
        data = [dict(zip(columns, row)) for row in rows]
        return data

    def remove_inator(self, filename: str, fingerprint: str, filepath: str):
        """Removes file from registry and disk"""

        conn = sqlite3.connect(self.DB_PATH)
        cursor = conn.cursor()
        try:
            cursor.execute(
                """
                DELETE FROM registry 
                WHERE original_name = ? 
                AND fingerprint = ?
                """,
                (filename, fingerprint),
            )
            if cursor.rowcount == 0:
                conn.close()
                raise FileNotFoundError("Registry entry not found")
            conn.commit()
        except Exception:
            conn.rollback()
            raise
        finally:
            conn.close()

        if Path(filepath).exists():
            Path(filepath).unlink()

    def reset_inator(self, status, fingerprint=None):
        VALID_COLUMNS = {"embedded", "converted"}

        if status not in VALID_COLUMNS:
            raise ValueError("Invalid status field")

        conn = sqlite3.connect(self.DB_PATH)
        cursor = conn.cursor()
        try:
            if fingerprint:
                cursor.execute(
                    f"""
                UPDATE registry
                SET {status} = 0
                WHERE fingerprint = ?
                """,
                    (fingerprint),
                )
            else:
                cursor.execute(f"UPDATE registry SET {status} = 0")
            conn.commit()
            count = cursor.rowcount
            return count

        finally:
            conn.close()

    def _fingerprint_inator(self, original_name: str):
        """Generate a determinstic fingerprint from filename"""
        return hashlib.sha256(original_name.encode("utf-8")).hexdigest()


@dataclass
class ChunkRecordInator:
    fingerprint: str
    chunk_index: str
    byte_start: int
    byte_end: int
    token_count: int
    chunk_type: str
    parent_chunk_index: Optional[str]
    embedded: int = 0


class ChunkRegisterInator:
    def __init__(self, db_path: str = "registry/chunk_registry.db"):
        self.db_path = CEREBRUM_PATHS.get_kb_root() / db_path
        self._init_table()

    # --------------------------------------------------
    # Table init
    # --------------------------------------------------
    def _init_table(self):
        conn = sqlite3.connect(self.db_path)
        cur = conn.cursor()
        cur.execute(
            """
            CREATE TABLE IF NOT EXISTS chunks (
                id INTEGER PRIMARY KEY,
                chunk_fingerprint TEXT NOT NULL,
                chunk_index INTEGER NOT NULL,
                byte_start INTEGER NOT NULL,
                byte_end INTEGER NOT NULL,
                token_count INTEGER,
                chunk_type TEXT NOT NULL,
                parent_chunk_index INTEGER,
                embedded INTEGER DEFAULT 0,
                UNIQUE (chunk_fingerprint, chunk_index)
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
            INSERT OR REPLACE INTO chunks (
                chunk_fingerprint,
                chunk_index,
                byte_start,
                byte_end,
                token_count,
                chunk_type,
                parent_chunk_index
            ) VALUES (?,?,?,?,?,?,?)
            """,
            chunk_rows,
        )
        conn.commit()
        conn.close()

    # --------------------------------------------------
    # Embedding progress (FIXED)
    # --------------------------------------------------
    def get_embedding_progress(self, chunk_fingerprint: str) -> dict:
        """
        Returns embedding progress with guaranteed int types.
        Never returns tuples or NULLs.
        """
        conn = sqlite3.connect(self.db_path)
        cur = conn.cursor()

        cur.execute(
            """
            SELECT 
                COUNT(*) AS total,
                COALESCE(SUM(embedded), 0) AS completed,
                COUNT(*) - COALESCE(SUM(embedded), 0) AS remaining
            FROM chunks
            WHERE chunk_fingerprint = ?
            """,
            (chunk_fingerprint,),
        )

        row = cur.fetchone()
        conn.close()

        if not row:
            return {
                "total": 0,
                "completed": 0,
                "remaining": 0,
                "progress_pct": 0,
            }

        total, completed, remaining = map(int, row)

        progress_pct = (completed / total) * 100 if total > 0 else 0

        return {
            "total": total,
            "completed": completed,
            "remaining": remaining,
            "progress_pct": progress_pct,
        }

    # --------------------------------------------------
    # Mark chunk embedded
    # --------------------------------------------------
    def mark_embedded(self, chunk_fingerprint: str, chunk_index: int):
        conn = sqlite3.connect(self.db_path)
        cur = conn.cursor()
        cur.execute(
            """
            UPDATE chunks
            SET embedded = 1
            WHERE chunk_fingerprint = ? AND chunk_index = ?
            """,
            (chunk_fingerprint, chunk_index),
        )
        conn.commit()
        conn.close()

    # --------------------------------------------------
    # Fetch unembedded chunks (ORDER SAFE)
    # --------------------------------------------------
    def get_unembedded_chunks(self, chunk_fingerprint: str):
        conn = sqlite3.connect(self.db_path)
        cur = conn.cursor()
        cur.execute(
            """
            SELECT
                chunk_fingerprint,
                chunk_index,
                byte_start,
                byte_end,
                token_count,
                chunk_type,
                parent_chunk_index,
                embedded
            FROM chunks
            WHERE chunk_fingerprint = ?
              AND embedded = 0
            ORDER BY chunk_index ASC
            """,
            (chunk_fingerprint,),
        )

        rows = cur.fetchall()
        conn.close()
        return [ChunkRecordInator(*row) for row in rows]
