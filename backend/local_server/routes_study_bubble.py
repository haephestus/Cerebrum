import hashlib
import json
import logging
import shutil
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List

import jsonpatch
from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel

from cerebrum_core.file_manager_inator import CerebrumPaths
from cerebrum_core.model_inator import (
    ContentDiff,
    CreateStudyBubble,
    InkDiff,
    NoteBase,
    NoteContent,
    NoteOut,
    NoteStorage,
    StudyBubble,
    UserConfig,
)
from cerebrum_core.retriever_inator import RetrieverInator
from cerebrum_core.user_inator import (
    DEFAULT_CHAT_MODEL,
    DEFAULT_EMBED_MODEL,
    ConfigManager,
)

bubble_router = APIRouter(prefix="/bubbles", tags=["Study Bubble API"])

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Config
llm_model = "granite4:micro"
embedding_model = "qwen3-embedding:4b-q4_K_M"

CEREBRUM_PATHS = CerebrumPaths()
ROOT_KB_DIR = CEREBRUM_PATHS.get_kb_dir()

# Base directories
STUDY_BUBBLES_DIR = CEREBRUM_PATHS.get_bubbles_dir()
STUDY_BUBBLES_DIR.mkdir(parents=True, exist_ok=True)

VECTORSTORES_DIR = ROOT_KB_DIR / "vectorstores"
VECTORSTORES_DIR.mkdir(parents=True, exist_ok=True)


# ------------------------------ UTILITIES ------------------------------ #
def hash_obj(obj: Any) -> str:
    """Return MD5 hash of object JSON strin."""
    return hashlib.md5(json.dumps(obj, sort_keys=True).encode()).hexdigest()


def get_user_config():
    return ConfigManager().load_config()


def get_bubble_path(bubble_id: str) -> Path:
    path = STUDY_BUBBLES_DIR / bubble_id
    return path


def get_notes_tracker_path(bubble_id: str) -> Path:
    path = STUDY_BUBBLES_DIR / bubble_id / "tracker"
    return path


def get_notes_dir(bubble_id: str) -> Path:
    """
    Always returns:
    DATA_DIR/study_bubbles/<bubble_id>/notes
    """
    bubble_path = get_bubble_path(bubble_id)
    notes_path = bubble_path / "notes"
    notes_path.mkdir(parents=True, exist_ok=True)
    return notes_path


def ensure_valid_document(document: Dict[str, Any]) -> Dict[str, Any]:
    """
    Ensure the document has valid AppFlowy structure with delta fields.
    """
    if not document:
        return {
            "type": "page",
            "children": [{"type": "paragraph", "data": {"delta": [{"insert": ""}]}}],
        }

    # Ensure children exist
    if "children" not in document or not isinstance(document["children"], list):
        document["children"] = [
            {"type": "paragraph", "data": {"delta": [{"insert": ""}]}}
        ]
        return document

    # Validate each child has delta
    for child in document["children"]:
        if isinstance(child, dict):
            if child.get("type") == "paragraph":
                if "data" not in child:
                    child["data"] = {}
                if isinstance(child["data"], dict) and "delta" not in child["data"]:
                    child["data"]["delta"] = [{"insert": ""}]

    return document


# --------------------------- STUDY BUBBLE CRUD -------------------------- #


@bubble_router.get("/", response_model=List[StudyBubble])
def list_study_bubbles():
    """
    List all study bubbles.
    """
    bubbles = []
    for folder in STUDY_BUBBLES_DIR.iterdir():
        if not folder.is_dir():
            continue

        info_file = folder / "info.json"
        if not info_file.exists():
            continue

        data = json.loads(info_file.read_text())

        bubbles.append(StudyBubble(**data))

    return bubbles


