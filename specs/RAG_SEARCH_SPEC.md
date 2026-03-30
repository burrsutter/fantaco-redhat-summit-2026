# RAG Document Search Service — Generative Spec

> **Purpose:** Given a domain name and a set of seed documents, generate a Python/FastAPI service that stores documents, chunks and embeds them with pgvector, and provides RAG-powered semantic search via an OpenAI-compatible LLM. Use this when the domain requires a knowledge base with natural-language search over unstructured text.

---

## When to Use This Spec (vs. Others)

| Use REST_CRUD_SPEC when... | Use REST_ACTION_SPEC when... | Use RAG_SEARCH_SPEC when... |
|----------------------------|------------------------------|------------------------------|
| The entity IS the resource | The endpoint represents an action | The data is unstructured text documents |
| Standard GET/POST/PUT/DELETE on a resource | All endpoints are POST (action invocations) | Users search by asking natural-language questions |
| Response is the entity directly | Response is wrapped: `{ success, message, data }` | Response is an LLM-generated answer with source citations |
| SQL queries on structured columns | Business logic, validation rules, side effects | Semantic similarity search over vector embeddings |
| Java / Spring Boot | Java / Spring Boot | Python / FastAPI |

**Examples of RAG search services:**
- Sales policies: "What is the return policy for defective tacos?"
- HR policies: "How many vacation days do new employees get?"
- Tech support KB: "How do I reset my taco press calibration?"

---

## Input Contract

To generate a service, provide:

| Input | Example | Required |
|-------|---------|----------|
| **Service name** | `fantaco-sales-policy-search` | Yes |
| **Port** | `8090` | Yes |
| **Domain name** | `sales-policy` (used in URL path `/api/sales-policy/...`) | Yes |
| **Database name** | `fantaco_sales_policy` | Yes |
| **Container registry** | `docker.io/burrsutter` | Yes |
| **Embedding model** | `nomic-ai/nomic-embed-text-v1.5` | Yes |
| **LLM config** | API base URL, model name, API key (all env vars) | Yes |
| **Document types** | `.txt`, `.md` | Yes |
| **Chunk size / overlap** | `1000` / `200` | Yes |
| **Seed documents** | List of `.txt`/`.md` files with sample content | Yes |

---

## Technology Stack

| Component | Technology |
|-----------|-----------|
| **Framework** | FastAPI (Python 3.11) |
| **Vector store** | pgvector (PostgreSQL extension) |
| **Embeddings** | sentence-transformers with `nomic-ai/nomic-embed-text-v1.5` |
| **RAG pipeline** | LangChain (`langchain`, `langchain-community`, `langchain-postgres`) |
| **LLM access** | OpenAI-compatible API via `langchain-openai` (configurable endpoint, model, API key) |
| **Database driver** | psycopg 3 (`psycopg[binary]`) + `psycopg_pool` for document metadata; pgvector for embeddings (no ORM) |
| **HTTP framework** | FastAPI with uvicorn |

---

## Naive RAG Scope

This spec is intentionally limited to **naive RAG**. Implementations generated from this spec must keep the retrieval and generation pipeline simple and predictable.

### In Scope

- Store raw documents in PostgreSQL
- Split documents into fixed character-based chunks
- Generate one embedding per chunk using a single embedding model
- Store embeddings in pgvector through LangChain PGVector
- Retrieve the top `k` most similar chunks for a query
- Build one prompt from those retrieved chunks
- Generate one final answer from the LLM
- Return the answer and the retrieved source chunks

### Explicit Non-Goals

- No reranking
- No hybrid keyword + vector search
- No metadata filtering during search
- No conversation memory
- No multi-step retrieval
- No query rewriting
- No agent/tool use
- No document parsing beyond plain `.txt` and `.md`

If a future service needs any of the above, it should extend this spec explicitly rather than changing the baseline behavior.

---

## Database Schema

### `documents` table (application-managed)

```sql
CREATE TABLE IF NOT EXISTS documents (
    id SERIAL PRIMARY KEY,
    title VARCHAR(500) NOT NULL,
    source_filename VARCHAR(500),
    content_text TEXT NOT NULL,
    category VARCHAR(200),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

### pgvector tables (LangChain-managed)

LangChain's PGVector integration automatically creates and manages:
- `langchain_pg_collection` — collection registry
- `langchain_pg_embedding` — vector embeddings with metadata

These tables are created automatically when the first embedding is stored. The application does **not** define or migrate them.

### Required chunk metadata

Each embedded chunk must be stored with metadata containing at least:

```json
{
  "document_id": 123,
  "title": "Return Policy v2.1",
  "source_filename": "return-policy-v2.md",
  "category": "returns",
  "chunk_index": 0
}
```

`document_id` is required for update/delete cleanup. `chunk_index` is required so retrieved chunks can be returned in a stable and debuggable way.

---

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/health` | Health check with document count |
| `POST` | `/api/{domain}/documents` | Upload a document (JSON with title + content) |
| `GET` | `/api/{domain}/documents` | List all documents (metadata only, no full text) |
| `GET` | `/api/{domain}/documents/{id}` | Get document by ID (full text) |
| `PUT` | `/api/{domain}/documents/{id}` | Update a document (re-chunks and re-embeds) |
| `DELETE` | `/api/{domain}/documents/{id}` | Delete document and its embeddings |
| `POST` | `/api/{domain}/search` | RAG search: query → LLM answer + source chunks |
| `POST` | `/api/{domain}/seed` | Seed documents from the `seed_documents/` directory |

---

## API Behavior Rules

### Common status codes

