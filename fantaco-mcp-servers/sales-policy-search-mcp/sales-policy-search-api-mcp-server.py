#!/usr/bin/env python3
"""
FastMCP server for Fantaco Sales Policy Search API
Provides tools to use the Fantaco Sales Policy Search Service API (RAG-powered)

Server Configuration:
    - Transport: streamable HTTP
    - Port: Configurable via PORT_FOR_SALES_POLICY_SEARCH_MCP (default: 9006)
    - Host: Configurable via HOST_FOR_SALES_POLICY_SEARCH_MCP (default: 0.0.0.0)

Environment Variables:
    SALES_POLICY_SEARCH_API_BASE_URL: Base URL for the Sales Policy Search API
    PORT_FOR_SALES_POLICY_SEARCH_MCP: Port number for the MCP server (default: 9006)
    HOST_FOR_SALES_POLICY_SEARCH_MCP: Host address to bind to (default: 0.0.0.0)
"""

from fastmcp import FastMCP
from dotenv import load_dotenv
import asyncio
import httpx
import os
import logging
from typing import Optional, Dict, Any

# Initialize FastMCP server
mcp = FastMCP("sales-policy-search-api")

# Load environment variables from .env file
load_dotenv()

# Configuration
port = int(os.getenv("PORT_FOR_SALES_POLICY_SEARCH_MCP", "9006"))
host = os.getenv("HOST_FOR_SALES_POLICY_SEARCH_MCP", "0.0.0.0")
BASE_URL = os.getenv("SALES_POLICY_SEARCH_API_BASE_URL")

# HTTP client for API calls
http_client: Optional[httpx.AsyncClient] = None


async def get_http_client() -> httpx.AsyncClient:
    """Get or create HTTP client."""
    global http_client
    if http_client is None:
        http_client = httpx.AsyncClient(base_url=BASE_URL, timeout=30.0)
    return http_client


async def handle_response(response: httpx.Response) -> Dict[str, Any]:
    """Handle HTTP response and return a consistent response envelope"""
    try:
        response.raise_for_status()
        if response.content:
            data = response.json()
            envelope: Dict[str, Any] = {
                "success": True,
                "message": "OK",
                "data": data,
            }
            if isinstance(data, list):
                envelope["count"] = len(data)
            return envelope
        return {"success": True, "message": "OK", "data": None}
    except httpx.HTTPStatusError as e:
        error_detail = ""
        try:
            error_detail = e.response.json()
        except:
            error_detail = e.response.text
        return {
            "success": False,
            "message": f"HTTP {e.response.status_code}",
            "data": error_detail
        }
    except Exception as e:
        return {"success": False, "message": str(e), "data": None}


@mcp.tool()
async def search_sales_policy(
    query: str,
    top_k: int = 5
) -> Dict[str, Any]:
    """
    Answer questions about sales policies using RAG search.

    Use this for natural-language prompts such as "What is our return sales policy?"
    or "What discount rules apply to service projects?" It performs semantic search
    across sales policy documents and returns an answer with supporting sources.

    Args:
        query: Natural language question about sales policies (e.g., "What is the return policy for perishable items?")
        top_k: Number of relevant document chunks to retrieve (default: 5)

    Returns:
        Dictionary with success status, AI-generated answer, source chunks with
        similarity scores, and the original query
    """
    payload = {
        "query": query,
        "top_k": top_k
    }

    client = await get_http_client()
    response = await client.post("/api/sales-policy/search", json=payload)
    return await handle_response(response)


@mcp.tool()
async def list_sales_policy_documents() -> Dict[str, Any]:
    """
    List sales policy documents in the knowledge base.

    Use this when browsing or validating what policy sources are available,
    not when the user is asking a policy question directly.

    Retrieves metadata for all documents in the sales policy knowledge base.
    Returns document IDs, titles, categories, and timestamps (no full text).

    Returns:
        List of document metadata including id, title, source_filename,
        category, created_at, and updated_at
    """
    client = await get_http_client()
    response = await client.get("/api/sales-policy/documents")
    return await handle_response(response)