@bubble_router.post("/create")
def create_study_bubble(data: CreateStudyBubble) -> StudyBubble:
    """
    Create a study bubble folder and info file.
    """
    bubble_id = data.name.replace(" ", "_").lower()
    bubble_path = get_bubble_path(bubble_id)

    if bubble_path.exists():
        raise HTTPException(status_code=400, detail="Bubble already exists")

    # Initialize study bubble associated dirs
    bubble_path.mkdir(parents=True, exist_ok=True)
    (bubble_path / "chat").mkdir(parents=True, exist_ok=True)
    (bubble_path / "notes").mkdir(parents=True, exist_ok=True)
    (bubble_path / "quizzes").mkdir(parents=True, exist_ok=True)
    (bubble_path / "notes" / "tracker").mkdir(parents=True, exist_ok=True)

    # TODO: initiate study bubble vectorstore
    bubble_data = StudyBubble(
        id=bubble_id,
        name=data.name,
        description=data.description,
        domains=data.domains,
        user_goals=data.user_goals,
        created_at=datetime.now(),
    )

    info_file = bubble_path / "info.json"
    info_file.write_text(bubble_data.model_dump_json(indent=4), encoding="utf-8")

    return bubble_data


@bubble_router.get("/{bubble_id}")
def get_study_bubble(bubble_id: str) -> StudyBubble:
    """
    Fetch a single study bubble's info.
    """
    bubble_path = get_bubble_path(bubble_id)
    info_file = bubble_path / "info.json"

    if not info_file.exists():
        raise HTTPException(status_code=404, detail="Study bubble not found")

    data = json.loads(info_file.read_text())
    return StudyBubble(**data)


@bubble_router.delete("/{bubble_id}")
def delete_study_bubble(bubble_id: str):
    """
    Delete a bubble and its notes.
    """
    bubble_path = get_bubble_path(bubble_id)

    if not bubble_path.exists():
        raise HTTPException(status_code=404, detail="Study bubble not found")

    # Recursively delete the folder
    shutil.rmtree(bubble_path)

    return {"detail": "Study bubble deleted successfully"}


# ------------------------------- NOTES CRUD ------------------------------ #


# List notes
@bubble_router.get("/{bubble_id}/notes", response_model=List[NoteOut])
def list_notes_in_bubble(bubble_id: str):
    notes_dir = get_notes_dir(bubble_id)
    notes = []
    for file in notes_dir.glob("*.json"):
        storage_data = json.loads(file.read_text(encoding="utf-8"))
        content_obj = NoteContent(**storage_data["content"])
        notes.append(
            NoteOut(
                title=storage_data["title"],
                content=content_obj,
                ink=storage_data.get("ink", []),
                filename=file.name,
            )
        )
    return notes


# Create a new note
@bubble_router.post("/{bubble_id}/create/notes", response_model=NoteOut)
def create_note(bubble_id: str, note: NoteBase):
    notes_dir = get_notes_dir(bubble_id)
    note.content.document = ensure_valid_document(note.content.document)

    safe_title = note.title.replace(" ", "_")
    filename = f"{safe_title}.json"
    file_path = notes_dir / filename

    # Avoid collisions
    counter = 1
    while file_path.exists():
        filename = f"{safe_title}_{counter}.json"
        file_path = notes_dir / filename
        counter += 1

    storage = NoteStorage(
        title=note.title,
        content=note.content,
        ink=note.ink or [],
        bubble_id=bubble_id,
    )
    storage.metadata.content_hash = hash_obj(storage.content.model_dump())
    storage.metadata.ink_hash = hash_obj([s.dict() for s in storage.ink])

    file_path.write_text(storage.model_dump_json(indent=2), encoding="utf-8")

    return NoteOut(
        title=storage.title,
        content=storage.content,
        ink=storage.ink or [],
        filename=filename,
    )


# Get a single note
@bubble_router.get("/{bubble_id}/notes/get/{filename}", response_model=NoteOut)
def get_note(bubble_id: str, filename: str):
    notes_dir = get_notes_dir(bubble_id)
    file_path = notes_dir / filename

    if not file_path.exists():
        raise HTTPException(status_code=404, detail="Note not found")

    storage_data = json.loads(file_path.read_text(encoding="utf-8"))

    # Ensure the document is valid before returning
    if "content" in storage_data and "document" in storage_data["content"]:
        storage_data["content"]["document"] = ensure_valid_document(
            storage_data["content"]["document"]
        )

    content_obj = NoteContent(**storage_data["content"])

    return NoteOut(
        title=storage_data["title"],
        content=content_obj,
        ink=storage_data.get("ink", []),
        filename=filename,
    )