- `200 OK` for successful reads, updates, deletes, searches, and seed runs
- `201 Created` for successful document creation
- `400 Bad Request` for invalid input such as empty `title`, empty `content`, empty `query`, invalid `top_k`, or invalid JSON
- `404 Not Found` when a requested document ID does not exist
- `500 Internal Server Error` for unexpected storage, embedding, or LLM failures

### Document create/update rules

- `title` must be non-empty after trimming
- `content` must be non-empty after trimming
- `category` and `source_filename` are optional
- `PUT /documents/{id}` is a **partial update**
- If `content` changes, the service must delete old embeddings for that document and regenerate them
- If only metadata fields change, the raw document row must be updated and the service may skip re-embedding

### Seed rules

- The seed endpoint reads all supported files from `seed_documents/`
- Supported file types are only `.txt` and `.md`
- Seeding is **idempotent by filename**
- If a seed file has already been imported with the same `source_filename`, the endpoint must skip it rather than creating a duplicate
- The seed response should report how many documents were created and how many were skipped

### Search rules

- `query` must be non-empty after trimming
- `top_k` defaults to `5`
- `top_k` maximum is `10`
- The service must retrieve vector matches first, and call the LLM whenever one or more chunks are returned

---

## Search Endpoint Detail

### `POST /api/{domain}/search`

**Request:**
```json
{
  "query": "What is the return policy for defective tacos?",
  "top_k": 5
}
```

**Response:**
```json
{
  "success": true,
  "answer": "According to the sales policy, defective tacos can be returned within 30 days of purchase for a full refund. The customer must provide proof of purchase and the defective product must be returned in its original packaging.",
  "sources": [
    {
      "document_id": 1,
      "title": "Return Policy v2.1",
      "chunk_text": "Defective products may be returned within 30 days of purchase...",
      "similarity_score": 0.92
    },
    {
      "document_id": 1,
      "title": "Return Policy v2.1",
      "chunk_text": "All returns require proof of purchase (receipt or order number)...",
      "similarity_score": 0.87
    }
  ],
  "query": "What is the return policy for defective tacos?"
}
```

**When no relevant documents are found:**
```json
{
  "success": true,
  "answer": "I don't have enough information in the knowledge base to answer that question.",
  "sources": [],
  "query": "What is the weather like today?"
}
```

### Relevance rule for naive RAG

To keep behavior simple and deterministic, the implementation must apply this rule:

1. Run vector similarity search for the requested `top_k`
2. If zero chunks are returned, do **not** call the LLM
3. If chunks are returned, send them directly to the LLM as context

There is **no similarity threshold**, reranking step, or secondary retrieval pass in the naive implementation.

---

## Document Ingestion Flow

1. Receive document via JSON body (`title`, `content`, optional `category`, `source_filename`)
2. Store raw document in `documents` table (plain SQL via psycopg)
3. Split content into chunks using LangChain's `RecursiveCharacterTextSplitter` (configurable `chunk_size` / `chunk_overlap`)
4. Generate embeddings using sentence-transformers (`nomic-ai/nomic-embed-text-v1.5`)
5. Store embeddings in pgvector via LangChain's `PGVector`, with required metadata including `document_id`, `title`, `source_filename`, `category`, and `chunk_index`

### Update Flow
1. Delete existing embeddings for the document (by `document_id` in metadata)
2. Update document text in `documents` table
3. Re-chunk and re-embed (steps 3-5 above)

### Delete Flow
1. Delete embeddings for the document (by `document_id` in metadata)
2. Delete document row from `documents` table

---

## RAG Search Flow

1. Receive query string and optional `top_k` (default 5, max 10)
2. Embed query using same sentence-transformers model
3. Similarity search against pgvector via LangChain's `PGVector.similarity_search_with_score` (top_k results)
4. If no chunks are returned, skip the LLM and return the standard "not enough information" answer with empty `sources`
5. Build one prompt with the retrieved chunks as context:
   ```
   Use the following context to answer the question. If the context doesn't
   contain enough information to answer, say so clearly.

   Context:
   ---
   {chunk_1_text}
   ---
   {chunk_2_text}
   ---
   ...

   Question: {user_query}
   ```
6. Send the prompt to the LLM via OpenAI-compatible API (`langchain-openai` `ChatOpenAI`)
7. Return answer + source chunks with similarity scores

The implementation must not add conversational memory, query rewriting, reranking, or follow-up retrieval steps.

---

## Environment Variables

| Variable | Example | Description |
|----------|---------|-------------|
| `DATABASE_URL` | `postgresql://user:pass@host:5432/db` | PostgreSQL connection (psycopg + pgvector) |
| `LLM_API_BASE_URL` | `http://litellm:4000/v1` | OpenAI-compatible endpoint |
| `LLM_MODEL_NAME` | `qwen3-14b` | Model to use for RAG answers |
| `LLM_API_KEY` | `sk-...` | API key for LLM |
| `EMBEDDING_MODEL` | `nomic-ai/nomic-embed-text-v1.5` | Sentence-transformers model |
| `CHUNK_SIZE` | `1000` | Characters per chunk |
| `CHUNK_OVERLAP` | `200` | Overlap between chunks |
| `COLLECTION_NAME` | `sales_policy_docs` | PGVector collection name (unique per instance) |

---

## Startup Requirements

On application startup, the service must:

1. Create the `documents` table if it does not exist
2. Initialize the psycopg connection pool
3. Verify that the configured embedding model can be loaded
4. Fail fast if `DATABASE_URL`, `LLM_API_BASE_URL`, `LLM_MODEL_NAME`, or `LLM_API_KEY` are missing

