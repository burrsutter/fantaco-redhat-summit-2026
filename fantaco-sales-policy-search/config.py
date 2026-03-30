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
