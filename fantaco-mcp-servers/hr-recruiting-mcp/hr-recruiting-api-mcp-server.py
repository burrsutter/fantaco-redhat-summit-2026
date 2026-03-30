#!/usr/bin/env python3
"""
FastMCP server for Fantaco HR Recruiting API
Provides tools to use the Fantaco HR Recruiting Service API
Based on OpenAPI specification v0

Server Configuration:
    - Transport: streamable HTTP
    - Port: Configurable via PORT_FOR_HR_MCP (default: 9005)
    - Host: Configurable via HOST_FOR_HR_MCP (default: 0.0.0.0)

Environment Variables:
    HR_API_BASE_URL: Base URL for the HR Recruiting API
    PORT_FOR_HR_MCP: Port number for the MCP server (default: 9005)
    HOST_FOR_HR_MCP: Host address to bind to (default: 0.0.0.0)
"""

from fastmcp import FastMCP
from dotenv import load_dotenv
import asyncio
import httpx
import os
import logging
from typing import Optional, Dict, Any

# Initialize FastMCP server
mcp = FastMCP("hr-recruiting-api")

# Load environment variables from .env file
load_dotenv()

# Configuration
port = int(os.getenv("PORT_FOR_HR_MCP", "9005"))
host = os.getenv("HOST_FOR_HR_MCP", "0.0.0.0")
BASE_URL = os.getenv("HR_API_BASE_URL")

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


# ============================================================
# Job Tools
# ============================================================

@mcp.tool()
async def search_jobs(
    title: Optional[str] = None,
    status: Optional[str] = None
) -> Dict[str, Any]:
    """
    Search for jobs by title or status with partial matching

    Args:
        title: Filter by job title (partial matching, optional)
        status: Filter by job status e.g. OPEN, FILLED, CLOSED (optional)

    Returns:
        List of jobs matching the search criteria
    """
    params = {}

    if title:
        params["title"] = title
    if status:
        params["status"] = status

    client = await get_http_client()
    response = await client.get("/api/jobs", params=params)
    return await handle_response(response)


@mcp.tool()
async def get_job(job_id: str) -> Dict[str, Any]:
    """
    Get job by ID

    Retrieves a single job posting by its unique identifier

    Args:
        job_id: The unique identifier of the job (e.g., "job-001")

    Returns:
        Job details including jobId, title, description, postedAt, status,
        createdAt, and updatedAt
    """
    client = await get_http_client()
    response = await client.get(f"/api/jobs/{job_id}")
    return await handle_response(response)


@mcp.tool()
async def create_job(
    job_id: str,
    title: str,
    description: str,
    status: str,
    posted_at: Optional[str] = None
) -> Dict[str, Any]:
    """
    Create a new job posting

    Creates a new job record with the provided information

    Args:
        job_id: Unique job identifier (e.g., "job-006")
        title: Job title (e.g., "Senior Software Engineer")
        description: Full job description (max 5000 chars)
        status: Job status - OPEN, FILLED, or CLOSED
        posted_at: When the job was posted in ISO 8601 format (optional)

    Returns:
        The created job details
    """
    payload = {
        "jobId": job_id,
        "title": title,
        "description": description,
        "status": status,
    }
    if posted_at:
        payload["postedAt"] = posted_at

    client = await get_http_client()
    response = await client.post("/api/jobs", json=payload)
    return await handle_response(response)


@mcp.tool()
async def update_job(
    job_id: str,
    title: str,
    description: str,
    status: str,
    posted_at: Optional[str] = None
) -> Dict[str, Any]:
    """
    Update an existing job posting

    Updates all fields of an existing job record

    Args:
        job_id: The job ID to update (path parameter)
        title: Updated job title
        description: Updated job description
        status: Updated status - OPEN, FILLED, or CLOSED
        posted_at: Updated posted date in ISO 8601 format (optional)

    Returns:
        The updated job details
    """
    payload = {
        "title": title,
        "description": description,
        "status": status,
    }
    if posted_at:
        payload["postedAt"] = posted_at

    client = await get_http_client()
    response = await client.put(f"/api/jobs/{job_id}", json=payload)
    return await handle_response(response)


@mcp.tool()
async def delete_job(job_id: str) -> Dict[str, Any]:
    """
    Delete a job posting

    Permanently deletes a job record

    Args:
        job_id: The unique identifier of the job to delete

    Returns:
        Confirmation of deletion
    """
    client = await get_http_client()
    response = await client.delete(f"/api/jobs/{job_id}")
    return await handle_response(response)


