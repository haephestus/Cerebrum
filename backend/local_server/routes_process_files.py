# %%
from pathlib import Path

import pymupdf
from fastapi import (
    APIRouter,
    BackgroundTasks,
    Depends,
    File,
    HTTPException,
    Request,
    UploadFile,
)

from cerebrum_core.file_manager_inator import CerebrumPaths, file_walker_inator
from cerebrum_core.ingest_inator import IngestInator
from cerebrum_core.model_inator import UserConfig
from cerebrum_core.user_inator import ConfigManager
from cerebrum_core.utils.progress_bar import progress_bar

router = APIRouter(prefix="/process")
paths = CerebrumPaths()

markdown_files_dir = paths.get_kb_dir() / "markdown"
markdown_files_dir.mkdir(parents=True, exist_ok=True)

knowledgebase_dir = paths.get_kb_dir()


def get_user_config():
    return ConfigManager().load_config()


# ==========================================================
# CONVERTER
# ==========================================================
def markdown_converter_inator(knowledgebase_dir: Path, llm_model: str, registry):
    """Convert PDF files to Markdown"""
    walked_knowledgebase = file_walker_inator(knowledgebase_dir, max_depth=4)

    for file_info in walked_knowledgebase:
        assert file_info is not None, "file info cannot be empty"

        print(f"Converting {file_info['filename']}")
        try:
            with pymupdf.open(file_info["filepath"]) as pdf:
                metadata = pdf.metadata

            markdown_files = IngestInator(filepath=file_info["filepath"])
            sanitized_metadata = markdown_files.sanitize_inator(
                filename=file_info["filestem"], metadata=metadata, llm_model=llm_model
            )

            hash_id = registry.hash_inator(filename=sanitized_metadata.title)
            registry.register_inator(
                original_name=file_info["filestem"],
                sanitized_name=sanitized_metadata.title,
            )
            is_converted = registry.check_inator(field="converted", hash_id=hash_id)
            if is_converted:
                continue
            markdown_files.markdown_inator(metadata=sanitized_metadata)
            registry.updater_inator(status="converted", hash_id=hash_id)

        except Exception as e:
            print(f"Failed for {file_info['filename']}: {e}")


# ==========================================================
# SINGLE FILE PROCESSOR (for uploads)
# ==========================================================
def process_single_pdf(file_path: Path, llm_model: str, embedding_model: str, registry):
    """Process a single PDF: convert to markdown then embed"""
    print(f"Processing uploaded file: {file_path.name}")

    try:
        # Step 1: Convert PDF to Markdown
        with pymupdf.open(file_path) as pdf:
            metadata = pdf.metadata

        markdown_files = IngestInator(filepath=file_path)
        sanitized_metadata = markdown_files.sanitize_inator(
            filename=file_path.stem, metadata=metadata, llm_model=llm_model
        )

        hash_id = registry.hash_inator(filename=sanitized_metadata.title)
        registry.register_inator(
            original_name=file_path.stem, sanitized_name=sanitized_metadata.title
        )

        # Convert to markdown
        markdown_files.markdown_inator(metadata=sanitized_metadata)
        registry.updater_inator(status="converted", hash_id=hash_id)
        print(f" Converted: {file_path.name}")

        # Step 2: Find the generated markdown file and embed it
        markdown_file_path = (
            markdown_files_dir
            / sanitized_metadata.domain
            / sanitized_metadata.subject
            / f"{sanitized_metadata.title}.md"
        )

        if markdown_file_path.exists():
            vectorstores_path = Path(
                f"../data/storage/vectorstores/{sanitized_metadata.domain}/{sanitized_metadata.subject}"
            )
            vectorstores_path.mkdir(parents=True, exist_ok=True)

            markdown_chunks = IngestInator(
                filepath=markdown_file_path,
                embedding_model=embedding_model,
                vectorstores_path=vectorstores_path,
            )

            chunks = markdown_chunks.chunk_inator(markdown_filepath=markdown_file_path)
            total = len(chunks)

            for idx, chunk in enumerate(chunks, start=1):
                markdown_chunks.embedd_inator(
                    chunk=chunk, collection_name=sanitized_metadata.subject
                )
                progress_bar(idx, total)

            registry.updater_inator(status="embedded", hash_id=hash_id)
            print(f" Embedded: {file_path.name}")
        else:
            print(f" Markdown file not found: {markdown_file_path}")

    except Exception as e:
        print(f" Failed to process {file_path.name}: {e}")


