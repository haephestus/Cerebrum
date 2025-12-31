"""
Complete knowledgebase routes with both file registry and vector store management.
"""

import asyncio
import json
from pathlib import Path

from fastapi import APIRouter, BackgroundTasks, File, HTTPException, Request, UploadFile
from fastapi.responses import StreamingResponse
from pydantic import BaseModel

from cerebrum_core.knowledgebase_inator import (
    EmbeddInator,
    MarkdownChunker,
    MarkdownConverter,
    VectorStoreManager,
)
from cerebrum_core.utils.file_util_inator import (
    CerebrumPaths,
    ChunkRegisterInator,
    FileRegisterInator,
)

router = APIRouter(prefix="/knowledgebase")
archives_dir = CerebrumPaths().get_kb_archives()
markdown_files_dir = CerebrumPaths().get_kb_artifacts()
knowledgebase_dir = CerebrumPaths().get_kb_source_files()


# ========================================
# Background Tasks
# ========================================


def process_single_file_task(file_info: dict, file_registry: FileRegisterInator):
    """
    Process a single file: convert to markdown, chunk, and embed.
    """
    try:
        print(f"Processing: {file_info['original_name']}")
        filepath = Path(file_info["filepath"])

        if not filepath.exists():
            print(f"File not found: {filepath}")
            return

        # Step 1: Convert to Markdown with LLM sanitization
        converter = MarkdownConverter(filepath=filepath)
        markdown_path, metadata = converter.convert(metadata=None)

        # Step 2: Chunk Markdown
        chunker = MarkdownChunker()
        chunked_path = chunker.chunk(
            markdown_path=markdown_path, doc_fingerprint=file_info["fingerprint"]
        )

        # Step 3: Update file registry (mark as converted)
        file_registry.mark_converted_inator(
            fingerprint=file_info["fingerprint"],
            domain=metadata.domain,
            subject=metadata.subject,
            sanitized_name=metadata.title,
        )

        # Step 4: Embed chunks
        embedding_manager = EmbeddInator(fingerprint=file_info["fingerprint"])
        embedding_manager.embed_from_chunked_markdown(
            chunked_markdown=chunked_path,
            collection_name=metadata.subject,
            domain=metadata.domain,
            subject=metadata.subject,
        )

        # Step 5: Mark as embedded
        file_registry.mark_embedded_inator(fingerprint=file_info["fingerprint"])

        print(f"✓ Completed: {file_info['original_name']}")

    except Exception as e:
        print(f"✗ Failed processing {file_info['original_name']}: {e}")
        raise


def markdown_converter_task(
    unconverted_files: list[dict], file_registry: FileRegisterInator
):
    """
    Convert source files to Markdown with LLM-enriched metadata and chunk them.
    """
    for file_info in unconverted_files:
        try:
            print(f"Converting: {file_info['original_name']}")
            filepath = Path(file_info["filepath"])
            if not filepath.exists():
                print(f"File not found: {filepath}")
                continue

            # Convert to Markdown with LLM sanitization
            converter = MarkdownConverter(filepath=filepath)
            markdown_path, metadata = converter.convert(metadata=None)

            # Chunk Markdown
            chunker = MarkdownChunker()
            chunked_path = chunker.chunk(
                markdown_path=markdown_path, doc_fingerprint=file_info["fingerprint"]
            )

            # Update file registry
            file_registry.mark_converted_inator(
                fingerprint=file_info["fingerprint"],
                domain=metadata.domain,
                subject=metadata.subject,
                sanitized_name=metadata.title,
            )

            print(f"✓ Converted & chunked: {file_info['original_name']}")

        except Exception as e:
            print(f"✗ Failed for {file_info['original_name']}: {e}")