@mcp.tool()
async def get_sales_policy_document(document_id: int) -> Dict[str, Any]:
    """
    Get the full text of a sales policy document by ID.

    Use this after list_sales_policy_documents or when a retrieved source
    document needs to be inspected directly.

    Retrieves the full details of a single document including its complete text content.

    Args:
        document_id: The unique integer identifier of the document

    Returns:
        Full document details including id, title, content_text, source_filename,
        category, created_at, and updated_at
    """
    client = await get_http_client()
    response = await client.get(f"/api/sales-policy/documents/{document_id}")
    return await handle_response(response)


@mcp.tool()
async def create_sales_policy_document(
    title: str,
    content: str,
    category: Optional[str] = None,
    source_filename: Optional[str] = None
) -> Dict[str, Any]:
    """
    Create a new sales policy document in the RAG knowledge base.

    Use this for knowledge-base maintenance when a new return, shipping,
    warranty, pricing, or service policy document needs to become searchable.
    The document will be automatically chunked, embedded, and indexed.

    Args:
        title: Title of the document (e.g., "Return Policy v2.1")
        content: Full text content of the document
        category: Optional category for the document (e.g., "returns", "shipping")
        source_filename: Optional source filename for idempotent seeding

    Returns:
        The created document metadata
    """
    payload = {
        "title": title,
        "content": content,
    }
    if category:
        payload["category"] = category
    if source_filename:
        payload["source_filename"] = source_filename

    client = await get_http_client()
    response = await client.post("/api/sales-policy/documents", json=payload)
    return await handle_response(response)


@mcp.tool()
async def update_sales_policy_document(
    document_id: int,
    title: Optional[str] = None,
    content: Optional[str] = None,
    category: Optional[str] = None
) -> Dict[str, Any]:
    """
    Update an existing sales policy document in the RAG knowledge base.

    Use this when the policy source itself changes. If content is updated,
    the document will be re-chunked and re-embedded for search.

    Args:
        document_id: The unique integer identifier of the document to update
        title: Updated title (optional)
        content: Updated full text content (optional, triggers re-embedding)
        category: Updated category (optional)

    Returns:
        The updated document metadata
    """
    payload = {}
    if title:
        payload["title"] = title
    if content:
        payload["content"] = content
    if category:
        payload["category"] = category

    client = await get_http_client()
    response = await client.put(f"/api/sales-policy/documents/{document_id}", json=payload)
    return await handle_response(response)


@mcp.tool()
async def delete_sales_policy_document(document_id: int) -> Dict[str, Any]:
    """
    Delete a sales policy document from the knowledge base.

    Use this only when a policy source should be permanently removed,
    including its embeddings.

    Args:
        document_id: The unique integer identifier of the document to delete

    Returns:
        Confirmation of deletion
    """
    client = await get_http_client()
    response = await client.delete(f"/api/sales-policy/documents/{document_id}")
    return await handle_response(response)


@mcp.tool()
async def seed_sales_policy_documents() -> Dict[str, Any]:
    """
    Seed sales policy documents from the built-in document collection.

    Use this for environment setup or demo reset workflows. The server loads
    and indexes documents from `seed_documents/`. The operation is idempotent:
    documents with matching `source_filename` values are skipped.

    Returns:
        Dictionary with seeded documents (title and chunk count), total count,
        and number of skipped documents
    """
    client = await get_http_client()
    response = await client.post("/api/sales-policy/seed")
    return await handle_response(response)


async def cleanup():
    """Cleanup resources."""
    global http_client
    if http_client:
        await http_client.aclose()
        http_client = None


if __name__ == "__main__":
    # Configure logging
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )
    logger = logging.getLogger(__name__)

    # Log configuration
    logger.info("=" * 60)
    logger.info("Sales Policy Search MCP Server Configuration:")
    logger.info(f"  SALES_POLICY_SEARCH_API_BASE_URL: {BASE_URL}")
    logger.info(f"  PORT_FOR_SALES_POLICY_SEARCH_MCP: {port}")
    logger.info(f"  HOST_FOR_SALES_POLICY_SEARCH_MCP: {host}")
    logger.info("=" * 60)

    try:
        mcp.run(transport="http", port=port, host=host)
    finally:
        asyncio.run(cleanup())