The service may rely on the pgvector-enabled PostgreSQL image to provide the `vector` extension, but startup should fail clearly if vector storage is unavailable.

---

## Output Contract (File Tree)

The generator produces these exact files:

```
fantaco-<domain>-search/
├── app.py                          # FastAPI application with all endpoints
├── config.py                       # Environment variable configuration
├── models.py                       # Plain dataclasses for Document
├── schemas.py                      # Pydantic request/response models
├── document_service.py             # CRUD operations (plain SQL via psycopg)
├── rag_service.py                  # Embedding, chunking, RAG search
├── database.py                     # psycopg connection pool setup
├── requirements.txt                # Python dependencies with pinned versions
├── Dockerfile                      # Container image (python:3.11-slim)
├── seed_documents/                 # Sample .txt/.md documents for seeding
│   ├── doc1.md
│   ├── doc2.txt
│   └── ...
└── deployment/
    └── kubernetes/
        ├── deployment.yaml         # Application deployment
        ├── service.yaml            # ClusterIP service
        ├── route.yaml              # OpenShift route (edge TLS)
        ├── configmap.yaml          # Non-secret configuration
        ├── secret.yaml             # API keys (placeholder)
        └── postgres/
            ├── deployment.yaml     # PostgreSQL 15 + pgvector
            └── service.yaml        # PostgreSQL ClusterIP service
```

---

## Kubernetes Conventions

Follow COMMON_SPECS.md, with these RAG-specific additions:

| Convention | Value |
|------------|-------|
| Image naming | `fantaco-<domain>-search` (e.g., `fantaco-sales-policy-search`) |
| Registry | `docker.io/burrsutter` |
| Build | `podman build --arch amd64 --os linux` |
| PostgreSQL base | `pgvector/pgvector:pg15` (pgvector-enabled, not plain PostgreSQL) |
| Resource limits | 128Mi/100m requests, 256Mi/500m limits (same as MCP servers) |
| Health probe | `GET /health` |
| Service naming | `fantaco-<domain>-search-service` |
| PostgreSQL service | `fantaco-<domain>-search-db` |

---

## Port Assignments

### RAG Search Services (8090-8099)

| Port | Service |
|------|---------|
| 8090 | fantaco-sales-policy-search |
| 8091 | fantaco-hr-policy-search |
| 8092 | fantaco-techsupport-search |
| 8093+ | (next RAG search service) |

### PostgreSQL (5432 internal, different service names)

Each RAG service gets its own PostgreSQL instance with pgvector. All use port 5432 internally, differentiated by service name.

---

## Three Intended Instances

| Instance | Service Name | Port | Database | Domain | Collection |
|----------|-------------|------|----------|--------|------------|
| Sales Policies | `fantaco-sales-policy-search` | 8090 | `fantaco_sales_policy` | `sales-policy` | `sales_policy_docs` |
| HR Policies | `fantaco-hr-policy-search` | 8091 | `fantaco_hr_policy` | `hr-policy` | `hr_policy_docs` |
| Tech Support KB | `fantaco-techsupport-search` | 8092 | `fantaco_techsupport` | `techsupport` | `techsupport_docs` |

*(The spec is generic — these are just the planned instantiations)*

---

## Complete Worked Example: Sales Policy Search Service

**Input:**
- Service name: `fantaco-sales-policy-search`
- Port: `8090`
- Domain name: `sales-policy`
- Database name: `fantaco_sales_policy`
- Registry: `docker.io/burrsutter`
- Embedding model: `nomic-ai/nomic-embed-text-v1.5`
- Chunk size: `1000`, overlap: `200`
- Collection name: `sales_policy_docs`

---

### Generated File: `fantaco-sales-policy-search/config.py`

```python
import os

# Database
DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "postgresql://rag_user:rag_pass@localhost:5432/fantaco_sales_policy"
)

# LLM Configuration
LLM_API_BASE_URL = os.getenv("LLM_API_BASE_URL", "http://localhost:4000/v1")
LLM_MODEL_NAME = os.getenv("LLM_MODEL_NAME", "qwen3-14b")
LLM_API_KEY = os.getenv("LLM_API_KEY", "sk-placeholder")

# Embedding Configuration
EMBEDDING_MODEL = os.getenv("EMBEDDING_MODEL", "nomic-ai/nomic-embed-text-v1.5")

# Chunking Configuration
CHUNK_SIZE = int(os.getenv("CHUNK_SIZE", "1000"))
CHUNK_OVERLAP = int(os.getenv("CHUNK_OVERLAP", "200"))

# PGVector Collection
COLLECTION_NAME = os.getenv("COLLECTION_NAME", "sales_policy_docs")

# Service
PORT = int(os.getenv("PORT", "8090"))
HOST = os.getenv("HOST", "0.0.0.0")
```

---

### Generated File: `fantaco-sales-policy-search/database.py`

```python
import psycopg
from psycopg_pool import ConnectionPool
from config import DATABASE_URL

pool = ConnectionPool(conninfo=DATABASE_URL, min_size=2, max_size=10)

CREATE_DOCUMENTS_TABLE = """
CREATE TABLE IF NOT EXISTS documents (
    id SERIAL PRIMARY KEY,
    title VARCHAR(500) NOT NULL,
    source_filename VARCHAR(500),
    content_text TEXT NOT NULL,
    category VARCHAR(200),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
"""


def get_conn():
    """FastAPI dependency that provides a psycopg connection from the pool."""
    with pool.connection() as conn:
        yield conn


def init_db():
    """Create the documents table if it does not exist."""
    with pool.connection() as conn:
        conn.execute(CREATE_DOCUMENTS_TABLE)
        conn.commit()
```