@bubble_router.post("/{bubble_id}/debug/notes")
async def debug_create_note(bubble_id: str, request: Request):
    """Temporary debug endpoint"""
    body = await request.json()
    logger.info(f"Received body: {json.dumps(body, indent=2)}")
    return {"received": body}


# Update a note
@bubble_router.put("/{bubble_id}/notes/update/{filename}", response_model=NoteOut)
def update_note(bubble_id: str, filename: str, note: NoteBase):
    notes_dir = get_notes_dir(bubble_id)
    file_path = notes_dir / filename
    if not file_path.exists():
        raise HTTPException(status_code=404, detail="Note not found")

    # Load existing storage
    storage_data = json.loads(file_path.read_text(encoding="utf-8"))
    storage = NoteStorage(**storage_data)

    # Ensure document valid
    note.content.document = ensure_valid_document(note.content.document)

    # ---------- CONTENT DIFF ----------
    old_content = storage.content.dict()
    new_content = note.content.dict()
    if old_content != new_content:
        patch_ops = jsonpatch.make_patch(old_content, new_content).patch
        storage.history.content.append(
            ContentDiff(
                version=storage.metadata.content_version,
                ts=datetime.now(),
                ops=patch_ops,
            )
        )
        storage.metadata.content_version += 1
        storage.content = note.content
        storage.metadata.content_hash = hash_obj(new_content)

    # ---------- INK DIFF ----------
    old_ink = [s.dict() for s in storage.ink]
    new_ink = [s.dict() for s in note.ink or []]
    if old_ink != new_ink:
        # Simple full replace diff for now
        ops = [{"op": "replace", "strokes": new_ink}]
        storage.history.ink.append(
            InkDiff(version=storage.metadata.ink_version, ts=datetime.now(), ops=ops)
        )
        storage.metadata.ink_version += 1
        storage.ink = note.ink or []
        storage.metadata.ink_hash = hash_obj(new_ink)

    # Save updated note
    file_path.write_text(storage.model_dump_json(indent=2), encoding="utf-8")

    return NoteOut(
        title=storage.title,
        content=storage.content,
        ink=storage.ink,
        filename=filename,
    )  # Delete a note


@bubble_router.delete("/{bubble_id}/notes/delete/{filename}")
def delete_note(bubble_id: str, filename: str):
    notes_dir = get_notes_dir(bubble_id)
    file_path = notes_dir / filename

    if not file_path.exists():
        raise HTTPException(status_code=404, detail="Note not found")

    file_path.unlink()
    return {"detail": "Note deleted successfully"}


# ---------------------------- CHAT ENDPOINT ------------------------------ #


class Query(BaseModel):
    text: str


# TODO: index notes directly linked to the current bubbleid
@bubble_router.post("/{bubble_id}/chat")
async def chat_in_bubble(
    bubble_id: str, query: Query, config: UserConfig = Depends(get_user_config)
):
    """
    Chat inside a specific study bubble.
    """
    vectorstore_root = VECTORSTORES_DIR
    chat_model = config.models.chat_model or DEFAULT_CHAT_MODEL
    embedding_model = config.models.embedding_model or DEFAULT_EMBED_MODEL

    processor = RetrieverInator(
        vectorstores_root=str(vectorstore_root),
        embedding_model=embedding_model,
        llm_model=chat_model,
    )

    # TRANSLATE USER QUERY
    translated_query = processor.translator_inator(user_query=query.text)
    logger.info("Translated Query: %s", translated_query)

    # CONSTRUCT CONTEXT
    processor.constructor_inator(translated_query=translated_query)

    # RETRIEVE
    processor.retrieve_inator()

    # GENERATE RESPONSE
    response = processor.generate_inator(user_query=query.text)

    return {"reply": response}
