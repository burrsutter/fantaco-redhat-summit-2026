#!/usr/bin/env python3
"""
FastMCP server for Fantaco Customer API (Read-Only)
Provides read-only tools to query the Fantaco Customer Service API
Based on OpenAPI specification v0

Server Configuration:
    - Transport: streamable HTTP
    - Port: Configurable via PORT_FOR_CUSTOMER_MCP (default: 9001)
    - Host: Configurable via HOST_FOR_CUSTOMER_MCP (default: 0.0.0.0)
    - Mode: Read-only (search and get operations only)

Environment Variables:
    CUSTOMER_API_BASE_URL: Base URL for the Customer API
    PORT_FOR_CUSTOMER_MCP: Port number for the MCP server (default: 9001)
    HOST_FOR_CUSTOMER_MCP: Host address to bind to (default: 0.0.0.0) 
                          
"""

from fastmcp import FastMCP
from dotenv import load_dotenv
import asyncio
import httpx
import os
import logging
from typing import Optional, Dict, Any

# Initialize FastMCP server
mcp = FastMCP("customer-api")

# Load environment variables from .env file
load_dotenv()

# Base URL for the Customer API (configurable via environment variable)
port = int(os.getenv("PORT_FOR_CUSTOMER_MCP", "9001"))
host = os.getenv("HOST_FOR_CUSTOMER_MCP", "0.0.0.0")
BASE_URL = os.getenv("CUSTOMER_API_BASE_URL")


# HTTP client for API calls
http_client: Optional[httpx.AsyncClient] = None


async def get_http_client() -> httpx.AsyncClient:
    """Get or create HTTP client."""
    global http_client
    if http_client is None:
        http_client = httpx.AsyncClient(base_url=BASE_URL, timeout=30.0)
    return http_client


async def handle_response(response: httpx.Response) -> Dict[str, Any]:
    """Handle HTTP response and return JSON or error message"""
    try:
        response.raise_for_status()
        if response.content:
            data = response.json()
            # MCP requires dict responses, so wrap lists in a dict
            if isinstance(data, list):
                return {"results": data}
            return data
        return {"status": "success", "status_code": response.status_code}
    except httpx.HTTPStatusError as e:
        error_detail = ""
        try:
            error_detail = e.response.json()
        except:
            error_detail = e.response.text
        return {
            "error": f"HTTP {e.response.status_code}",
            "detail": error_detail,
            "status_code": e.response.status_code
        }
    except Exception as e:
        return {"error": str(e)}


@mcp.tool()
async def search_customers(
    company_name: Optional[str] = None,
    contact_name: Optional[str] = None,
    contact_email: Optional[str] = None,
    phone: Optional[str] = None
) -> Dict[str, Any]:
    """
    Search for customers by various fields with partial matching

    Args:
        company_name: Filter by company name (partial matching, optional)
        contact_name: Filter by contact person name (partial matching, optional)
        contact_email: Filter by contact email address (partial matching, optional)
        phone: Filter by phone number (partial matching, optional)

    Returns:
        List of customers matching the search criteria
    """
    params = {}

    if company_name:
        params["companyName"] = company_name
    if contact_name:
        params["contactName"] = contact_name
    if contact_email:
        params["contactEmail"] = contact_email
    if phone:
        params["phone"] = phone

    client = await get_http_client()
    response = await client.get("/api/customers", params=params)
    return await handle_response(response)


@mcp.tool()
async def get_customer(customer_id: str) -> Dict[str, Any]:
    """
    Get customer by ID

    Retrieves a single customer record by its unique identifier

    Args:
        customer_id: The unique 5-character identifier of the customer

    Returns:
        Customer details including customerId, companyName, contactName, contactTitle,
        address, city, region, postalCode, country, phone, fax, contactEmail,
        createdAt, and updatedAt
    """
    client = await get_http_client()
    response = await client.get(f"/api/customers/{customer_id}")
    return await handle_response(response)


@mcp.tool()
async def get_customer_detail(customer_id: str) -> Dict[str, Any]:
    """
    Get customer detail with all CRM data

    Retrieves a customer record along with all associated notes, contacts, and sales persons

    Args:
        customer_id: The unique identifier of the customer (e.g. CUST001)

    Returns:
        Customer details including notes, contacts, and sales person assignments
    """
    client = await get_http_client()
    response = await client.get(f"/api/customers/{customer_id}/detail")
    return await handle_response(response)


@mcp.tool()
async def get_customer_notes(customer_id: str) -> Dict[str, Any]:
    """
    Get all notes for a customer

    Retrieves all notes associated with the specified customer

    Args:
        customer_id: The unique identifier of the customer (e.g. CUST001)

    Returns:
        List of notes for the customer, each with id, noteText, createdAt, updatedAt
    """
    client = await get_http_client()
    response = await client.get(f"/api/customers/{customer_id}/notes")
    return await handle_response(response)


@mcp.tool()
async def get_customer_contacts(customer_id: str) -> Dict[str, Any]:
    """
    Get all contacts for a customer

    Retrieves all contacts associated with the specified customer

    Args:
        customer_id: The unique identifier of the customer (e.g. CUST001)

    Returns:
        List of contacts for the customer, each with id, firstName, lastName, email, title, phone, notes
    """
    client = await get_http_client()
    response = await client.get(f"/api/customers/{customer_id}/contacts")
    return await handle_response(response)


@mcp.tool()
async def get_customer_salespersons(customer_id: str) -> Dict[str, Any]:
    """
    Get all sales persons assigned to a customer

    Retrieves all sales person assignments for the specified customer

    Args:
        customer_id: The unique identifier of the customer (e.g. CUST001)

    Returns:
        List of sales persons for the customer, each with id, firstName, lastName, email, phone, territory
    """
    client = await get_http_client()
    response = await client.get(f"/api/customers/{customer_id}/salespersons")
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
    logger.info("Customer MCP Server Configuration:")
    logger.info(f"  CUSTOMER_API_BASE_URL: {BASE_URL}")
    logger.info(f"  PORT_FOR_CUSTOMER_MCP: {port}")
    logger.info(f"  HOST_FOR_CUSTOMER_MCP: {host}")
    logger.info("=" * 60)

    try:
        mcp.run(transport="http", port=port, host=host)
    finally:
        asyncio.run(cleanup())

