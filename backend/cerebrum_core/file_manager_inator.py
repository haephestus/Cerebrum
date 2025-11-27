import re
import hashlib
import sqlite3
from pathlib import Path
from platformdirs import PlatformDirs


# init dirs for server
class CerebrumPaths:
    def __init__(self, app_name: str = "cerebrum"):
        dirs = PlatformDirs(app_name)
        self.DATA_DIR = Path(dirs.user_data_dir)
        self.CONFIG_FILE = Path(dirs.user_config_dir)

    def init_cerebrum_dirs(self):
        self.DATA_DIR.mkdir(parents=True, exist_ok=True)
        self.CONFIG_FILE.mkdir(parents=True, exist_ok=True)

        for sub in ["knowledgebase", "projects", "study_bubbles", "logs"]:
            (self.DATA_DIR / sub).mkdir(exist_ok=True)

    def get_kb_dir(self):
        KB_DIR = self.DATA_DIR / "knowledgebase"
        return KB_DIR

    def get_projects_dir(self):
        PROJECTS_DIR = self.DATA_DIR / "projects"
        return PROJECTS_DIR

    def get_bubbles_dir(self):
        BUBBLE_DIR = self.DATA_DIR / "study_bubbles"
        return BUBBLE_DIR

    def get_logs_dir(self):
        LOGS_DIR = self.DATA_DIR / "logs"
        return LOGS_DIR

    def get_config_dir(self):
        return self.CONFIG_FILE


# init so functions in this file can use it
path = CerebrumPaths()


def file_walker_inator(root: Path, max_depth: int = 4):
    """
    walk the through knowledgebase_dir, identify files at

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
    def __init__(self, db_path: str = "registry/registry.db"):
        self.DB_PATH = path.get_kb_dir() / db_path
        self.DB_PATH.parent.mkdir(parents=True, exist_ok=True)
        self._table_iniatior_inator()

    def _table_iniatior_inator(self):
        conn = sqlite3.connect(self.DB_PATH)
        cursor = conn.cursor()

        # table if none exists
        cursor.execute("""
        CREATE TABLE IF NOT EXISTS registry (
            id INTEGER PRIMARY KEY,
            original_name TEXT UNIQUE,
            sanitized_name TEXT,
            hash_id TEXT UNIQUE,
            converted INTEGER DEFAULT 0,
            embedded INTEGER DEFAULT 0,
            last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
        """)

        cursor.execute(
            "CREATE UNIQUE INDEX IF NOT EXISTS idx_registry_original_name ON registry(original_name)"
        )
        cursor.execute(
            "CREATE UNIQUE INDEX IF NOT EXISTS idx_registry_hash ON registry(hash_id)"
        )

        conn.commit()
        conn.close()

    def hash_inator(self, filename: str):
        """Generate a determinstic hash_id from filename"""
        return hashlib.sha256(filename.encode("utf-8")).hexdigest()

    def register_inator(self, original_name: str, sanitized_name: str):
        hash_id = self.hash_inator(sanitized_name)
        conn = sqlite3.connect(self.DB_PATH)
        cursor = conn.cursor()

        cursor.execute(
            """
        INSERT INTO registry (original_name, sanitized_name, hash_id)
        VALUES (?,?, ?)
        ON CONFLICT(hash_id) DO UPDATE SET
            last_updated = CURRENT_TIMESTAMP
        """,
            (original_name, sanitized_name, hash_id),
        )

        conn.commit()
        conn.close()

        return hash_id

    def updater_inator(self, status: str, hash_id: str):
        conn = sqlite3.connect(self.DB_PATH)
        cursor = conn.cursor()

        if status in ("converted", "embedded"):
            cursor.execute(
                f"""
            UPDATE registry
            SET {status} = 1,
                last_updated = CURRENT_TIMESTAMP
            WHERE hash_id = ?
            """,
                (hash_id,),
            )

            print(
                f"[DEBUG] Updated {status} for hash_id={hash_id} → {cursor.rowcount} rows affected"
            )

        conn.commit()
        conn.close()

    def check_inator(self, hash_id: str, field: str = "") -> bool:
        """
        Check if a file exists or if a flag is set.
        """

        conn = sqlite3.connect(self.DB_PATH)
        cursor = conn.cursor()

        if field:
            cursor.execute(
                f"SELECT {field} FROM registry WHERE hash_id = ?", (hash_id,)
            )
        else:
            cursor.execute("SELECT 1 FROM registry WHERE hash_id = ?", (hash_id,))

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
            "hash_id",
            "converted",
            "embedded",
        ]
        data = [dict(zip(columns, row)) for row in rows]
        return data

    def reset_inator(self, status, hash_id=None):
        VALID_COLUMNS = {"embedded", "converted"}

        if status not in VALID_COLUMNS:
            raise ValueError("Invalid status field")

        conn = sqlite3.connect(self.DB_PATH)
        cursor = conn.cursor()
        try:
            if hash_id:
                cursor.execute(
                    f"""
                UPDATE registry
                SET {status} = 0
                WHERE hash_id = ?
                """,
                    (hash_id),
                )
            else:
                cursor.execute(f"UPDATE registry SET {status} = 0")
            conn.commit()
            count = cursor.rowcount
            return count

        finally:
            conn.close()
