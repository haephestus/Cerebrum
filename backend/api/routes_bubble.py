import hashlib
import json
import logging
import shutil
from datetime import datetime
from typing import Any, Dict, List

import jsonpatch
import ulid
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from agents.rose import RosePrompts
from cerebrum_core.model_inator import (
    ContentDiff,
    CreateStudyBubble,
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
from cerebrum_core.utils.file_manager_inator import CerebrumPaths
from cerebrum_core.utils.note_util_inator import ArchiveInator, diff_collapser_inator

bubble_router = APIRouter(prefix="/bubbles", tags=["Study Bubble API"])

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# ------------------------------ UTILITIES ------------------------------ #
# TODO: move to note_util_inator?
def hash_obj(obj: Any) -> str:
    """Return MD5 hash of object JSON strin."""
    return hashlib.md5(json.dumps(obj, sort_keys=True).encode()).hexdigest()


def get_user_config():
    return ConfigManager().load_config()


# TODO: move to note_util_inator?
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


# TODO: move to note_util_inator?
def extract_total_text(doc):
    text_chunks = []
    for child in doc.get("children", []):
        for op in child["data"].get("delta", []):
            text_chunks.append(op.get("insert", ""))
    return "".join(text_chunks)


# TODO: move to note_util_inator?
def calculate_version_increment(old_doc: dict, new_doc: dict) -> float:
    """
    Rules:
      - If text added > 100 chars OR new children > 10 → major bump (+1)
      - Else → minor bump (+0.01)
    """
    # Entire text
    old_text = extract_total_text(old_doc)
    new_text = extract_total_text(new_doc)

    added_chars = len(new_text) - len(old_text)

    # Child changes (block additions)
    old_children = old_doc.get("children", [])
    new_children = new_doc.get("children", [])
    added_children = max(0, len(new_children) - len(old_children))

    # ----- Decision -----

    if added_chars > 250 or added_children > 10:
        return 1.0  # major bump
    elif added_chars > 125 or added_children > 5:
        return 0.1  # medium bump
    elif added_chars > 0:
        return 0.01  # minor bump
    else:
        return 0.0  # unchanged


# --------------------------- STUDY BUBBLE CRUD -------------------------- #


@bubble_router.get("/", response_model=List[StudyBubble])
def list_study_bubbles():
    STUDY_BUBBLES_DIR = CerebrumPaths().get_bubbles_root()
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
    bubble = CerebrumPaths().get_bubbles_root() / bubble_id

    if bubble.exists():
        raise HTTPException(status_code=400, detail="Bubble already exists")

    # Initialize study bubble associated dirs
    # TODO: move to file_manager_inator
    CerebrumPaths().init_bubble_dirs(bubble_id=bubble_id)

    # TODO: initiate study bubble archives
    bubble_data = StudyBubble(
        id=bubble_id,
        name=data.name,
        description=data.description,
        domains=data.domains,
        user_goals=data.user_goals,
        created_at=datetime.now(),
    )

    info_file = bubble / "info.json"
    info_file.write_text(bubble_data.model_dump_json(indent=4), encoding="utf-8")

    return bubble_data


@bubble_router.get("/{bubble_id}")
def get_study_bubble(bubble_id: str) -> StudyBubble:
    """
    Fetch a single study bubble's info.
    """

    bubble_path = CerebrumPaths().get_bubble_path(bubble_id)
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
    bubble_path = CerebrumPaths().get_bubble_path(bubble_id)

    if not bubble_path.exists():
        raise HTTPException(status_code=404, detail="Study bubble not found")

    # Recursively delete the folder
    shutil.rmtree(bubble_path)

    return {"detail": "Study bubble deleted successfully"}


# ------------------------------- NOTES CRUD ------------------------------ #


# List notes
@bubble_router.get("/{bubble_id}/notes", response_model=List[NoteOut])
def list_notes_in_bubble(bubble_id: str):
    notes_dir = CerebrumPaths().get_notes_dir(bubble_id)
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
    notes_dir = CerebrumPaths().get_notes_dir(bubble_id)
    note.content.document = ensure_valid_document(note.content.document)

    safe_title = note.title.replace(" ", "_")
    filename = f"{safe_title}.json"
    file_path = notes_dir / filename
    note_id = ulid.ulid()

    # Avoid collisions
    counter = 1
    while file_path.exists():
        filename = f"{safe_title}_{counter}.json"
        file_path = notes_dir / filename
        counter += 1

    storage = NoteStorage(
        note_id=note_id,
        title=note.title,
        bubble_id=bubble_id,
        content=note.content,
        ink=note.ink or [],
    )
    storage.metadata.content_hash = hash_obj(storage.content.model_dump())
    storage.metadata.ink_hash = hash_obj([s.model_dump() for s in storage.ink])

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
    notes_dir = CerebrumPaths().get_notes_dir(bubble_id)
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


'''
@bubble_router.post("/{bubble_id}/debug/notes")
async def debug_create_note(bubble_id: str, request: Request):
    """Temporary debug endpoint"""
    body = await request.json()
    logger.info(f"Received body: {json.dumps(body, indent=2)}")
    return {"received": body}
'''


# Update a note
@bubble_router.put("/{bubble_id}/notes/update/{filename}", response_model=NoteOut)
def update_note(bubble_id: str, filename: str, note: NoteBase):
    notes_dir = CerebrumPaths().get_notes_dir(bubble_id)
    archive_path = notes_dir / ".archives"
    file_path = notes_dir / filename
    if not file_path.exists():
        raise HTTPException(status_code=404, detail="Note not found")

    # Load existing storage
    stored_note_data = json.loads(file_path.read_text(encoding="utf-8"))
    stored_note = NoteStorage(**stored_note_data)

    # Ensure document valid
    note.content.document = ensure_valid_document(note.content.document)

    # ---------- CREATE DIFFS -------------
    # ---------- CONTENT DIFF ----------
    old_content = stored_note.content.model_dump()
    new_content = note.content.model_dump()
    version = stored_note.metadata.content_version
    increment = calculate_version_increment(
        old_doc=stored_note.content.document, new_doc=note.content.document
    )

    if old_content != new_content:
        patch_ops = jsonpatch.make_patch(old_content, new_content).patch
        stored_note.history.content.append(
            ContentDiff(
                version=stored_note.metadata.content_version,
                ts=datetime.now(),
                ops=patch_ops,
            )
        )

        version = int(version) + 1 if increment == 1 else version + increment

        stored_note.content = note.content
        stored_note.metadata.content_hash = hash_obj(new_content)

    # ---------- INK DIFF ----------
    # TODO: revisit when ink has been incorporated
    """
    old_ink = [s.model_dump() for s in stored_note.ink]
    new_ink = [s.model_dump() for s in note.ink or []]
    if old_ink != new_ink:
        # Simple full replace diff for now
        ops = [{"op": "replace", "strokes": new_ink}]
        stored_note.history.ink.append(
            InkDiff(
                version=stored_note.metadata.ink_version, ts=datetime.now(), ops=ops
            )
        )
        # TODO: add major/minor version handlers
        stored_note.metadata.ink_version += 1
        stored_note.ink = note.ink or []
        stored_note.metadata.ink_hash = hash_obj(new_ink)
    """

    # ----------------- COMPRESS DIFFS -------------------
    stored_note = diff_collapser_inator(stored_note)

    # ---------- ADD TO HISTORIC NOTES ARCHIVE -------------
    should_archive = (increment == 1) or (version == 1)
    if should_archive:
        archive = ArchiveInator(note=stored_note, note_archives=str(archive_path))
        archive.archive_init_inator()
        archive.archive_populator_inator()

    # Save updated note
    file_path.write_text(stored_note.model_dump_json(indent=2), encoding="utf-8")

    return NoteOut(
        filename=filename,
        ink=stored_note.ink,
        title=stored_note.title,
        content=stored_note.content,
        bubble_id=stored_note.bubble_id,
    )


@bubble_router.put("/{bubble_id}/notes/rename/{filename}", response_model=NoteOut)
def rename_note(bubble_id: str, filename: str, payload: NoteBase):
    notes_dir = CerebrumPaths().get_notes_dir(bubble_id)
    old_path = notes_dir / filename

    if not old_path.exists():
        raise HTTPException(status_code=404, detail="Origincal note not found")

    # Load old note into memory
    old_data = json.loads(old_path.read_text(encoding="utf-8"))
    old_note = NoteStorage(**old_data)

    # Capture payload data
    old_note.title = payload.title
    new_filename = f"{payload.title}.json"
    new_path = notes_dir / new_filename

    if new_path.exists():
        raise HTTPException(status_code=409, detail="Target filename already exists")

    # Write new note data to disk
    new_path.write_text(old_note.model_dump_json(indent=2), encoding="utf-8")
    old_path.unlink()

    return NoteOut(**old_note.model_dump(), filename=new_filename)


# Delete a note
@bubble_router.delete("/{bubble_id}/notes/delete/{filename}")
def delete_note(bubble_id: str, filename: str):
    notes_dir = CerebrumPaths().get_notes_dir(bubble_id)
    filepath = notes_dir / filename

    if not filepath.exists():
        raise HTTPException(status_code=404, detail="Note not found")

    # TODO: delete note from the archive
    data = json.loads(filepath.read_text())
    ArchiveInator(
        note=NoteStorage(**data), note_archives=str(filepath)
    ).archive_cleaner_inator()

    filepath.unlink()
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
    archives_root = CerebrumPaths().get_kb_archives()
    chat_model = config.models.chat_model or DEFAULT_CHAT_MODEL
    embedding_model = config.models.embedding_model or DEFAULT_EMBED_MODEL
    translation_prompt = RosePrompts.get_prompt("rose_query_translator")
    processor = RetrieverInator(
        archives_root=str(archives_root),
        embedding_model=embedding_model,
        chat_model=chat_model,
    )

    assert translation_prompt is not None
    # TRANSLATE USER QUERY
    translated_query = processor.translator_inator(
        user_query=query.text,
        translation_prompt=translation_prompt,
    )
    logger.info("Translated Query: %s", translated_query)

    # CONSTRUCT CONTEXT
    processor.constructor_inator(translated_query=translated_query)

    # TODO: cache responses for bubbles
    # RETRIEVE from knowledgebase and from note/.archives
    processor.retrieve_inator()

    # GENERATE RESPONSE
    response = processor.generate_inator(user_query=query.text)

    return {"reply": response}