---

### Generated File: `fantaco-sales-policy-search/models.py`

```python
from dataclasses import dataclass, field
from datetime import datetime
from typing import Optional


@dataclass
class Document:
    id: int
    title: str
    content_text: str
    source_filename: Optional[str] = None
    category: Optional[str] = None
    created_at: datetime = field(default_factory=datetime.utcnow)
    updated_at: datetime = field(default_factory=datetime.utcnow)
```

---

### Generated File: `fantaco-sales-policy-search/schemas.py`

```python
from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime


# --- Document Schemas ---

class DocumentCreate(BaseModel):
    title: str
    content: str
    category: Optional[str] = None
    source_filename: Optional[str] = None


class DocumentUpdate(BaseModel):
    title: Optional[str] = None
    content: Optional[str] = None
    category: Optional[str] = None


class DocumentMetadata(BaseModel):
    id: int
    title: str
    source_filename: Optional[str] = None
    category: Optional[str] = None
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class DocumentDetail(DocumentMetadata):
    content_text: str


# --- Search Schemas ---

class SearchRequest(BaseModel):
    query: str
    top_k: int = 5


class SourceChunk(BaseModel):
    document_id: Optional[int] = None
    title: Optional[str] = None
    chunk_text: str
    similarity_score: float


class SearchResponse(BaseModel):
    success: bool
    answer: str
    sources: List[SourceChunk]
    query: str


# --- Health ---

class HealthResponse(BaseModel):
    status: str
    service: str
    document_count: int
```

---

### Generated File: `fantaco-sales-policy-search/document_service.py`

```python
from psycopg import Connection
from psycopg.rows import dict_row
from models import Document
from schemas import DocumentCreate, DocumentUpdate
from typing import List, Optional


def _row_to_document(row: dict) -> Document:
    """Convert a database row dict to a Document dataclass."""
    return Document(**row)


def create_document(conn: Connection, doc: DocumentCreate) -> Document:
    """Create a new document record."""
    with conn.cursor(row_factory=dict_row) as cur:
        cur.execute(
            """INSERT INTO documents (title, content_text, category, source_filename)
               VALUES (%(title)s, %(content)s, %(category)s, %(source_filename)s)
               RETURNING *""",
            {
                "title": doc.title,
                "content": doc.content,
                "category": doc.category,
                "source_filename": doc.source_filename,
            },
        )
        row = cur.fetchone()
    conn.commit()
    return _row_to_document(row)


def get_document(conn: Connection, doc_id: int) -> Optional[Document]:
    """Get a document by ID."""
    with conn.cursor(row_factory=dict_row) as cur:
        cur.execute("SELECT * FROM documents WHERE id = %s", (doc_id,))
        row = cur.fetchone()
    return _row_to_document(row) if row else None


def list_documents(conn: Connection) -> List[Document]:
    """List all documents (ordered by created_at desc)."""
    with conn.cursor(row_factory=dict_row) as cur:
        cur.execute("SELECT * FROM documents ORDER BY created_at DESC")
        rows = cur.fetchall()
    return [_row_to_document(r) for r in rows]


def update_document(conn: Connection, doc_id: int, update: DocumentUpdate) -> Optional[Document]:
    """Update a document's fields."""
    sets, params = [], {"doc_id": doc_id}
    if update.title is not None:
        sets.append("title = %(title)s")
        params["title"] = update.title
    if update.content is not None:
        sets.append("content_text = %(content)s")
        params["content"] = update.content
    if update.category is not None:
        sets.append("category = %(category)s")
        params["category"] = update.category
    if not sets:
        return get_document(conn, doc_id)

    sets.append("updated_at = CURRENT_TIMESTAMP")
    sql = f"UPDATE documents SET {', '.join(sets)} WHERE id = %(doc_id)s RETURNING *"
    with conn.cursor(row_factory=dict_row) as cur:
        cur.execute(sql, params)
        row = cur.fetchone()
    conn.commit()
    return _row_to_document(row) if row else None


def delete_document(conn: Connection, doc_id: int) -> bool:
    """Delete a document by ID. Returns True if deleted."""
    with conn.cursor() as cur:
        cur.execute("DELETE FROM documents WHERE id = %s", (doc_id,))
        deleted = cur.rowcount > 0
    conn.commit()
    return deleted


def count_documents(conn: Connection) -> int:
    """Count total documents."""
    with conn.cursor() as cur:
        cur.execute("SELECT COUNT(*) FROM documents")
        return cur.fetchone()[0]
```

---

### Generated File: `fantaco-sales-policy-search/rag_service.py`

