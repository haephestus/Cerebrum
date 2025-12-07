import json
import logging
import shutil
from datetime import datetime
from pathlib import Path
from typing import List

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from cerebrum_core.model_inator import (
    CreateResearchProject,
    NoteBase,
    NoteOut,
    ResearchProject,
)
from cerebrum_core.retriever_inator import RetrieverInator
from cerebrum_core.utils.file_manager_inator import CerebrumPaths

# ------------------------- logging & config --------------------------- #
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

llm_model = "granite4:micro"
embedding_model = "qwen3-embedding:4b-q4_K_M"

# --------------------------- router & paths --------------------------- #
project_router = APIRouter(prefix="/projects", tags=["Project API"])

CEREBRUM_PATHS = CerebrumPaths()
ROOT_KB_DIR = CEREBRUM_PATHS.get_kb_dir()

PROJECTS_ROOT = CEREBRUM_PATHS.get_projects_dir()
PROJECTS_ROOT.mkdir(parents=True, exist_ok=True)

VECTORSTORES_ROOT = ROOT_KB_DIR / "vectorstores"
VECTORSTORES_ROOT.mkdir(parents=True, exist_ok=True)


# ------------------------------ UTILITIES ------------------------------ #


def get_project_path(project_id: str) -> Path:
    return PROJECTS_ROOT / project_id


def get_notes_dir(project_id: str) -> Path:
    """
    Returns the notes directory for:
      - projects/<id>/notes
      - study_bubbles/<id>/notes
    Raises HTTPException on invalid project_id.
    """
    projects_path = get_project_path(project_id)
    notes_path = projects_path / "notes"
    notes_path.mkdir(parents=True, exist_ok=True)
    return notes_path


def list_notes_in(notes_path: Path) -> List[NoteOut]:
    notes = []
    for file in notes_path.glob("*.md"):
        content = file.read_text(encoding="utf-8")
        title = content.splitlines()[0] if content else file.stem
        notes.append(NoteOut(title=title, content=content, filename=file.name))
    return notes


# --------------------------- PROJECT CRUD ----------------------------- #


@project_router.get("/", response_model=List[ResearchProject])
def list_projects():
    """
    List all projects found under DATA_DIR/projects.
    Expects each project to have an 'info.txt' with name on first line and description on second line (optional).
    """
    projects = []
    for folder in PROJECTS_ROOT.iterdir():
        if not folder.is_dir():
            continue

        info_file = folder / "info.json"
        if not info_file.exists():
            continue

        data = json.loads(info_file.read_text())

        projects.append(ResearchProject(**data))

    return projects


@project_router.post("/create", response_model=ResearchProject)
def create_project(data: CreateResearchProject) -> ResearchProject:
    """
    Create a new project folder with an info file.
    The project id is a slugified (simple) version of the name.
    """
    project_id = data.name.replace(" ", "_").lower()
    project_path = get_project_path(project_id)

    if project_path.exists():
        raise HTTPException(status_code=400, detail="Project already exists")

    project_path.mkdir(parents=True, exist_ok=True)
    (project_path / "chat").mkdir(parents=True, exist_ok=True)
    (project_path / "notes").mkdir(parents=True, exist_ok=True)
    (project_path / "reviews").mkdir(parents=True, exist_ok=True)

    project_data = ResearchProject(
        id=project_id,
        name=data.name,
        description=data.description,
        domains=data.domains,
        user_goals=data.user_goals,
        created_at=datetime.now(),
    )

    info_file = project_path / "info.json"
    info_file.write_text(project_data.model_dump_json(indent=4), encoding="utf-8")

    return project_data


@project_router.get("/{project_id}")
def get_project(project_id: str) -> ResearchProject:
    project_path = get_project_path(project_id)
    info_file = project_path / "info.json"

    if not info_file.exists():
        raise HTTPException(status_code=404, detail="Project not found")

    data = json.loads(info_file.read_text())

    return ResearchProject(**data)


@project_router.delete("/{project_id}")
def delete_project(project_id: str):
    project_path = get_project_path(project_id)
    if not project_path.exists():
        raise HTTPException(status_code=404, detail="Project not found")

    # Recursively delete folder
    shutil.rmtree(project_path)

    return {"detail": "Project deleted successfully"}


# ------------------------------ NOTES CRUD --------------------------- #
@project_router.get("/{project_id}/notes")
def list_notes(project_id: str):
    notes_dir = get_notes_dir(
        project_id,
    )
    return list_notes_in(notes_dir)


@project_router.post("/{project_id}/notes/create", response_model=NoteOut)
def create_note(project_id: str, note: NoteBase):
    notes_dir = get_notes_dir(
        project_id,
    )

    safe_title = note.title.replace(" ", "_")
    filename = f"{safe_title}.md"
    file_path = notes_dir / filename

    counter = 1
    while file_path.exists():
        filename = f"{safe_title}_{counter}.md"
        file_path = notes_dir / filename
        counter += 1

    file_path.write_text(note.content, encoding="utf-8")
    return NoteOut(title=note.title, content=note.content, filename=filename)


@project_router.get("/{project_id}/notes/get/{filename}", response_model=NoteOut)
def get_note(project_id: str, filename: str):
    notes_dir = get_notes_dir(
        project_id,
    )
    file_path = notes_dir / filename
    if not file_path.exists():
        raise HTTPException(status_code=404, detail="Note not found")
    content = file_path.read_text(encoding="utf-8")
    title = content.splitlines()[0] if content else file_path.stem
    return NoteOut(title=title, content=content, filename=filename)


@project_router.put("/{project_id}/notes/update/{filename}", response_model=NoteOut)
def update_note(project_id: str, filename: str, note: NoteBase):
    notes_dir = get_notes_dir(
        project_id,
    )
    file_path = notes_dir / filename
    if not file_path.exists():
        raise HTTPException(status_code=404, detail="Note not found")
    file_path.write_text(note.content, encoding="utf-8")
    return NoteOut(title=note.title, content=note.content, filename=filename)


@project_router.delete("/{project_id}/notes/delete/{filename}")
def delete_note(project_id: str, filename: str):
    notes_dir = get_notes_dir(
        project_id,
    )
    file_path = notes_dir / filename
    if not file_path.exists():
        raise HTTPException(status_code=404, detail="Note not found")
    file_path.unlink()
    return {"detail": "Note deleted successfully"}


# ------------------------------- CHAT -------------------------------- #
class Query(BaseModel):
    text: str


@project_router.post("/{project_id}/chat")
async def chat_in_project(project_id: str, query: Query):
    """
    Chat inside a specific project.
    Uses the global vectorstore root but you can adapt to per-project vectorstores easily.
    """
    vectorstores_root = VECTORSTORES_ROOT

    processor = RetrieverInator(
        vectorstores_root=str(vectorstores_root),
        embedding_model=embedding_model,
        llm_model=llm_model,
    )

    translated_query = processor.translator_inator(user_query=query.text)
    logger.info("Translated query dict: %s", translated_query)

    processor.constructor_inator(translated_query=translated_query)
    processor.retrieve_inator()
    response = processor.generate_inator(user_query=query.text)

    return {"reply": response}
