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