```python
import logging
from typing import List, Tuple
from langchain_text_splitters import RecursiveCharacterTextSplitter
from langchain_huggingface import HuggingFaceEmbeddings
from langchain_postgres import PGVector
from langchain_openai import ChatOpenAI
from langchain_core.documents import Document as LCDocument
from config import (
    DATABASE_URL,
    LLM_API_BASE_URL,
    LLM_MODEL_NAME,
    LLM_API_KEY,
    EMBEDDING_MODEL,
    CHUNK_SIZE,
    CHUNK_OVERLAP,
    COLLECTION_NAME,
)

logger = logging.getLogger(__name__)

# --- Embedding Model (loaded once) ---

_embeddings = None


def get_embeddings() -> HuggingFaceEmbeddings:
    """Get or create the embedding model (singleton)."""
    global _embeddings
    if _embeddings is None:
        logger.info(f"Loading embedding model: {EMBEDDING_MODEL}")
        _embeddings = HuggingFaceEmbeddings(
            model_name=EMBEDDING_MODEL,
            model_kwargs={"trust_remote_code": True},
        )
        logger.info("Embedding model loaded successfully")
    return _embeddings


# --- Vector Store ---

_vector_store = None


def get_vector_store() -> PGVector:
    """Get or create the PGVector store (singleton)."""
    global _vector_store
    if _vector_store is None:
        _vector_store = PGVector(
            embeddings=get_embeddings(),
            collection_name=COLLECTION_NAME,
            connection=DATABASE_URL,
            use_jsonb=True,
        )
    return _vector_store


# --- Text Splitter ---

def get_text_splitter() -> RecursiveCharacterTextSplitter:
    """Create a text splitter with configured chunk size and overlap."""
    return RecursiveCharacterTextSplitter(
        chunk_size=CHUNK_SIZE,
        chunk_overlap=CHUNK_OVERLAP,
        length_function=len,
        separators=["\n\n", "\n", ". ", " ", ""],
    )


# --- LLM ---

def get_llm() -> ChatOpenAI:
    """Create the LLM client for RAG answer generation."""
    return ChatOpenAI(
        base_url=LLM_API_BASE_URL,
        model=LLM_MODEL_NAME,
        api_key=LLM_API_KEY,
        temperature=0.1,
    )


# --- Ingestion ---

def ingest_document(document_id: int, title: str, content: str) -> int:
    """
    Chunk a document and store embeddings in pgvector.

    Returns the number of chunks created.
    """
    splitter = get_text_splitter()
    chunks = splitter.split_text(content)

    lc_docs = [
        LCDocument(
            page_content=chunk,
            metadata={
                "document_id": document_id,
                "title": title,
                "chunk_index": i,
            },
        )
        for i, chunk in enumerate(chunks)
    ]

    store = get_vector_store()
    store.add_documents(lc_docs)

    logger.info(f"Ingested document {document_id} ({title}): {len(chunks)} chunks")
    return len(chunks)


def delete_document_embeddings(document_id: int) -> None:
    """Delete all embeddings associated with a document ID."""
    store = get_vector_store()
    # Get all docs matching this document_id and delete them
    try:
        results = store.similarity_search(
            query="",
            k=10000,
            filter={"document_id": document_id},
        )
        if results:
            ids_to_delete = [doc.metadata.get("id") for doc in results if doc.metadata.get("id")]
            if ids_to_delete:
                store.delete(ids=ids_to_delete)
                logger.info(f"Deleted {len(ids_to_delete)} embeddings for document {document_id}")
    except Exception as e:
        logger.warning(f"Filter-based delete failed, using SQL fallback: {e}")
        import psycopg
        with psycopg.connect(DATABASE_URL) as conn:
            conn.execute(
                "DELETE FROM langchain_pg_embedding "
                "WHERE cmetadata->>'document_id' = %s",
                (str(document_id),),
            )
            conn.commit()
        logger.info(f"Deleted embeddings for document {document_id} via SQL")


# --- RAG Search ---

RAG_PROMPT_TEMPLATE = """Use the following context to answer the question. If the context doesn't contain enough information to answer, say so clearly. Do not make up information that is not supported by the context.

Context:
{context}

Question: {question}"""


def search(query: str, top_k: int = 5) -> Tuple[str, List[dict]]:
    """
    Perform RAG search: embed query, find similar chunks, generate answer.

    Returns:
        Tuple of (answer_text, list_of_source_dicts)
    """
    store = get_vector_store()

    # Similarity search with scores
    results_with_scores = store.similarity_search_with_score(query, k=top_k)

    if not results_with_scores:
        return (
            "I don't have enough information in the knowledge base to answer that question.",
            [],
        )

    # Build context from retrieved chunks
    context_parts = []
    sources = []
    for doc, score in results_with_scores:
        context_parts.append(doc.page_content)
        sources.append({
            "document_id": doc.metadata.get("document_id"),
            "title": doc.metadata.get("title"),
            "chunk_text": doc.page_content,
            "similarity_score": round(1 - score, 4) if score <= 1 else round(score, 4),
        })

    context = "\n---\n".join(context_parts)

    # Build prompt and call LLM
    prompt = RAG_PROMPT_TEMPLATE.format(context=context, question=query)

    llm = get_llm()
    response = llm.invoke(prompt)
    answer = response.content

    return answer, sources
```

---

### Generated File: `fantaco-sales-policy-search/app.py`

