# %%
from pathlib import Path

from fastapi import APIRouter, BackgroundTasks, File, HTTPException, Request, UploadFile
from pymupdf4llm import pymupdf

from cerebrum_core.file_processor_inator import IngestInator
from cerebrum_core.utils.file_util_inator import CerebrumPaths, FileRegisterInator

router = APIRouter(prefix="/knowledgebase")
archives_dir = CerebrumPaths().get_kb_archives()
markdown_files_dir = CerebrumPaths().get_kb_artifacts()
knowledgebase_dir = CerebrumPaths().get_kb_source_files()


def markdown_converter_task(
    unconverted_files: list[dict], file_registry: FileRegisterInator
):
    """Background task to convert PDFs to Markdown"""
    for file_info in unconverted_files:
        print(f"Converting {file_info['original_name']}")
        try:
            filepath = Path(file_info["filepath"])

            if not filepath.exists():
                print(f"⚠ File not found: {filepath}")
                continue

            with pymupdf.open(filepath) as pdf:
                metadata = pdf.metadata

            ingestor = IngestInator(filepath=filepath)
            sanitized_metadata = ingestor.sanitize_inator(
                filename=file_info["original_name"], metadata=metadata
            )

            ingestor.markdown_inator(metadata=sanitized_metadata)

            file_registry.mark_converted_inator(
                domain=sanitized_metadata.domain,
                subject=sanitized_metadata.subject,
                fingerprint=file_info["fingerprint"],
                sanitized_name=sanitized_metadata.title,
            )

            print(f"✓ Converted: {file_info['original_name']}")

        except Exception as e:
            print(f"✗ Failed for {file_info['original_name']}: {e}")


def embedding_task(unembedded_files: list[dict], file_registry: FileRegisterInator):
    """Background task to embed Markdown files"""
    for file_info in unembedded_files:
        print(f"Embedding {file_info['sanitized_name']}")
        try:
            # Reconstruct paths
            original_filepath = Path(file_info["filepath"])

            # Need to parse domain/subject from filepath or metadata
            # Assuming structure: knowledgebase_dir/domain/subject/file.pdf
            path_parts = original_filepath.relative_to(knowledgebase_dir).parts
            domain = path_parts[0] if len(path_parts) > 0 else "general"
            subject = path_parts[1] if len(path_parts) > 1 else "misc"

            markdown_path = (
                markdown_files_dir
                / domain
                / subject
                / f"{file_info['sanitized_name']}.md"
            )

            if not markdown_path.exists():
                print(f"Markdown not found: {markdown_path}")
                continue

            archives_path = archives_dir / domain / subject
            archives_path.mkdir(parents=True, exist_ok=True)

            # Use original PDF for fingerprinting
            ingestor = IngestInator(
                filepath=original_filepath,
            )

            # Chunk and embed
            chunks = ingestor.chunk_inator(markdown_filepath=markdown_path)

            # Check progress
            chunk_progress = ingestor.registry.get_embedding_progress(
                ingestor.fingerprint
            )
            if chunk_progress["total"] > 0 and chunk_progress["remaining"] > 0:
                print(
                    f"Resuming: {chunk_progress['completed']}/{chunk_progress['total']} chunks"
                )

            ingestor.embedd_inator(collection_name=subject, chunk_fingerprint="")

            file_registry.mark_embedded_inator(
                fingerprint=file_info["fingerprint"],
            )

            print(f"Embedded: {file_info['sanitized_name']}")

        except Exception as e:
            print(f"Failed for {file_info['sanitized_name']}: {e}")
            print("   Progress saved - will resume on next run")


# ==========================================================
# ROUTES
# ==========================================================
@router.get("/show")
async def stats(request: Request):
    file_registry = request.app.state.file_registry
    return file_registry.show_all_inator() or []


@router.post("/upload")
async def upload_pdf(
    request: Request,
    file: UploadFile = File(...),
):
    """Upload a PDF file and auto-process it"""
    file_registry = request.app.state.file_registry
    if file.filename is None:
        raise ValueError("filename cannot be None")

    filepath = knowledgebase_dir / file.filename
    filepath.parent.mkdir(parents=True, exist_ok=True)

    file_registry.register_inator(file.filename, str(filepath))
    with filepath.open("wb") as f:
        content = await file.read()
        f.write(content)

    return {
        "message": "PDF uploaded and queued for processing",
        "filename": file.filename,
        "path": str(filepath),
    }


@router.delete("/delete")
async def delete_pdf():
    pass


@router.post("/remove/{status}")
async def remove_from_registry():
    pass


@router.post("/markdowninator")
async def convert_files(request: Request, background_task: BackgroundTasks):
    """Queue Markdown conversion in background"""
    # get file from registry
    file_registry = request.app.state.file_registry
    unconverted = file_registry.fetch_unconverted_file_inator()
    if not unconverted:
        return {"message": "No files to convert", "count": 0}

    background_task.add_task(markdown_converter_task, unconverted, file_registry)


@router.post("/embeddinator")
async def embedd_files(request: Request, background_task: BackgroundTasks):
    """Embedd Markdown files in the background"""
    file_registry = request.app.state.file_registry
    unembedded = file_registry.fetch_unembedded_file_inator()

    if not unembedded:
        return {"message": "No files to embed", "count": 0}
    background_task.add_task(embedding_task, unembedded, file_registry)

    return {
        "message": f"Queued {len(unembedded)} files for embedding",
        "count": len(unembedded),
    }


@router.post("/reset/{status}")
async def reset_registry(request: Request, status: str, fingerprint: str | None):
    """Queue Markdown embedding in background"""
    file_registry = request.app.state.file_registry

    if status not in ["converted", "embedded"]:
        raise HTTPException(
            status_code=400, detail="Status must be 'converted' or 'embedded'"
        )

    count = file_registry.reset_inator(status, fingerprint)
    return {"message": f"Reset {status} status", "affected_rows": count}
