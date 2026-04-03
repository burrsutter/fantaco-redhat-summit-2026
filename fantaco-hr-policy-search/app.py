#!/usr/bin/env python3
"""
 FantaCo HR Policy Search — RAG-powered document search service.

Provides document management and semantic search over HR policy documents
using pgvector embeddings and an OpenAI-compatible LLM for answer generation.
"""

import logging
import os
from contextlib import asynccontextmanager
from typing import List

import psycopg
from psycopg.rows import dict_row
from fastapi import FastAPI, Depends, HTTPException

import config
from database import get_conn, init_db
import document_service
import rag_service
from schemas import (
    DocumentCreate,
    DocumentUpdate,
    DocumentMetadata,
    DocumentDetail,
    SearchRequest,
    SearchResponse,
    SourceChunk,
    HealthResponse,
)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger(__name__)

DOMAIN = "hr-policy"


def _auto_seed_documents():
    """
    AUTO-SEED ON STARTUP: Automatically loads seed documents into the database
    and vector store when the service starts.

    This runs once at startup and is IDEMPOTENT — if a seed file has already
    been imported (matched by source_filename), it is skipped. This means
    restarting the pod will NOT create duplicate documents or embeddings.

    Flow for each .txt/.md file in seed_documents/:
      1. Check if the file was already imported (by source_filename)
      2. If not, insert the raw document text into the 'documents' table
      3. Split the document into chunks (using RecursiveCharacterTextSplitter)
      4. Generate vector embeddings for each chunk (using nomic-embed-text-v1.5)
      5. Store the embeddings in pgvector for later semantic search
    """
    from database import pool

    seed_dir = os.path.join(os.path.dirname(__file__), "seed_documents")
    if not os.path.isdir(seed_dir):
        logger.warning("No seed_documents/ directory found — skipping auto-seed")
        return

    # Collect all .txt and .md files from the seed_documents/ directory
    seed_files = sorted(
        f for f in os.listdir(seed_dir) if f.endswith((".txt", ".md"))
    )
    if not seed_files:
        logger.info("No seed documents found in seed_documents/ — nothing to seed")
        return

    logger.info(f"Auto-seed: found {len(seed_files)} seed document(s)")

    seeded_count = 0
    skipped_count = 0

    with pool.connection() as conn:
        for filename in seed_files:
            # Step 1: Check if this file was already imported (idempotency check)
            with conn.cursor(row_factory=dict_row) as cur:
                cur.execute(
                    "SELECT id FROM documents WHERE source_filename = %s",
                    (filename,),
                )
                if cur.fetchone():
                    logger.info(f"  SKIP (already imported): {filename}")
                    skipped_count += 1
                    continue

            # Step 2: Read the file content
            filepath = os.path.join(seed_dir, filename)
            with open(filepath, "r") as f:
                content = f.read()

            # Derive a human-readable title from the filename
            # e.g. "fantaco-hr-benefits.md" -> "Fantaco Hr Benefits"
            title = (
                os.path.splitext(filename)[0]
                .replace("-", " ")
                .replace("_", " ")
                .title()
            )

            # Step 3: Insert raw document into the 'documents' table
            doc = DocumentCreate(
                title=title,
                content=content,
                source_filename=filename,
                category="seed",
            )
            db_doc = document_service.create_document(conn, doc)

            # Step 4 & 5: Chunk the document, generate embeddings, store in pgvector
            chunk_count = rag_service.ingest_document(
                db_doc.id, db_doc.title, db_doc.content_text
            )

            logger.info(
                f"  SEEDED: {filename} -> \"{title}\" "
                f"(doc_id={db_doc.id}, {chunk_count} chunks embedded)"
            )
            seeded_count += 1

    logger.info(
        f"Auto-seed complete: {seeded_count} imported, {skipped_count} skipped"
    )