```python
#!/usr/bin/env python3
"""
FantaCo Sales Policy Search — RAG-powered document search service.

Provides document management and semantic search over sales policy documents
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

DOMAIN = "sales-policy"


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Initialize database tables on startup."""
    logger.info("=" * 60)
    logger.info("FantaCo Sales Policy Search Service")
    logger.info(f"  DATABASE_URL: {config.DATABASE_URL}")
    logger.info(f"  LLM_API_BASE_URL: {config.LLM_API_BASE_URL}")
    logger.info(f"  LLM_MODEL_NAME: {config.LLM_MODEL_NAME}")
    logger.info(f"  EMBEDDING_MODEL: {config.EMBEDDING_MODEL}")
    logger.info(f"  CHUNK_SIZE: {config.CHUNK_SIZE}")
    logger.info(f"  CHUNK_OVERLAP: {config.CHUNK_OVERLAP}")
    logger.info(f"  COLLECTION_NAME: {config.COLLECTION_NAME}")
    logger.info(f"  PORT: {config.PORT}")
    logger.info("=" * 60)
    init_db()
    logger.info("Database tables initialized")
    yield


app = FastAPI(
    title="FantaCo Sales Policy Search",
    description="RAG-powered semantic search over sales policy documents",
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
        service="fantaco-sales-policy-search",
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
    Skips documents whose titles already exist.
    """
    seed_dir = os.path.join(os.path.dirname(__file__), "seed_documents")
    if not os.path.isdir(seed_dir):
        raise HTTPException(status_code=404, detail="seed_documents/ directory not found")

    seeded = []
    for filename in sorted(os.listdir(seed_dir)):
        if not filename.endswith((".txt", ".md")):
            continue

        filepath = os.path.join(seed_dir, filename)
        with open(filepath, "r") as f:
            content = f.read()

        title = os.path.splitext(filename)[0].replace("-", " ").replace("_", " ").title()

        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute("SELECT id FROM documents WHERE title = %s", (title,))
            if cur.fetchone():
                logger.info(f"Skipping seed document (already exists): {title}")
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

    return {"success": True, "seeded": seeded, "count": len(seeded)}


# --- Main ---

if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host=config.HOST, port=config.PORT)
```

---

### Generated File: `fantaco-sales-policy-search/requirements.txt`

```
fastapi==0.115.6
uvicorn==0.34.0
psycopg[binary]==3.2.4
psycopg-pool==3.2.4
langchain==0.3.14
langchain-community==0.3.14
langchain-openai==0.3.0
langchain-postgres==0.0.13
langchain-huggingface==0.1.2
langchain-text-splitters==0.3.4
sentence-transformers==3.3.1
pgvector==0.3.6
pydantic==2.10.4
```

---

### Generated File: `fantaco-sales-policy-search/Dockerfile`

```dockerfile
FROM python:3.11-slim

WORKDIR /app

# Install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Pre-download the embedding model at build time (avoids runtime download)
RUN python -c "from sentence_transformers import SentenceTransformer; SentenceTransformer('nomic-ai/nomic-embed-text-v1.5', trust_remote_code=True)"

# Copy application
COPY . .

# Expose port
EXPOSE 8090

# Run the application
CMD ["python", "app.py"]
```

---

### Generated File: `fantaco-sales-policy-search/seed_documents/return-policy.md`

```markdown
# FantaCo Return Policy

## Standard Returns

Customers may return any unopened FantaCo product within 30 days of purchase for a full refund. The original receipt or order confirmation email is required for all returns.

## Defective Products

Defective products may be returned within 90 days of purchase for a full refund or replacement. A product is considered defective if it arrives damaged, has manufacturing defects, or does not match the product description. Customers do not need original packaging for defective returns, but must provide proof of purchase.

## Perishable Items

Taco shells, tortillas, and other perishable items must be returned within 7 days of purchase. Perishable returns require the original packaging and proof of purchase. If a perishable item arrives spoiled or past its expiration date, contact customer service immediately for a full refund — no return shipment necessary.

## Refund Processing

Refunds are processed within 5-7 business days of receiving the returned product. Refunds are issued to the original payment method. Shipping costs are non-refundable unless the return is due to a FantaCo error or defective product.

## Bulk Order Returns

For orders exceeding $500 or 100 units, returns must be coordinated with the FantaCo Sales team directly. A restocking fee of 15% applies to bulk returns of non-defective products. Contact your assigned sales representative or email bulk-returns@fantaco.com.
```

---

### Generated File: `fantaco-sales-policy-search/seed_documents/pricing-and-discounts.md`

```markdown
# FantaCo Pricing and Discount Policy

## Standard Pricing

All FantaCo products are priced according to the current catalog. Prices are subject to change with 30 days' written notice to active customers. Price increases do not apply to orders already confirmed.

## Volume Discounts

FantaCo offers tiered volume discounts for qualifying orders:

- Orders of 100-499 units: 5% discount
- Orders of 500-999 units: 10% discount
- Orders of 1,000-4,999 units: 15% discount
- Orders of 5,000+ units: 20% discount

Volume discounts are calculated per order, not across multiple orders. Discounts apply to the base product price before tax and shipping.

## Loyalty Program

Customers who have been active for 12+ months and have placed 10+ orders qualify for the FantaCo Loyalty Program. Loyalty members receive an additional 3% discount on all orders, stackable with volume discounts (up to a maximum combined discount of 25%).

## Promotional Pricing

Seasonal and promotional pricing may be offered at FantaCo's discretion. Promotional prices cannot be combined with volume discounts or loyalty discounts. Promotional pricing is valid only during the stated promotion period.

## Payment Terms

Standard payment terms are Net 30 for approved credit accounts. New customers must prepay for their first three orders. A 2% early payment discount is available for invoices paid within 10 days. Late payments incur a 1.5% monthly finance charge.
```

---

### Generated File: `fantaco-sales-policy-search/seed_documents/shipping-policy.txt`

