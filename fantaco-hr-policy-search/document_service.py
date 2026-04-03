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