def embedding_task(unembedded_files: list[dict], file_registry: FileRegisterInator):
    """
    Embed chunked Markdown files in vector database.
    """
    for file_info in unembedded_files:
        try:
            domain = file_info.get("domain", "default")
            subject = file_info.get("subject", "default")
            sanitized_name = file_info["sanitized_name"]

            # Locate chunked markdown file
            chunked_path = (
                markdown_files_dir / domain / subject / f"{sanitized_name}.chunked.md"
            )

            if not chunked_path.exists():
                print(f"Chunked markdown file not found: {chunked_path}")
                continue

            # Embed using byte-coordinate access
            embedding_manager = EmbeddInator(fingerprint=file_info["fingerprint"])
            embedding_manager.embed_from_chunked_markdown(
                chunked_markdown=chunked_path,
                collection_name=subject,
                domain=domain,
                subject=subject,
            )

            # Mark as embedded in registry
            file_registry.mark_embedded_inator(fingerprint=file_info["fingerprint"])
            print(f"✓ Embedded: {sanitized_name}")

        except Exception as e:
            print(f"✗ Failed embedding {file_info['sanitized_name']}: {e}")
            print("Progress saved — will resume on next run.")


# ========================================
# File Registry Routes
# ========================================


@router.get("/show")
async def show_files(request: Request):
    """Show all source files in registry."""
    file_registry = request.app.state.file_registry
    return file_registry.show_all_inator() or []


@router.post("/upload")
async def upload_pdf(
    request: Request, file: UploadFile = File(...), priority: bool = False
):
    """
    Upload PDF to knowledgebase.

    Args:
        priority: If True, processes immediately. If False, queues for batch processing.
    """
    file_registry = request.app.state.file_registry

    if file.filename is None:
        raise ValueError("filename cannot be None")

    filepath = knowledgebase_dir / file.filename
    filepath.parent.mkdir(parents=True, exist_ok=True)

    # Register file
    file_registry.register_inator(file.filename, str(filepath))

    # Save file
    with filepath.open("wb") as f:
        content = await file.read()
        f.write(content)

    response = {
        "message": "PDF uploaded",
        "filename": file.filename,
        "path": str(filepath),
    }

    if priority:
        response["status"] = "queued for immediate processing"
    else:
        response["status"] = "queued for batch processing"

    return response


@router.post("/process-file/{fingerprint}")
async def process_single_file(
    request: Request, fingerprint: str, background_tasks: BackgroundTasks
):
    """
    Process a single file immediately (convert + embed).
    Use for urgent documents or interactive workflows.

    Monitor progress via /stream-progress/{fingerprint}
    """
    file_registry = request.app.state.file_registry

    # Check if file exists
    if not file_registry.check_inator(fingerprint):
        raise HTTPException(status_code=404, detail="File not found")

    # Check if already processed
    if file_registry.check_inator(fingerprint, "embedded"):
        return {
            "message": "File already processed",
            "fingerprint": fingerprint,
            "status": "completed",
        }

    # Get file info
    all_files = file_registry.show_all_inator()
    file_info = next((f for f in all_files if f["fingerprint"] == fingerprint), None)

    if not file_info:
        raise HTTPException(status_code=404, detail="File info not found")

    # Queue for immediate processing
    background_tasks.add_task(process_single_file_task, file_info, file_registry)

    return {
        "message": "File queued for processing",
        "fingerprint": fingerprint,
        "status": "processing",
        "progress_stream": f"/knowledgebase/stream-progress/{fingerprint}",
    }


@router.get("/stream-progress/{fingerprint}")
async def stream_progress(fingerprint: str):
    """
    Server-Sent Events (SSE) endpoint for real-time progress updates.

    Frontend usage:
        const eventSource = new EventSource('/knowledgebase/stream-progress/abc123');
        eventSource.onmessage = (event) => {
            const progress = JSON.parse(event.data);
            console.log(`Progress: ${progress.progress_pct}%`);
        };
    """

    async def event_generator():
        chunk_registry = ChunkRegisterInator()
        last_progress = -1

        while True:
            try:
                # Get embedding progress
                progress = chunk_registry.get_embedding_progress(fingerprint)

                # Only send update if progress changed
                if progress["progress_pct"] != last_progress:
                    last_progress = progress["progress_pct"]

                    # SSE format: "data: {json}\n\n"
                    data = {
                        "fingerprint": fingerprint,
                        "total": progress["total"],
                        "completed": progress["completed"],
                        "remaining": progress["remaining"],
                        "progress_pct": progress["progress_pct"],
                        "status": (
                            "completed" if progress["remaining"] == 0 else "processing"
                        ),
                    }

                    yield f"data: {json.dumps(data)}\n\n"

                    # Exit if complete
                    if progress["remaining"] == 0 and progress["total"] > 0:
                        yield f"data: {json.dumps({'status': 'done'})}\n\n"
                        break

                # Poll every second
                await asyncio.sleep(1)

            except Exception as e:
                error_data = {"status": "error", "message": str(e)}
                yield f"data: {json.dumps(error_data)}\n\n"
                break

    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
        },
    )


