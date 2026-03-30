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
