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
        # LangChain PGVector uses SQLAlchemy under the hood. The default
        # "postgresql://" dialect expects psycopg2, but we use psycopg3.
        # Replacing the scheme with "postgresql+psycopg://" tells SQLAlchemy
        # to use the psycopg3 driver instead.
        sa_url = DATABASE_URL.replace("postgresql://", "postgresql+psycopg://", 1)
        _vector_store = PGVector(
            embeddings=get_embeddings(),
            collection_name=COLLECTION_NAME,
            connection=sa_url,
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