@router.get("/file-status/{fingerprint}")
async def get_file_status(request: Request, fingerprint: str):
    """
    Get current status of a file (polling alternative to SSE).

    Returns file conversion and embedding status.
    """
    file_registry = request.app.state.file_registry
    chunk_registry = ChunkRegisterInator()

    if not file_registry.check_inator(fingerprint):
        raise HTTPException(status_code=404, detail="File not found")

    converted = file_registry.check_inator(fingerprint, "converted")
    embedded = file_registry.check_inator(fingerprint, "embedded")
    chunk_progress = chunk_registry.get_embedding_progress(fingerprint)

    return {
        "fingerprint": fingerprint,
        "converted": converted,
        "embedded": embedded,
        "chunk_progress": chunk_progress,
        "status": "completed" if embedded else "processing" if converted else "pending",
    }


class DeletePayload(BaseModel):
    filename: str
    filepath: str
    fingerprint: str
    collection_name: str | None = None


@router.delete("/delete/")
async def remove_source_file(request: Request, payload: DeletePayload):
    """Remove file from knowledgebase and vector database."""
    file_registry = request.app.state.file_registry

    # Remove from registry and filesystem
    file_registry.remove_inator(payload.filename, payload.fingerprint, payload.filepath)

    # Remove from vector database across all collections
    try:
        manager = VectorStoreManager()
        count = manager.delete_by_fingerprint_all_collections(payload.fingerprint)
        print(f"✓ Deleted {count} documents from vector stores")
    except Exception as e:
        print(f"Warning: Failed to delete from vector stores: {e}")

    return {"detail": "File removed from knowledgebase successfully"}


@router.post("/markdowninator")
async def convert_files(request: Request, background_task: BackgroundTasks):
    """Queue unconverted files for markdown conversion."""
    file_registry = request.app.state.file_registry
    unconverted = file_registry.fetch_unconverted_file_inator()

    if not unconverted:
        return {"message": "No files to convert", "count": 0}

    background_task.add_task(markdown_converter_task, unconverted, file_registry)

    return {
        "message": f"Queued {len(unconverted)} files for conversion",
        "count": len(unconverted),
    }


@router.post("/embeddinator")
async def embedd_files(request: Request, background_task: BackgroundTasks):
    """Queue converted files for embedding."""
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
async def reset_registry(request: Request, status: str, fingerprint: str | None = None):
    """Reset conversion or embedding status in registry."""
    file_registry = request.app.state.file_registry

    if status not in ["converted", "embedded"]:
        raise HTTPException(
            status_code=400, detail="Status must be 'converted' or 'embedded'"
        )

    count = file_registry.reset_inator(status, fingerprint)

    return {"message": f"Reset {status} status", "affected_rows": count}


# ========================================
# Vector Store Management Routes
# ========================================


@router.get("/collections")
async def list_all_collections():
    """
    List all vector database collections with their info.

    Returns:
        List of collections with domain, subject, count, etc.
    """
    manager = VectorStoreManager()
    collections = manager.list_all_collections()

    return {
        "collections": collections,
        "count": len(collections),
    }


@router.get("/collections/{domain}/{subject}/{collection_name}")
async def get_collection_details(domain: str, subject: str, collection_name: str):
    """
    Get detailed information about a specific collection.

    Returns:
        Collection info with count, metadata, sample documents
    """
    manager = VectorStoreManager()

    try:
        info = manager.get_collection_info(collection_name, domain, subject)
        return info
    except Exception as e:
        raise HTTPException(status_code=404, detail=f"Collection not found: {e}")