@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    FastAPI lifespan handler — runs once when the service starts up.

    Startup sequence:
      1. Log configuration for debugging
      2. Create the 'documents' table if it doesn't exist
      3. Auto-seed: load seed documents, chunk them, generate embeddings,
         and store in pgvector so the service is ready to answer queries
         immediately after deployment (no manual curl needed)
    """
    logger.info("=" * 60)
    logger.info("FantaCo HR Policy Search Service — STARTING UP")
    logger.info(f"  DATABASE_URL: {config.DATABASE_URL}")
    logger.info(f"  LLM_API_BASE_URL: {config.LLM_API_BASE_URL}")
    logger.info(f"  LLM_MODEL_NAME: {config.LLM_MODEL_NAME}")
    logger.info(f"  EMBEDDING_MODEL: {config.EMBEDDING_MODEL}")
    logger.info(f"  CHUNK_SIZE: {config.CHUNK_SIZE}")
    logger.info(f"  CHUNK_OVERLAP: {config.CHUNK_OVERLAP}")
    logger.info(f"  COLLECTION_NAME: {config.COLLECTION_NAME}")
    logger.info(f"  PORT: {config.PORT}")
    logger.info("=" * 60)

    # Step 1: Create the 'documents' table if it doesn't exist
    init_db()
    logger.info("Database tables initialized")

    # Step 2: Auto-seed — read seed_documents/, chunk, embed, store in pgvector.
    # This makes the service ready to answer RAG queries immediately after deploy.
    # Idempotent: skips files already imported, safe on pod restarts.
    _auto_seed_documents()

    yield


app = FastAPI(
    title="FantaCo HR Policy Search",
    description="RAG-powered semantic search over HR policy documents",
    version="1.0.0",
    lifespan=lifespan,
)


# --- Health ---

@app.get("/health", response_model=HealthResponse)
def health_check(conn: psycopg.Connection = Depends(get_conn)):
    """Health check with document count."""
    count = document_service.count_documents(conn)
    return HealthResponse(
        status="UP",
        service="fantaco-hr-policy-search",
        document_count=count,
    )


# --- Document CRUD ---

@app.post(f"/api/{DOMAIN}/documents", response_model=DocumentMetadata, status_code=201)
def create_document(doc: DocumentCreate, conn: psycopg.Connection = Depends(get_conn)):
    """Upload a document. Stores the text and generates embeddings."""
    db_doc = document_service.create_document(conn, doc)
    chunk_count = rag_service.ingest_document(db_doc.id, db_doc.title, db_doc.content_text)
    logger.info(f"Created document {db_doc.id} with {chunk_count} chunks")
    return db_doc


@app.get(f"/api/{DOMAIN}/documents", response_model=List[DocumentMetadata])
def list_documents(conn: psycopg.Connection = Depends(get_conn)):
    """List all documents (metadata only, no full text)."""
    return document_service.list_documents(conn)


@app.get(f"/api/{DOMAIN}/documents/{{doc_id}}", response_model=DocumentDetail)
def get_document(doc_id: int, conn: psycopg.Connection = Depends(get_conn)):
    """Get a single document by ID (includes full text)."""
    db_doc = document_service.get_document(conn, doc_id)
    if not db_doc:
        raise HTTPException(status_code=404, detail=f"Document {doc_id} not found")
    return db_doc


@app.put(f"/api/{DOMAIN}/documents/{{doc_id}}", response_model=DocumentMetadata)
def update_document(doc_id: int, update: DocumentUpdate, conn: psycopg.Connection = Depends(get_conn)):
    """Update a document. If content changes, re-chunks and re-embeds."""
    existing = document_service.get_document(conn, doc_id)
    if not existing:
        raise HTTPException(status_code=404, detail=f"Document {doc_id} not found")

    db_doc = document_service.update_document(conn, doc_id, update)

    if update.content is not None:
        rag_service.delete_document_embeddings(doc_id)
        chunk_count = rag_service.ingest_document(
            db_doc.id, db_doc.title, db_doc.content_text
        )
        logger.info(f"Re-embedded document {doc_id} with {chunk_count} chunks")

    return db_doc


@app.delete(f"/api/{DOMAIN}/documents/{{doc_id}}", status_code=204)
def delete_document(doc_id: int, conn: psycopg.Connection = Depends(get_conn)):
    """Delete a document and its embeddings."""
    existing = document_service.get_document(conn, doc_id)
    if not existing:
        raise HTTPException(status_code=404, detail=f"Document {doc_id} not found")

    rag_service.delete_document_embeddings(doc_id)
    document_service.delete_document(conn, doc_id)
    logger.info(f"Deleted document {doc_id}")


# --- RAG Search ---

@app.post(f"/api/{DOMAIN}/search", response_model=SearchResponse)
def search_documents(request: SearchRequest):
    """
    RAG search: takes a natural-language query, retrieves relevant chunks,
    and generates an LLM answer with source citations.
    """
    answer, sources = rag_service.search(request.query, request.top_k)

    return SearchResponse(
        success=True,
        answer=answer,
        sources=[SourceChunk(**s) for s in sources],
        query=request.query,
    )


# --- Seed Documents ---

@app.post(f"/api/{DOMAIN}/seed")
def seed_documents(conn: psycopg.Connection = Depends(get_conn)):
    """
    Seed the database with documents from the seed_documents/ directory.
    Skips documents whose source_filename already exists.
    """
    seed_dir = os.path.join(os.path.dirname(__file__), "seed_documents")
    if not os.path.isdir(seed_dir):
        raise HTTPException(status_code=404, detail="seed_documents/ directory not found")

    seeded = []
    skipped = 0
    for filename in sorted(os.listdir(seed_dir)):
        if not filename.endswith((".txt", ".md")):
            continue

        filepath = os.path.join(seed_dir, filename)
        with open(filepath, "r") as f:
            content = f.read()

        title = os.path.splitext(filename)[0].replace("-", " ").replace("_", " ").title()

        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute("SELECT id FROM documents WHERE source_filename = %s", (filename,))
            if cur.fetchone():
                logger.info(f"Skipping seed document (already exists): {filename}")
                skipped += 1
                continue

        doc = DocumentCreate(
            title=title,
            content=content,
            source_filename=filename,
            category="seed",
        )
        db_doc = document_service.create_document(conn, doc)
        chunk_count = rag_service.ingest_document(db_doc.id, db_doc.title, db_doc.content_text)
        seeded.append({"title": title, "chunks": chunk_count})
        logger.info(f"Seeded: {title} ({chunk_count} chunks)")

    return {"success": True, "seeded": seeded, "count": len(seeded), "skipped": skipped}


# --- Main ---

if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host=config.HOST, port=config.PORT)