# ============================================================
# Application Tools
# ============================================================

@mcp.tool()
async def search_applications(
    applicant_name: Optional[str] = None,
    status: Optional[str] = None,
    job_id: Optional[str] = None
) -> Dict[str, Any]:
    """
    Search for job applications by applicant name, status, or job ID

    Args:
        applicant_name: Filter by applicant name (partial matching, optional)
        status: Filter by application status e.g. SUBMITTED, UNDER_REVIEW,
                INTERVIEW_SCHEDULED, OFFER_EXTENDED, REJECTED (optional)
        job_id: Filter by associated job ID (optional)

    Returns:
        List of applications matching the search criteria
    """
    params = {}

    if applicant_name:
        params["applicantName"] = applicant_name
    if status:
        params["status"] = status
    if job_id:
        params["jobId"] = job_id

    client = await get_http_client()
    response = await client.get("/api/applications", params=params)
    return await handle_response(response)


@mcp.tool()
async def get_application(application_id: str) -> Dict[str, Any]:
    """
    Get application by ID

    Retrieves a single job application by its unique identifier

    Args:
        application_id: The unique identifier of the application (e.g., "app-001")

    Returns:
        Application details including applicationId, jobId, applicantName,
        applicantEmail, resumeData, status, submittedAt, createdAt, and updatedAt
    """
    client = await get_http_client()
    response = await client.get(f"/api/applications/{application_id}")
    return await handle_response(response)


@mcp.tool()
async def create_application(
    application_id: str,
    job_id: str,
    applicant_name: str,
    applicant_email: str,
    resume_data: str,
    status: str,
    submitted_at: Optional[str] = None
) -> Dict[str, Any]:
    """
    Create a new job application

    Creates a new application record for a job posting

    Args:
        application_id: Unique application identifier (e.g., "app-007")
        job_id: The job ID this application is for (e.g., "job-001")
        applicant_name: Full name of the applicant
        applicant_email: Email address of the applicant
        resume_data: Resume content or data
        status: Application status - SUBMITTED, UNDER_REVIEW,
                INTERVIEW_SCHEDULED, OFFER_EXTENDED, or REJECTED
        submitted_at: Submission timestamp in ISO 8601 format (optional)

    Returns:
        The created application details
    """
    payload = {
        "applicationId": application_id,
        "jobId": job_id,
        "applicantName": applicant_name,
        "applicantEmail": applicant_email,
        "resumeData": resume_data,
        "status": status,
    }
    if submitted_at:
        payload["submittedAt"] = submitted_at

    client = await get_http_client()
    response = await client.post("/api/applications", json=payload)
    return await handle_response(response)


@mcp.tool()
async def update_application(
    application_id: str,
    job_id: str,
    applicant_name: str,
    applicant_email: str,
    resume_data: str,
    status: str,
    submitted_at: Optional[str] = None
) -> Dict[str, Any]:
    """
    Update an existing job application

    Updates all fields of an existing application record

    Args:
        application_id: The application ID to update (path parameter)
        job_id: Updated associated job ID
        applicant_name: Updated applicant name
        applicant_email: Updated applicant email
        resume_data: Updated resume content
        status: Updated status - SUBMITTED, UNDER_REVIEW,
                INTERVIEW_SCHEDULED, OFFER_EXTENDED, or REJECTED
        submitted_at: Updated submission timestamp in ISO 8601 format (optional)

    Returns:
        The updated application details
    """
    payload = {
        "jobId": job_id,
        "applicantName": applicant_name,
        "applicantEmail": applicant_email,
        "resumeData": resume_data,
        "status": status,
    }
    if submitted_at:
        payload["submittedAt"] = submitted_at

    client = await get_http_client()
    response = await client.put(f"/api/applications/{application_id}", json=payload)
    return await handle_response(response)


@mcp.tool()
async def delete_application(application_id: str) -> Dict[str, Any]:
    """
    Delete a job application

    Permanently deletes an application record

    Args:
        application_id: The unique identifier of the application to delete

    Returns:
        Confirmation of deletion
    """
    client = await get_http_client()
    response = await client.delete(f"/api/applications/{application_id}")
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
    logger.info("HR Recruiting MCP Server Configuration:")
    logger.info(f"  HR_API_BASE_URL: {BASE_URL}")
    logger.info(f"  PORT_FOR_HR_MCP: {port}")
    logger.info(f"  HOST_FOR_HR_MCP: {host}")
    logger.info("=" * 60)

    try:
        mcp.run(transport="http", port=port, host=host)
    finally:
        asyncio.run(cleanup())