# ==========================================================
# EMBEDDER
# ==========================================================
def markdown_embedder_inator(markdown_files_dir: Path, embedding_model: str, registry):
    """Chunk and embed Markdown files into vectorstores"""
    walked_markdown_dir = file_walker_inator(markdown_files_dir, max_depth=4)

    for md_file in walked_markdown_dir:
        print(md_file["filename"])
        try:
            vectorstores_path = Path(
                f"../data/storage/vectorstores/{md_file['domain']}/{md_file['subject']}"
            )
            vectorstores_path.mkdir(parents=True, exist_ok=True)

            markdown_chunks = IngestInator(
                filepath=md_file["filepath"],
                embedding_model=embedding_model,
                vectorstores_path=vectorstores_path,
            )

            hash_id = registry.hash_inator(md_file["filestem"])
            is_embedded = registry.check_inator(field="embedded", hash_id=hash_id)
            if is_embedded:
                print(f"skipping {md_file['filestem']}")
                continue
            chunks = markdown_chunks.chunk_inator(markdown_filepath=md_file["filepath"])
            total = len(chunks)

            for idx, chunk in enumerate(chunks, start=1):
                markdown_chunks.embedd_inator(
                    chunk=chunk, collection_name=md_file["subject"]
                )
                progress_bar(idx, total)

                # last updated chunk
                # registry.update_last_embedded_chunk(hash_id, idx)

            # TODO: implement a hash fetcher
            registry.updater_inator(status="embedded", hash_id=hash_id)

        except Exception as e:
            print(f"Failed for {md_file['filename']}: {e}")


# ==========================================================
# ROUTES
# ==========================================================
@router.get("/")
async def stats(request: Request):
    reg = request.app.state.registry
    data = reg.show_all_inator() or []
    return {"registry": data}


@router.post("/reset/{status}")
async def reset(status: str, request: Request, hash_id: str | None = None):
    reg = request.app.state.registry
    data = reg.reset_inator(status, hash_id)
    return data


@router.post("/markdowninator")
async def convert_files(
    background_tasks: BackgroundTasks,
    request: Request,
    config: UserConfig = Depends(get_user_config),
):
    """Queue Markdown conversion in background"""
    chat_model = config.models.chat_model or "llama3.2:3b"
    reg = request.app.state.registry
    background_tasks.add_task(
        markdown_converter_inator, knowledgebase_dir, chat_model, reg
    )
    return {"message": "Conversion started in background"}


@router.post("/embeddinator")
async def embedd_files(
    background_tasks: BackgroundTasks,
    request: Request,
    config: UserConfig = Depends(get_user_config),
):
    embedding_model = config.models.embedding_model or "mxbai-embed-large:latest"
    """Queue Markdown embedding in background"""
    reg = request.app.state.registry
    background_tasks.add_task(
        markdown_embedder_inator, markdown_files_dir, embedding_model, reg
    )
    return {"message": "Embedding started in background"}


@router.post("/upload")
async def upload_pdf(
    background_tasks: BackgroundTasks,
    request: Request,
    file: UploadFile = File(...),
    config: UserConfig = Depends(get_user_config),
):
    chat_model = config.models.chat_model or "llama3.2:3b"
    embedding_model = config.models.embedding_model or "mxbai-embed-large:latest"
    """Upload a PDF file and auto-process it"""
    # Validate file type
    if not file.filename or not file.filename.lower().endswith(".pdf"):
        raise HTTPException(status_code=400, detail="Only PDF files are allowed")

    # Ensure knowledgebase directory exists
    knowledgebase_dir.mkdir(parents=True, exist_ok=True)

    # Save file
    if file.filename is None:
        raise ValueError("filename cannot be None")

    # TODO: dir aware file uploads?
    file_path = knowledgebase_dir / "uploads" / file.filename

    try:
        contents = await file.read()
        with open(file_path, "wb") as f:
            f.write(contents)

        # Auto-process the uploaded PDF
        if background_tasks and request:
            reg = request.app.state.registry
            # Convert to markdown
            background_tasks.add_task(
                process_single_pdf, file_path, chat_model, embedding_model, reg
            )

        return {
            "message": "PDF uploaded and queued for processing",
            "filename": file.filename,
            "path": str(file_path),
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to upload file: {str(e)}")
