#!/usr/bin/env python3
"""
FastMCP server for Fantaco Finance API
Provides tools to use the Fantaco Finance Service API
Based on OpenAPI specification v0

Server Configuration:
    - Transport: streamable HTTP
    - Port: Configurable via PORT_FOR_FINANCE_MCP (default: 9002)
    - Host: Configurable via HOST_FOR_FINANCE_MCP (default: 0.0.0.0)
    - Mode: Read-write (search, get, and action operations)

Environment Variables:
    FINANCE_API_BASE_URL: Base URL for the Finance API
    PORT_FOR_FINANCE_MCP: Port number for the MCP server (default: 9002)
    HOST_FOR_FINANCE_MCP: Host address to bind to (default: 0.0.0.0)
"""

from fastmcp import FastMCP
from dotenv import load_dotenv
import asyncio
import httpx
import os
import logging
from typing import Optional, Dict, Any

# Initialize FastMCP server
mcp = FastMCP("finance-api")

# Load environment variables from .env file
load_dotenv()

# Configuration
port = int(os.getenv("PORT_FOR_FINANCE_MCP", "9002"))
host = os.getenv("HOST_FOR_FINANCE_MCP", "0.0.0.0")
BASE_URL = os.getenv("FINANCE_API_BASE_URL")

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
async def get_all_invoices() -> Dict[str, Any]:
    """
    List all invoices

    Retrieves all invoices in the system.

    Returns:
        Dictionary containing:
        - success: Boolean indicating if the request was successful
        - message: Description of the result
        - data: List of invoice objects with details (id, invoiceNumber, orderNumber, customerId, amount, status, invoiceDate, dueDate, paidDate)
        - count: Number of invoices returned
    """
    client = await get_http_client()
    response = await client.get("/api/finance/invoices")
    return await handle_response(response)


@mcp.tool()
async def get_invoice(invoice_id: int) -> Dict[str, Any]:
    """
    Get invoice by ID

    Retrieves a single invoice record by its unique identifier.

    Args:
        invoice_id: The unique numeric identifier of the invoice

    Returns:
        Dictionary containing:
        - success: Boolean indicating if the request was successful
        - message: Description of the result
        - data: Invoice object with details (id, invoiceNumber, orderNumber, customerId, amount, status, invoiceDate, dueDate, paidDate)
    """
    client = await get_http_client()
    response = await client.get(f"/api/finance/invoices/{invoice_id}")
    return await handle_response(response)


@mcp.tool()
async def get_invoices_by_customer(customer_id: str) -> Dict[str, Any]:
    """
    Get invoices by customer ID

    Retrieves all invoices for a specific customer.

    Args:
        customer_id: Unique identifier for the customer (e.g., "CUST001")

    Returns:
        Dictionary containing:
        - success: Boolean indicating if the request was successful
        - message: Description of the result
        - data: List of invoice objects for the customer
        - count: Number of invoices returned
    """
    client = await get_http_client()
    response = await client.get(f"/api/finance/invoices/customer/{customer_id}")
    return await handle_response(response)


@mcp.tool()
async def get_invoices_by_order(order_number: str) -> Dict[str, Any]:
    """
    Get invoices by order number

    Retrieves all invoices associated with a specific order.

    Args:
        order_number: The order number to look up invoices for (e.g., "ORD-2025-0001")

    Returns:
        Dictionary containing:
        - success: Boolean indicating if the request was successful
        - message: Description of the result
        - data: List of invoice objects for the order
        - count: Number of invoices returned
    """
    client = await get_http_client()
    response = await client.get(f"/api/finance/invoices/order/{order_number}")
    return await handle_response(response)


@mcp.tool()
async def fetch_invoice_history(
    customer_id: str,
    start_date: Optional[str] = None,
    end_date: Optional[str] = None,
    limit: int = 50
) -> Dict[str, Any]:
    """
    Get invoice history for a customer.

    Retrieves the invoice history for a specific customer with optional date filtering and pagination.

    Args:
        customer_id: Unique identifier for the customer (e.g., "CUST001")
        start_date: Start date for filtering invoices in ISO 8601 format (e.g., "2024-01-15T10:30:00")
        end_date: End date for filtering invoices in ISO 8601 format (e.g., "2024-01-31T23:59:59")
        limit: Maximum number of invoices to return (default: 50)

    Returns:
        Dictionary containing:
        - success: Boolean indicating if the request was successful
        - message: Description of the result
        - data: List of invoice objects with details (id, invoiceNumber, orderNumber, customerId, amount, status, invoiceDate, dueDate, paidDate)
        - count: Number of invoices returned
    """
    client = await get_http_client()

    # Build request payload
    payload = {
        "customerId": customer_id,
        "limit": limit
    }

    if start_date:
        payload["startDate"] = start_date
    if end_date:
        payload["endDate"] = end_date

    # Make POST request
    response = await client.post("/api/finance/invoices/history", json=payload)

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
    logger.info("Finance MCP Server Configuration:")
    logger.info(f"  FINANCE_API_BASE_URL: {BASE_URL}")
    logger.info(f"  PORT_FOR_FINANCE_MCP: {port}")
    logger.info(f"  HOST_FOR_FINANCE_MCP: {host}")
    logger.info("=" * 60)

    try:
        mcp.run(transport="http", port=port, host=host)
    finally:
        asyncio.run(cleanup())