```
FantaCo Shipping Policy
========================

Standard Shipping
-----------------
All domestic orders are shipped within 2-3 business days of order confirmation.
Standard shipping typically takes 5-7 business days for delivery. Free standard
shipping is available on orders over $200.

Expedited Shipping
------------------
Expedited shipping (2-3 business day delivery) is available for an additional
fee of $15 per order or 5% of the order total, whichever is greater. Expedited
orders placed before 2:00 PM EST are processed the same business day.

Overnight Shipping
------------------
Overnight shipping is available for orders placed before 12:00 PM EST. Overnight
shipping costs $35 per order or 10% of the order total, whichever is greater.
Overnight shipping is not available to all regions — check with customer service.

International Shipping
----------------------
FantaCo ships to select international destinations. International orders are
subject to additional customs duties and taxes, which are the responsibility
of the customer. International shipping times vary from 7-21 business days
depending on the destination. International orders over $1,000 require
advance payment via wire transfer.

Damaged Shipments
-----------------
If a shipment arrives damaged, customers must report the damage within 48 hours
of delivery. Take photos of the damaged packaging and products. FantaCo will
arrange a replacement shipment at no additional cost. The damaged products do
not need to be returned unless specifically requested.

Order Tracking
--------------
All orders include tracking information sent via email within 24 hours of
shipment. Customers can track their orders on the FantaCo website or by
contacting customer service with their order number.
```

---

### Generated File: `fantaco-sales-policy-search/seed_documents/warranty-policy.txt`

```
FantaCo Product Warranty Policy
================================

Standard Warranty
-----------------
All FantaCo taco press machines and commercial equipment carry a standard
12-month warranty from the date of purchase. This warranty covers defects in
materials and workmanship under normal use conditions.

What Is Covered
---------------
- Manufacturing defects in mechanical components
- Electrical failures under normal operating conditions
- Premature wear of heating elements (failure within warranty period)
- Software/firmware defects in digital control panels

What Is Not Covered
-------------------
- Damage caused by misuse, abuse, or unauthorized modifications
- Normal wear and tear (gaskets, seals, non-stick coatings)
- Damage caused by power surges or improper electrical connections
- Consumable parts (filters, lubricants, cleaning supplies)
- Cosmetic damage that does not affect functionality

Extended Warranty
-----------------
Customers may purchase an extended warranty at the time of equipment purchase.
The extended warranty adds an additional 12 months (total 24 months) of coverage
for 10% of the original equipment purchase price. Extended warranties must be
purchased within 30 days of the original equipment purchase.

Warranty Claims Process
-----------------------
1. Contact FantaCo customer service with your order number and description
   of the issue.
2. A technician will attempt to troubleshoot the issue remotely.
3. If the issue cannot be resolved remotely, FantaCo will issue an RMA
   (Return Merchandise Authorization) number.
4. Ship the product to the designated FantaCo service center (prepaid
   shipping label provided for warranty claims).
5. Repairs or replacements are typically completed within 10 business days.
6. If a product cannot be repaired, FantaCo will provide a replacement of
   equal or greater value.
```

---

### Generated File: `fantaco-sales-policy-search/deployment/kubernetes/configmap.yaml`

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: fantaco-sales-policy-search-config
  labels:
    app: fantaco-sales-policy-search
data:
  DATABASE_URL: "postgresql://rag_user:rag_pass@fantaco-sales-policy-search-db:5432/fantaco_sales_policy"
  LLM_API_BASE_URL: "http://litellm-service:4000/v1"
  LLM_MODEL_NAME: "qwen3-14b"
  EMBEDDING_MODEL: "nomic-ai/nomic-embed-text-v1.5"
  CHUNK_SIZE: "1000"
  CHUNK_OVERLAP: "200"
  COLLECTION_NAME: "sales_policy_docs"
  PORT: "8090"
  HOST: "0.0.0.0"
```

---

### Generated File: `fantaco-sales-policy-search/deployment/kubernetes/secret.yaml`

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: fantaco-sales-policy-search-secret
  labels:
    app: fantaco-sales-policy-search
type: Opaque
stringData:
  LLM_API_KEY: "sk-placeholder-change-me"
```

---

### Generated File: `fantaco-sales-policy-search/deployment/kubernetes/deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fantaco-sales-policy-search
  labels:
    app: fantaco-sales-policy-search
spec:
  replicas: 1
  selector:
    matchLabels:
      app: fantaco-sales-policy-search
  template:
    metadata:
      labels:
        app: fantaco-sales-policy-search
    spec:
      containers:
      - name: rag-search
        image: docker.io/burrsutter/fantaco-sales-policy-search:1.0.0
        imagePullPolicy: Always
        ports:
        - containerPort: 8090
          name: http
          protocol: TCP
        envFrom:
        - configMapRef:
            name: fantaco-sales-policy-search-config
        - secretRef:
            name: fantaco-sales-policy-search-secret
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "500m"
        livenessProbe:
          httpGet:
            path: /health
            port: 8090
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /health
            port: 8090
          initialDelaySeconds: 15
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 3
```

---

### Generated File: `fantaco-sales-policy-search/deployment/kubernetes/service.yaml`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: fantaco-sales-policy-search-service
  labels:
    app: fantaco-sales-policy-search
spec:
  type: ClusterIP
  selector:
    app: fantaco-sales-policy-search
  ports:
  - port: 8090
    targetPort: 8090
    protocol: TCP
    name: http
```

---

### Generated File: `fantaco-sales-policy-search/deployment/kubernetes/route.yaml`

```yaml
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: fantaco-sales-policy-search-route
  labels:
    app: fantaco-sales-policy-search
spec:
  to:
    kind: Service
    name: fantaco-sales-policy-search-service
    weight: 100
  port:
    targetPort: http
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
```

---

### Generated File: `fantaco-sales-policy-search/deployment/kubernetes/postgres/deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fantaco-sales-policy-search-db
  labels:
    app: fantaco-sales-policy-search-db
