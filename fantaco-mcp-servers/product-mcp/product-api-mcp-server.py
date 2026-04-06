#!/usr/bin/env python3
"""
FastMCP server for Fantaco Product API
Provides full CRUD tools to manage the Fantaco Product Service API
Based on OpenAPI specification v0

Server Configuration:
    - Transport: streamable HTTP
    - Port: Configurable via PORT_FOR_PRODUCT_MCP (default: 9003)
    - Host: Configurable via HOST_FOR_PRODUCT_MCP (default: 0.0.0.0)
    - Mode: Read-write (full CRUD operations)

Environment Variables:
    PRODUCT_API_BASE_URL: Base URL for the Product API
    PORT_FOR_PRODUCT_MCP: Port number for the MCP server (default: 9003)
    HOST_FOR_PRODUCT_MCP: Host address to bind to (default: 0.0.0.0)
"""

from fastmcp import FastMCP
from dotenv import load_dotenv
import asyncio
import httpx
import os
import logging
from typing import Optional, Dict, Any, List

# Initialize FastMCP server
mcp = FastMCP("product-api")

# Load environment variables from .env file
load_dotenv()

# Configuration
port = int(os.getenv("PORT_FOR_PRODUCT_MCP", "9003"))
host = os.getenv("HOST_FOR_PRODUCT_MCP", "0.0.0.0")
BASE_URL = os.getenv("PRODUCT_API_BASE_URL")

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
async def search_products(
    name: Optional[str] = None,
    category: Optional[str] = None,
    manufacturer: Optional[str] = None,
    theme: Optional[str] = None,
) -> Dict[str, Any]:
    """
    Search the product catalog by name, category, manufacturer, or pod theme.

    Use this when the user is exploring catalog offerings, including
    theme-specific Imagination Pod items or universal products.

    Args:
        name: Filter by product name (partial matching, optional)
        category: Filter by product category (e.g., "Desk Accessories", "Writing Supplies", optional)
        manufacturer: Filter by manufacturer name (partial matching, optional)
        theme: Imagination Pod workspace theme token (optional). Use list_pod_themes for values.
            Examples: INTERSTELLAR_SPACESHIP, ENCHANTED_FOREST, SPEAKEASY_1920S, ZEN_GARDEN, CUSTOM.
            Universal catalog SKUs (no theme tags) match every theme.

    Returns:
        List of products matching the search criteria
    """
    params = {}

    if name:
        params["name"] = name
    if category:
        params["category"] = category
    if manufacturer:
        params["manufacturer"] = manufacturer
    if theme:
        params["theme"] = theme

    client = await get_http_client()
    response = await client.get("/api/products", params=params)
    return await handle_response(response)


@mcp.tool()
async def list_pod_themes() -> Dict[str, Any]:
    """
    List valid Imagination Pod theme tokens used by product and project tools.

    Returns:
        Sorted list of theme enum names (e.g. INTERSTELLAR_SPACESHIP).
    """
    client = await get_http_client()
    response = await client.get("/api/products/meta/pod-themes")
    return await handle_response(response)


@mcp.tool()
async def get_product(sku: str) -> Dict[str, Any]:
    """
    Get a single product by SKU.

    Use this when the user already knows the SKU and wants the full catalog entry.

    Args:
        sku: The unique SKU identifier for the product (e.g., "PEN-BLK-001")

    Returns:
        Product details including sku, name, description, category, price, cost,
        stockQuantity, manufacturer, supplier, weight, dimensions, and isActive
    """
    client = await get_http_client()
    response = await client.get(f"/api/products/{sku}")
    return await handle_response(response)


