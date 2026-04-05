#!/usr/bin/env python3
"""
FastMCP server for Fantaco Sales Order API (Read-Only)
Provides read-only tools to query the Fantaco Sales Order Service API
Based on OpenAPI specification v0

Server Configuration:
    - Transport: streamable HTTP
    - Port: Configurable via PORT_FOR_SALES_ORDER_MCP (default: 9004)
    - Host: Configurable via HOST_FOR_SALES_ORDER_MCP (default: 0.0.0.0)
    - Mode: Read-only (search and get operations only)

Environment Variables:
    SALES_ORDER_API_BASE_URL: Base URL for the Sales Order API
    PORT_FOR_SALES_ORDER_MCP: Port number for the MCP server (default: 9004)
    HOST_FOR_SALES_ORDER_MCP: Host address to bind to (default: 0.0.0.0)
"""

from fastmcp import FastMCP
from dotenv import load_dotenv
import asyncio
import httpx
import os
import logging
from typing import Optional, Dict, Any

# Initialize FastMCP server
mcp = FastMCP("sales-order-api")

# Load environment variables from .env file
load_dotenv()

# Configuration
port = int(os.getenv("PORT_FOR_SALES_ORDER_MCP", "9004"))
host = os.getenv("HOST_FOR_SALES_ORDER_MCP", "0.0.0.0")
BASE_URL = os.getenv("SALES_ORDER_API_BASE_URL")

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
async def search_sales_orders(
    customer_id: Optional[str] = None,
    customer_name: Optional[str] = None,
    status: Optional[str] = None
) -> Dict[str, Any]:
    """
    Search sales orders by customer or status.

    Use this for prompts like "What are Tech Solutions recent orders?"
    after first resolving the customer account. This tool searches orders;
    it does not return invoices or customer CRM notes.

    Args:
        customer_id: Filter by customer ID (e.g., "CUST001", optional)
        customer_name: Filter by customer name (partial matching, optional)
        status: Filter by order status (e.g., "PENDING", "CONFIRMED", "SHIPPED", "DELIVERED", "CANCELLED", optional)

    Returns:
        List of sales orders matching the search criteria
    """
    params = {}

    if customer_id:
        params["customerId"] = customer_id
    if customer_name:
        params["customerName"] = customer_name
    if status:
        params["status"] = status

    client = await get_http_client()
    response = await client.get("/api/sales-orders", params=params)
    return await handle_response(response)


@mcp.tool()
async def get_sales_order(order_number: str) -> Dict[str, Any]:
    """
    Get a full sales order by order number.

    Use this when the user references a specific order and needs line items,
    totals, or order status details.

    Args:
        order_number: The unique order number identifier (e.g., "ORD-2025-0001")

    Returns:
        Sales order details including orderNumber, customerId, customerName,
        orderDate, status, totalAmount, and lineItems
    """
    client = await get_http_client()
    response = await client.get(f"/api/sales-orders/{order_number}")
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
    logger.info("Sales Order MCP Server Configuration:")
    logger.info(f"  SALES_ORDER_API_BASE_URL: {BASE_URL}")
    logger.info(f"  PORT_FOR_SALES_ORDER_MCP: {port}")
    logger.info(f"  HOST_FOR_SALES_ORDER_MCP: {host}")
    logger.info("=" * 60)

    try:
        mcp.run(transport="http", port=port, host=host)
    finally:
        asyncio.run(cleanup())
