#!/usr/bin/env python3
"""
FastMCP server for Fantaco Customer API
Provides tools to query and manage the Fantaco Customer Service API,
including customer data and Imagination Pod project management.

Server Configuration:
    - Transport: streamable HTTP
    - Port: Configurable via PORT_FOR_CUSTOMER_MCP (default: 9001)
    - Host: Configurable via HOST_FOR_CUSTOMER_MCP (default: 0.0.0.0)

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
    Search for customers by company name, contact name, email, or phone.
    This searches customer master data fields only.
    To find customers by their assigned sales person, use search_customers_by_salesperson instead.

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
async def search_customers_by_salesperson(
    salesperson_name: str
) -> Dict[str, Any]:
    """
    Find all customers assigned to a specific sales person.

    Use this tool when asked questions like "which customers does Sally Sellers handle?"
    or "find customers for sales rep John". Searches by partial name match
    (case-insensitive) against sales person first name and last name.

    Args:
        salesperson_name: Full or partial name of the sales person (e.g. "Sally Sellers", "Sally", "Sellers")

    Returns:
        List of customers assigned to the matching sales person, each with full customer details and matching sales person info
    """
    client = await get_http_client()

    # Step 1: Fetch all customers
    response = await client.get("/api/customers")
    if response.status_code != 200:
        return await handle_response(response)
    customers = response.json()
    if not isinstance(customers, list):
        customers = customers.get("results", [])

    # Step 2: Concurrently fetch detail for each customer
    async def fetch_detail(customer):
        cid = customer.get("customerId")
        resp = await client.get(f"/api/customers/{cid}/detail")
        if resp.status_code == 200:
            return resp.json()
        return None

    details = await asyncio.gather(*(fetch_detail(c) for c in customers))

    # Step 3: Filter by sales person name match
    search_terms = salesperson_name.lower().split()
    matching_customers = []

    for detail in details:
        if detail is None:
            continue
        salespersons = detail.get("salesPersons", [])
        matching_sps = []
        for sp in salespersons:
            first = (sp.get("firstName") or "").lower()
            last = (sp.get("lastName") or "").lower()
            full_name = f"{first} {last}"
            if all(term in full_name for term in search_terms):
                matching_sps.append(sp)
        if matching_sps:
            matching_customers.append({
                "customerId": detail.get("customerId"),
                "companyName": detail.get("companyName"),
                "contactName": detail.get("contactName"),
                "contactEmail": detail.get("contactEmail"),
                "phone": detail.get("phone"),
                "city": detail.get("city"),
                "region": detail.get("region"),
                "country": detail.get("country"),
                "matchingSalespersons": matching_sps
            })

    return {
        "query": salesperson_name,
        "totalCustomersSearched": len(customers),
        "matchingCustomerCount": len(matching_customers),
        "results": matching_customers
    }


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

    Retrieves a customer record along with all associated CRM data:
    notes (interaction history), contacts (people at the company),
    and sales persons (reps assigned to the account).
    Use search_customers_by_salesperson to find customers by sales rep name.

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


@mcp.tool()
async def get_customer_projects(
    customer_id: str,
    status: Optional[str] = None,
    pod_theme: Optional[str] = None
) -> Dict[str, Any]:
    """
    List all Imagination Pod projects for a customer, with optional filtering.

    Args:
        customer_id: The unique identifier of the customer (e.g. CUST001)
        status: Filter by project status (optional). Values: PROPOSAL, APPROVED, IN_PROGRESS, ON_HOLD, COMPLETED, CANCELLED
        pod_theme: Filter by pod theme (optional). Values: ENCHANTED_FOREST, INTERSTELLAR_SPACESHIP, SPEAKEASY_1920S, ZEN_GARDEN, CUSTOM

    Returns:
        List of projects for the customer
    """
    params = {}
    if status:
        params["status"] = status
    if pod_theme:
        params["podTheme"] = pod_theme

    client = await get_http_client()
    response = await client.get(f"/api/customers/{customer_id}/projects", params=params)
    return await handle_response(response)


@mcp.tool()
async def get_project_detail(
    customer_id: str,
    project_id: int
) -> Dict[str, Any]:
    """
    Get full project detail including milestones and notes.

    Args:
        customer_id: The unique identifier of the customer (e.g. CUST001)
        project_id: The numeric ID of the project

    Returns:
        Project details with milestones (ordered by sort_order) and notes (newest first)
    """
    client = await get_http_client()
    response = await client.get(f"/api/customers/{customer_id}/projects/{project_id}")
    return await handle_response(response)


@mcp.tool()
async def search_projects_by_status(
    status: str
) -> Dict[str, Any]:
    """
    Find all projects across all customers in a given status.

    Args:
        status: Project status to search for. Values: PROPOSAL, APPROVED, IN_PROGRESS, ON_HOLD, COMPLETED, CANCELLED

    Returns:
        List of projects matching the status across all customers
    """
    client = await get_http_client()

    # Fetch all customers
    response = await client.get("/api/customers")
    if response.status_code != 200:
        return await handle_response(response)
    customers = response.json()
    if not isinstance(customers, list):
        customers = customers.get("results", [])

    # Fetch projects filtered by status for each customer
    async def fetch_projects(customer):
        cid = customer.get("customerId")
        resp = await client.get(f"/api/customers/{cid}/projects", params={"status": status})
        if resp.status_code == 200:
            data = resp.json()
            return data if isinstance(data, list) else data.get("results", [])
        return []

    all_project_lists = await asyncio.gather(*(fetch_projects(c) for c in customers))
    all_projects = [p for project_list in all_project_lists for p in project_list]

    return {
        "query_status": status,
        "totalProjects": len(all_projects),
        "results": all_projects
    }


@mcp.tool()
async def search_projects_by_theme(
    pod_theme: str
) -> Dict[str, Any]:
    """
    Find all projects across all customers with a given pod theme.

    Args:
        pod_theme: Pod theme to search for. Values: ENCHANTED_FOREST, INTERSTELLAR_SPACESHIP, SPEAKEASY_1920S, ZEN_GARDEN, CUSTOM

    Returns:
        List of projects matching the theme across all customers
    """
    client = await get_http_client()

    # Fetch all customers
    response = await client.get("/api/customers")
    if response.status_code != 200:
        return await handle_response(response)
    customers = response.json()
    if not isinstance(customers, list):
        customers = customers.get("results", [])

    # Fetch projects filtered by theme for each customer
    async def fetch_projects(customer):
        cid = customer.get("customerId")
        resp = await client.get(f"/api/customers/{cid}/projects", params={"podTheme": pod_theme})
        if resp.status_code == 200:
            data = resp.json()
            return data if isinstance(data, list) else data.get("results", [])
        return []

    all_project_lists = await asyncio.gather(*(fetch_projects(c) for c in customers))
    all_projects = [p for project_list in all_project_lists for p in project_list]

    return {
        "query_theme": pod_theme,
        "totalProjects": len(all_projects),
        "results": all_projects
    }


@mcp.tool()
async def add_project_note(
    customer_id: str,
    project_id: int,
    note_text: str,
    note_type: str,
    author: Optional[str] = None
) -> Dict[str, Any]:
    """
    Add a note to a project.

    Args:
        customer_id: The unique identifier of the customer (e.g. CUST001)
        project_id: The numeric ID of the project
        note_text: The note content
        note_type: Type of note. Values: STATUS_UPDATE, CHANGE_ORDER, SITE_VISIT, ISSUE, GENERAL
        author: Who wrote the note (optional)

    Returns:
        The created project note
    """
    body = {
        "noteText": note_text,
        "noteType": note_type
    }
    if author:
        body["author"] = author

    client = await get_http_client()
    response = await client.post(
        f"/api/customers/{customer_id}/projects/{project_id}/notes",
        json=body
    )
    return await handle_response(response)


@mcp.tool()
async def update_project_status(
    customer_id: str,
    project_id: int,
    status: str,
    project_name: Optional[str] = None,
    description: Optional[str] = None,
    pod_theme: Optional[str] = None,
    site_address: Optional[str] = None,
    estimated_start_date: Optional[str] = None,
    estimated_end_date: Optional[str] = None,
    actual_start_date: Optional[str] = None,
    actual_end_date: Optional[str] = None,
    estimated_budget: Optional[float] = None,
    actual_cost: Optional[float] = None
) -> Dict[str, Any]:
    """
    Update a project's status and other fields. Uses PUT so all mutable fields are sent.
    First fetches the current project to preserve existing values for fields not being changed.

    Allowed status transitions:
    - PROPOSAL -> APPROVED, CANCELLED
    - APPROVED -> IN_PROGRESS, ON_HOLD, CANCELLED
    - IN_PROGRESS -> ON_HOLD, COMPLETED, CANCELLED
    - ON_HOLD -> IN_PROGRESS, CANCELLED
    - COMPLETED and CANCELLED are terminal states

    Args:
        customer_id: The unique identifier of the customer (e.g. CUST001)
        project_id: The numeric ID of the project
        status: New project status
        project_name: Project name (uses current if not provided)
        description: Project description (uses current if not provided)
        pod_theme: Pod theme (uses current if not provided)
        site_address: Site address (uses current if not provided)
        estimated_start_date: Estimated start date as YYYY-MM-DD (uses current if not provided)
        estimated_end_date: Estimated end date as YYYY-MM-DD (uses current if not provided)
        actual_start_date: Actual start date as YYYY-MM-DD (required for IN_PROGRESS/COMPLETED)
        actual_end_date: Actual end date as YYYY-MM-DD (required for COMPLETED)
        estimated_budget: Estimated budget (uses current if not provided)
        actual_cost: Actual cost (uses current if not provided)

    Returns:
        The updated project
    """
    client = await get_http_client()

    # Fetch current project to preserve existing values
    current_resp = await client.get(f"/api/customers/{customer_id}/projects/{project_id}")
    if current_resp.status_code != 200:
        return await handle_response(current_resp)
    current = current_resp.json()

    body = {
        "projectName": project_name if project_name is not None else current.get("projectName"),
        "description": description if description is not None else current.get("description"),
        "podTheme": pod_theme if pod_theme is not None else current.get("podTheme"),
        "status": status,
        "siteAddress": site_address if site_address is not None else current.get("siteAddress"),
        "estimatedStartDate": estimated_start_date if estimated_start_date is not None else current.get("estimatedStartDate"),
        "estimatedEndDate": estimated_end_date if estimated_end_date is not None else current.get("estimatedEndDate"),
        "actualStartDate": actual_start_date if actual_start_date is not None else current.get("actualStartDate"),
        "actualEndDate": actual_end_date if actual_end_date is not None else current.get("actualEndDate"),
        "estimatedBudget": estimated_budget if estimated_budget is not None else current.get("estimatedBudget"),
        "actualCost": actual_cost if actual_cost is not None else current.get("actualCost"),
    }

    response = await client.put(
        f"/api/customers/{customer_id}/projects/{project_id}",
        json=body
    )
    return await handle_response(response)


@mcp.tool()
async def update_milestone_status(
    customer_id: str,
    project_id: int,
    milestone_id: int,
    status: str,
    completed_date: Optional[str] = None,
    notes: Optional[str] = None,
    due_date: Optional[str] = None,
    name: Optional[str] = None,
    sort_order: Optional[int] = None
) -> Dict[str, Any]:
    """
    Update a milestone's status and optional fields. Uses PUT so all mutable fields are sent.
    First fetches the current milestone to preserve existing values for fields not being changed.

    Args:
        customer_id: The unique identifier of the customer (e.g. CUST001)
        project_id: The numeric ID of the project
        milestone_id: The numeric ID of the milestone
        status: New milestone status. Values: NOT_STARTED, IN_PROGRESS, COMPLETED, BLOCKED
        completed_date: Completion date as YYYY-MM-DD (required when status=COMPLETED, must be null otherwise)
        notes: Milestone notes (uses current if not provided)
        due_date: Due date as YYYY-MM-DD (uses current if not provided)
        name: Milestone name (uses current if not provided)
        sort_order: Sort order (uses current if not provided)

    Returns:
        The updated milestone
    """
    client = await get_http_client()

    # Fetch current milestones to find current values
    milestones_resp = await client.get(
        f"/api/customers/{customer_id}/projects/{project_id}/milestones"
    )
    if milestones_resp.status_code != 200:
        return await handle_response(milestones_resp)

    milestones = milestones_resp.json()
    if isinstance(milestones, dict):
        milestones = milestones.get("results", [])

    current = None
    for m in milestones:
        if m.get("id") == milestone_id:
            current = m
            break

    if current is None:
        return {"error": f"Milestone {milestone_id} not found in project {project_id}"}

    body = {
        "name": name if name is not None else current.get("name"),
        "status": status,
        "dueDate": due_date if due_date is not None else current.get("dueDate"),
        "completedDate": completed_date,
        "notes": notes if notes is not None else current.get("notes"),
        "sortOrder": sort_order if sort_order is not None else current.get("sortOrder"),
    }

    response = await client.put(
        f"/api/customers/{customer_id}/projects/{project_id}/milestones/{milestone_id}",
        json=body
    )
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

