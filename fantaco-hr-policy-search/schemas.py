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