spec:
  replicas: 1
  selector:
    matchLabels:
      app: fantaco-sales-policy-search-db
  template:
    metadata:
      labels:
        app: fantaco-sales-policy-search-db
    spec:
      containers:
      - name: postgresql
        image: pgvector/pgvector:pg15
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 5432
          protocol: TCP
        env:
        - name: POSTGRES_DB
          value: fantaco_sales_policy
        - name: POSTGRES_USER
          value: rag_user
        - name: POSTGRES_PASSWORD
          value: rag_pass
        resources:
          requests:
            memory: "256Mi"
            cpu: "100m"
          limits:
            memory: "512Mi"
            cpu: "500m"
        volumeMounts:
        - name: pgdata
          mountPath: /var/lib/postgresql/data
      volumes:
      - name: pgdata
        emptyDir: {}
```

---

### Generated File: `fantaco-sales-policy-search/deployment/kubernetes/postgres/service.yaml`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: fantaco-sales-policy-search-db
  labels:
    app: fantaco-sales-policy-search-db
spec:
  type: ClusterIP
  selector:
    app: fantaco-sales-policy-search-db
  ports:
  - port: 5432
    targetPort: 5432
    protocol: TCP
    name: postgresql
```

---

## Build & Deploy Commands

```bash
# Build container image
cd fantaco-sales-policy-search
podman build --arch amd64 --os linux -t docker.io/burrsutter/fantaco-sales-policy-search:1.0.0 .
podman push docker.io/burrsutter/fantaco-sales-policy-search:1.0.0

# Deploy to OpenShift
oc apply -f deployment/kubernetes/postgres/
oc apply -f deployment/kubernetes/

# Seed documents (after deployment)
curl -X POST http://<route>/api/sales-policy/seed

# Test search
curl -X POST http://<route>/api/sales-policy/search \
  -H "Content-Type: application/json" \
  -d '{"query": "What is the return policy for defective tacos?", "top_k": 5}'
```

---

## Local Development

```bash
# Start PostgreSQL with pgvector locally
podman run -d --name pgvector-local \
  -e POSTGRES_DB=fantaco_sales_policy \
  -e POSTGRES_USER=rag_user \
  -e POSTGRES_PASSWORD=rag_pass \
  -p 5432:5432 \
  pgvector/pgvector:pg15

# Install dependencies
cd fantaco-sales-policy-search
pip install -r requirements.txt

# Set environment variables
export DATABASE_URL="postgresql://rag_user:rag_pass@localhost:5432/fantaco_sales_policy"
export LLM_API_BASE_URL="http://localhost:4000/v1"
export LLM_MODEL_NAME="qwen3-14b"
export LLM_API_KEY="sk-your-key"

# Run the service
python app.py

# Seed documents
curl -X POST http://localhost:8090/api/sales-policy/seed

# Test search
curl -X POST http://localhost:8090/api/sales-policy/search \
  -H "Content-Type: application/json" \
  -d '{"query": "What discounts are available for large orders?"}'
```

---

## Template Rules (How to Generalize)

To generate a new RAG search service from this spec, replace these values:

| Placeholder | Sales Policy Example | What to Change |
|------------|---------------------|----------------|
| `{service_name}` | `fantaco-sales-policy-search` | Full service name |
| `{domain}` | `sales-policy` | URL path segment |
| `{database_name}` | `fantaco_sales_policy` | PostgreSQL database name |
| `{collection_name}` | `sales_policy_docs` | PGVector collection name |
| `{port}` | `8090` | Service port |
| `{service_title}` | `FantaCo Sales Policy Search` | Human-readable title |
| `{seed_documents}` | Return policy, pricing, etc. | Domain-specific documents |

### Files That Change Per Instance
- `config.py` — default port, collection name, database URL
- `app.py` — `DOMAIN` constant, FastAPI title/description, service name in health check
- `seed_documents/` — domain-specific content
- All `deployment/kubernetes/*.yaml` — names, ports, database name
- `Dockerfile` — `EXPOSE` port

### Files That Stay the Same
- `database.py` — generic psycopg connection pool setup
- `models.py` — Document dataclass is the same for all instances
- `schemas.py` — request/response models are generic
- `document_service.py` — CRUD operations (plain SQL) are generic
- `rag_service.py` — RAG pipeline is generic (configured via env vars)
- `requirements.txt` — same dependencies for all instances

---

## Conventions Checklist

- [ ] Python 3.11-slim Docker base image
- [ ] FastAPI with uvicorn
- [ ] psycopg 3 + psycopg_pool for document metadata (no ORM)
- [ ] LangChain PGVector for embeddings
- [ ] sentence-transformers with `nomic-ai/nomic-embed-text-v1.5`
- [ ] `langchain-openai` `ChatOpenAI` for LLM access
- [ ] `RecursiveCharacterTextSplitter` for chunking
- [ ] All configuration via environment variables
- [ ] `GET /health` health endpoint with document count
- [ ] Full CRUD for documents (POST, GET list, GET by ID, PUT, DELETE)
- [ ] `POST /api/{domain}/search` for RAG queries
- [ ] `POST /api/{domain}/seed` for loading seed documents
- [ ] PostgreSQL with `pgvector/pgvector:pg15` image
- [ ] K8s: Deployment + Service (ClusterIP) + Route (edge TLS)
- [ ] K8s: ConfigMap for non-secret env vars, Secret for API keys
- [ ] K8s resources: 128Mi/100m requests, 256Mi/500m limits
- [ ] `podman build --arch amd64 --os linux` for container builds
- [ ] Registry: `docker.io/burrsutter`
- [ ] Image tag: `1.0.0`
- [ ] Pinned dependency versions in requirements.txt
- [ ] Embedding model pre-downloaded in Docker build
- [ ] Health probes on `/health` endpoint