@mcp.tool()
async def create_product(
    sku: str,
    name: str,
    category: str,
    price: float,
    cost: float,
    stock_quantity: int,
    manufacturer: str,
    supplier: str,
    is_active: bool,
    description: Optional[str] = None,
    weight: Optional[float] = None,
    dimensions: Optional[str] = None,
    pod_themes: Optional[List[str]] = None,
) -> Dict[str, Any]:
    """
    Create a new product catalog entry.

    Use this for catalog-management workflows when FantaCo introduces a new
    office product, furniture item, or theme-specific Imagination Pod offering.

    Args:
        sku: Unique SKU identifier (e.g., "PEN-BLK-001")
        name: Product name
        category: Product category (e.g., "Desk Accessories", "Writing Supplies", "Office Furniture")
        price: Selling price
        cost: Cost price
        stock_quantity: Current stock quantity
        manufacturer: Manufacturer name
        supplier: Supplier name
        is_active: Whether the product is active
        description: Product description (optional)
        weight: Product weight in appropriate units (optional)
        dimensions: Product dimensions as string (optional)
        pod_themes: Workspace theme tags (optional). Empty or omitted = universal catalog.
            Use list_pod_themes for allowed tokens.

    Returns:
        The created product record
    """
    payload = {
        "sku": sku,
        "name": name,
        "category": category,
        "price": price,
        "cost": cost,
        "stockQuantity": stock_quantity,
        "manufacturer": manufacturer,
        "supplier": supplier,
        "isActive": is_active,
    }

    if description is not None:
        payload["description"] = description
    if weight is not None:
        payload["weight"] = weight
    if dimensions is not None:
        payload["dimensions"] = dimensions
    if pod_themes is not None:
        payload["podThemes"] = pod_themes

    client = await get_http_client()
    response = await client.post("/api/products", json=payload)
    return await handle_response(response)


@mcp.tool()
async def update_product(
    sku: str,
    name: str,
    category: str,
    price: float,
    cost: float,
    stock_quantity: int,
    manufacturer: str,
    supplier: str,
    is_active: bool,
    description: Optional[str] = None,
    weight: Optional[float] = None,
    dimensions: Optional[str] = None,
    pod_themes: Optional[List[str]] = None,
) -> Dict[str, Any]:
    """
    Update an existing product catalog entry.

    Use this when pricing, stock, supplier information, or theme tags need to change.

    Args:
        sku: Unique SKU identifier of the product to update
        name: Updated product name
        category: Updated product category
        price: Updated selling price
        cost: Updated cost price
        stock_quantity: Updated stock quantity
        manufacturer: Updated manufacturer name
        supplier: Updated supplier name
        is_active: Whether the product is active
        description: Updated product description (optional)
        weight: Updated product weight (optional)
        dimensions: Updated product dimensions (optional)
        pod_themes: When provided, replaces theme tags; use [] for universal. When omitted, themes unchanged.

    Returns:
        The updated product record
    """
    payload = {
        "sku": sku,
        "name": name,
        "category": category,
        "price": price,
        "cost": cost,
        "stockQuantity": stock_quantity,
        "manufacturer": manufacturer,
        "supplier": supplier,
        "isActive": is_active,
    }

    if description is not None:
        payload["description"] = description
    if weight is not None:
        payload["weight"] = weight
    if dimensions is not None:
        payload["dimensions"] = dimensions
    if pod_themes is not None:
        payload["podThemes"] = pod_themes

    client = await get_http_client()
    response = await client.put(f"/api/products/{sku}", json=payload)
    return await handle_response(response)


@mcp.tool()
async def delete_product(sku: str) -> Dict[str, Any]:
    """
    Delete a product by SKU.

    Use this only when a catalog entry should be permanently removed.

    Args:
        sku: The unique SKU identifier of the product to delete

    Returns:
        Confirmation of deletion
    """
    client = await get_http_client()
    response = await client.delete(f"/api/products/{sku}")
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
    logger.info("Product MCP Server Configuration:")
    logger.info(f"  PRODUCT_API_BASE_URL: {BASE_URL}")
    logger.info(f"  PORT_FOR_PRODUCT_MCP: {port}")
    logger.info(f"  HOST_FOR_PRODUCT_MCP: {host}")
    logger.info("=" * 60)

    try:
        mcp.run(transport="http", port=port, host=host)
    finally:
        asyncio.run(cleanup())