@router.get("/collections/{domain}/{subject}/{collection_name}/count")
async def get_collection_count(domain: str, subject: str, collection_name: str):
    """Get document count for a specific collection."""
    manager = VectorStoreManager()

    try:
        store = manager.get_store(collection_name, domain, subject)
        count = store._collection.count()
        return {
            "domain": domain,
            "subject": subject,
            "collection": collection_name,
            "count": count,
        }
    except Exception as e:
        raise HTTPException(status_code=404, detail=f"Collection not found: {e}")


@router.delete("/collections/{domain}/{subject}/{collection_name}")
async def delete_collection(domain: str, subject: str, collection_name: str):
    """Delete an entire collection."""
    manager = VectorStoreManager()

    try:
        manager.delete_collection(collection_name, domain, subject)
        return {
            "message": "Collection deleted successfully",
            "domain": domain,
            "subject": subject,
            "collection": collection_name,
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to delete collection: {e}")


# ========================================
# Search Routes
# ========================================


class SearchRequest(BaseModel):
    query: str
    domains: list[str] | None = None
    subjects: list[str] | None = None
    k: int = 5


@router.post("/search")
async def search_collections(request: SearchRequest):
    """
    Search across multiple collections.

    Args:
        query: Search query text
        domains: Optional list of domains to search
        subjects: Optional list of subjects to search
        k: Number of results per collection

    Returns:
        List of matching documents with collection info
    """
    manager = VectorStoreManager()

    try:
        results = manager.search_across_collections(
            query=request.query,
            domains=request.domains,
            subjects=request.subjects,
            k=request.k,
        )

        return {
            "query": request.query,
            "results": results,
            "count": len(results),
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Search failed: {e}")


@router.get("/search/fingerprint/{fingerprint}")
async def find_by_fingerprint(fingerprint: str):
    """
    Find all documents with a specific fingerprint across all collections.

    Args:
        fingerprint: Document fingerprint to search for

    Returns:
        List of documents with collection info
    """
    manager = VectorStoreManager()

    try:
        documents = manager.get_documents_by_fingerprint(fingerprint)

        return {
            "fingerprint": fingerprint,
            "documents": documents,
            "count": len(documents),
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Search failed: {e}")


# ========================================
# Delete Routes
# ========================================


class DeleteByMetadataRequest(BaseModel):
    collection_name: str
    domain: str = "default"
    subject: str = "default"
    metadata_filter: dict


@router.delete("/documents/by-metadata")
async def delete_by_metadata(request: DeleteByMetadataRequest):
    """
    Delete documents matching metadata criteria.

    Example request body:
    {
        "collection_name": "biology",
        "domain": "science",
        "subject": "biology",
        "metadata_filter": {"author": "Smith"}
    }
    """
    manager = VectorStoreManager()

    try:
        count = manager.delete_by_metadata(
            request.collection_name,
            request.metadata_filter,
            request.domain,
            request.subject,
        )

        return {
            "message": "Documents deleted successfully",
            "count": count,
            "filter": request.metadata_filter,
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Delete failed: {e}")


@router.delete("/documents/fingerprint/{fingerprint}")
async def delete_by_fingerprint(fingerprint: str):
    """
    Delete all documents with a specific fingerprint across ALL collections.

    This is useful when removing a source document from the knowledgebase.
    """
    manager = VectorStoreManager()

    try:
        count = manager.delete_by_fingerprint_all_collections(fingerprint)

        return {
            "message": "Documents deleted successfully",
            "fingerprint": fingerprint,
            "total_deleted": count,
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Delete failed: {e}")


# ========================================
# Statistics Routes
# ========================================


@router.get("/stats")
async def get_statistics():
    """
    Get overall knowledgebase statistics.

    Returns:
        Total collections, documents, domains, subjects
    """
    manager = VectorStoreManager()

    collections = manager.list_all_collections()

    total_docs = sum(c["count"] for c in collections)
    unique_domains = len(set(c["domain"] for c in collections))
    unique_subjects = len(set(c["subject"] for c in collections))

    return {
        "total_collections": len(collections),
        "total_documents": total_docs,
        "unique_domains": unique_domains,
        "unique_subjects": unique_subjects,
        "collections": collections,
    }
