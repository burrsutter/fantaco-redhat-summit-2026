import os
import logging
from typing import TypedDict, Any, List, Literal, Optional
from datetime import datetime
from contextlib import asynccontextmanager
from dataclasses import asdict

from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from pydantic import BaseModel
import pathlib

from evaluation import run_evaluation, sync_to_langfuse, load_local_test_cases

from langgraph.graph import StateGraph, END
from langchain_mcp_adapters.client import MultiServerMCPClient
from langchain_openai import ChatOpenAI
from langchain_core.messages import HumanMessage, AIMessage, SystemMessage, ToolMessage
from langfuse.langchain import CallbackHandler
from langfuse import get_client

# Load environment variables from the same directory as this script
_env_path = pathlib.Path(__file__).parent / ".env"
load_dotenv(_env_path)

# Configuration - load environment variables once
API_KEY = os.getenv("API_KEY", "not-needed")
INFERENCE_MODEL = os.getenv("INFERENCE_MODEL", "qwen3:14b-q8_0")
MODEL_BASE_URL = os.getenv("MODEL_BASE_URL", "http://localhost:11434")
# Ensure the URL ends with /v1 for OpenAI-compatible API
if not MODEL_BASE_URL.endswith("/v1"):
    MODEL_BASE_URL = MODEL_BASE_URL.rstrip("/") + "/v1"
LANGFUSE_SECRET_KEY = os.getenv("LANGFUSE_SECRET_KEY")
LANGFUSE_PUBLIC_KEY = os.getenv("LANGFUSE_PUBLIC_KEY")
LANGFUSE_HOST = os.getenv("LANGFUSE_HOST")
CUSTOMER_MCP_SERVER_URL = os.getenv("CUSTOMER_MCP_SERVER_URL", "http://localhost:9001/mcp")
FINANCE_MCP_SERVER_URL = os.getenv("FINANCE_MCP_SERVER_URL", "http://localhost:9002/mcp")
PORT = int(os.getenv("PORT", "8002"))

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Log environment variables at startup
def log_env_variables():
    """Log all expected environment variables and their current values."""
    logger.info("=" * 60)
    logger.info("ENVIRONMENT VARIABLES:")
    logger.info("=" * 60)
    logger.info(f"  API_KEY: {API_KEY[:10]}..." if API_KEY else "  API_KEY: NOT SET")
    logger.info(f"  INFERENCE_MODEL: {INFERENCE_MODEL}")
    logger.info(f"  MODEL_BASE_URL: {MODEL_BASE_URL}")
    logger.info(f"  LANGFUSE_SECRET_KEY: {LANGFUSE_SECRET_KEY[:20]}..." if LANGFUSE_SECRET_KEY else "  LANGFUSE_SECRET_KEY: NOT SET")
    logger.info(f"  LANGFUSE_PUBLIC_KEY: {LANGFUSE_PUBLIC_KEY}" if LANGFUSE_PUBLIC_KEY else "  LANGFUSE_PUBLIC_KEY: NOT SET")
    logger.info(f"  LANGFUSE_HOST: {LANGFUSE_HOST}" if LANGFUSE_HOST else "  LANGFUSE_HOST: NOT SET")
    logger.info(f"  CUSTOMER_MCP_SERVER_URL: {CUSTOMER_MCP_SERVER_URL}")
    logger.info(f"  FINANCE_MCP_SERVER_URL: {FINANCE_MCP_SERVER_URL}")
    logger.info(f"  PORT: {PORT}")
    logger.info("=" * 60)

log_env_variables()

# Pydantic models for API
class ChatRequest(BaseModel):
    message: str
    session_id: Optional[str] = None   # for your UI to pass a stable chat/session id
    user_id: Optional[str] = None      # optional: if your UI has auth/user info


class ChatResponse(BaseModel):
    reply: str
    tool_result: Any = None
    trace_id: Optional[str] = None


# Evaluation API models
class EvaluationRequest(BaseModel):
    run_name: Optional[str] = None
    sync_dataset: bool = True
    record_to_langfuse: bool = True


class TestCaseResultResponse(BaseModel):
    test_id: str
    test_name: str
    passed: bool
    score: float
    response: str
    trace_id: Optional[str]
    matched_keywords: List[str]
    missing_keywords: List[str]
    details: str
    duration_ms: float


class EvaluationResponse(BaseModel):
    run_name: str
    timestamp: str
    dataset_name: str
    total_tests: int
    passed: int
    failed: int
    pass_rate: float
    average_score: float
    duration_ms: float
    results: List[TestCaseResultResponse]


class SyncDatasetRequest(BaseModel):
    force_recreate: bool = False


class SyncDatasetResponse(BaseModel):
    dataset_name: str
    items_synced: int
    total_items: int
    version: str


# Feedback API models
class FeedbackRequest(BaseModel):
    trace_id: str
    score: int  # 1 = thumbs up, 0 = thumbs down
    comment: Optional[str] = None


class FeedbackResponse(BaseModel):
    success: bool
    message: str


class FeedbackItem(BaseModel):
    trace_id: str
    score: str  # "thumbs_up" or "thumbs_down"
    comment: Optional[str]
    created_at: Optional[str]


class FeedbackReportResponse(BaseModel):
    total: int
    positive: int
    negative: int
    feedback: List[FeedbackItem]


# LangGraph State
class State(TypedDict):
    messages: List[Any]


# Global variables for MCP clients and tools
mcp_clients = {}
all_tools = []


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Initialize MCP clients on startup and cleanup on shutdown"""
    global mcp_clients, all_tools

    logger.info("Initializing MCP clients...")

    # Connect to both MCP servers
    customer_mcp = MultiServerMCPClient(
        {
            "customer_mcp": {
                "transport": "http",
                "url": CUSTOMER_MCP_SERVER_URL,
            }
        }
    )

    finance_mcp = MultiServerMCPClient(
        {
            "finance_mcp": {
                "transport": "http",
                "url": FINANCE_MCP_SERVER_URL,
            }
        }
    )

    # Store clients
    mcp_clients = {
        "customer": customer_mcp,
        "finance": finance_mcp
    }

    # Get tools from both servers
    customer_tools = await customer_mcp.get_tools()
    finance_tools = await finance_mcp.get_tools()
    all_tools = customer_tools + finance_tools

    logger.info(f"MCP clients initialized. Available tools: {[t.name for t in all_tools]}")

    yield

    # Cleanup on shutdown
    logger.info("Shutting down MCP clients...")


# Create FastAPI app
app = FastAPI(
    title="LangGraph MCP Customer Service API",
    description="Customer service chatbot with MCP tools and Langfuse tracking",
    version="1.0.0",
    lifespan=lifespan
)

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # In production, specify actual origins
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


async def process_chat(message: str, session_id: Optional[str] = None, user_id: Optional[str] = None) -> tuple[str, Optional[str]]:
    """Process a chat message and return the response with trace ID"""

    logger.info(f"Processing message: {message[:50]}... (Session: {session_id}, User: {user_id})")

    # Get the global Langfuse client
    langfuse = get_client()

    # Initialize Langfuse CallbackHandler
    langfuse_handler = CallbackHandler()

    # Initialize LLM with tools and Langfuse callback
    llm = ChatOpenAI(
        model=INFERENCE_MODEL,
        base_url=MODEL_BASE_URL,
        api_key=API_KEY,
        temperature=0.7,
        callbacks=[langfuse_handler]
    )

    # Bind tools to LLM
    llm_with_tools = llm.bind_tools(all_tools)

    # Counter for tracking node executions
    node_counter = {"llm": 0, "tools": 0}

    # Define workflow nodes
    async def call_llm(state: State) -> State:
        """Call LLM with available tools"""
        messages = state["messages"]
        node_counter["llm"] += 1

        logger.debug(f"[LLM Call #{node_counter['llm']}] Invoking LLM with {len(messages)} messages")
        response = await llm_with_tools.ainvoke(messages, config={"callbacks": [langfuse_handler]})

        has_tool_calls = hasattr(response, 'tool_calls') and bool(response.tool_calls)
        logger.debug(f"[LLM Call #{node_counter['llm']}] Response received. Has tool calls: {has_tool_calls}")

        return {"messages": messages + [response]}

    async def call_tools(state: State) -> State:
        """Execute any tool calls requested by the LLM"""
        messages = state["messages"]
        last_message = messages[-1]
        node_counter["tools"] += 1

        tool_messages = []
        if hasattr(last_message, 'tool_calls') and last_message.tool_calls:
            logger.info(f"[Tool Execution] LLM requested {len(last_message.tool_calls)} tool call(s)")

            for tool_call in last_message.tool_calls:
                tool_name = tool_call["name"]
                tool_args = tool_call["args"]

                logger.info(f"  Calling tool: {tool_name} with args: {tool_args}")

                # Find the tool
                tool = next((t for t in all_tools if t.name == tool_name), None)
                if tool:
                    try:
                        # Tool calls are automatically tracked by CallbackHandler
                        result = await tool.ainvoke(tool_args, config={"callbacks": [langfuse_handler]})
                        result_text = result[0]['text'] if isinstance(result, list) else str(result)

                        if len(result_text) > 100:
                            logger.debug(f"  Tool result (truncated): {result_text[:100]}...")
                        else:
                            logger.debug(f"  Tool result: {result_text}")

                        tool_messages.append(
                            ToolMessage(
                                content=result_text,
                                tool_call_id=tool_call["id"],
                                name=tool_name
                            )
                        )
                    except Exception as e:
                        logger.error(f"  Tool execution error: {str(e)}")
                        tool_messages.append(
                            ToolMessage(
                                content=f"Error: {str(e)}",
                                tool_call_id=tool_call["id"],
                                name=tool_name
                            )
                        )

        return {"messages": messages + tool_messages}

    def should_continue(state: State) -> Literal["tools", "end"]:
        """Determine if we should call tools or end"""
        last_message = state["messages"][-1]
        if hasattr(last_message, 'tool_calls') and last_message.tool_calls:
            return "tools"
        return "end"

    # Build the graph
    workflow = StateGraph(State)
    workflow.add_node("llm", call_llm)
    workflow.add_node("tools", call_tools)

    workflow.set_entry_point("llm")
    workflow.add_conditional_edges("llm", should_continue, {"tools": "tools", "end": END})
    workflow.add_edge("tools", "llm")  # After tools, go back to LLM

    graph = workflow.compile()

    # Run the workflow wrapped in a Langfuse span for proper tracing
    system_message = SystemMessage(content="""You are a helpful customer service assistant with access to customer and order information.

Available tools:
- search_customers: Search for customers by name, company, email, or phone
- get_customer: Get customer details by customer ID
- fetch_order_history: Get order history for a customer by customer ID
- fetch_invoice_history: Get invoice history for a customer by customer ID

When a user asks about a customer:
1. First search for the customer to get their customer ID
2. Then fetch their orders if needed
3. Provide a clear, friendly summary

Be concise and helpful.""")

    # Use span context to ensure trace is properly created and captured
    with langfuse.start_as_current_span(name="customer-service-chat") as span:
        # Update trace with metadata
        span.update_trace(
            user_id=user_id,
            session_id=session_id,
            input={"message": message}
        )

        result = await graph.ainvoke(
            {
                "messages": [
                    system_message,
                    HumanMessage(content=message)
                ]
            },
            config={"callbacks": [langfuse_handler]}
        )

        # Extract final response
        final_response = ""
        if result.get("messages"):
            # Find the last AI message
            for msg in reversed(result["messages"]):
                if isinstance(msg, AIMessage) and msg.content:
                    final_response = msg.content
                    break

        # Update trace with output
        span.update_trace(output={"response": final_response})

        # Get trace ID from the span
        trace_id = span.trace_id

    # Flush Langfuse to ensure all trace data is sent
    langfuse.flush()

    if trace_id:
        logger.info(f"Request processed. Trace ID: {trace_id}")
        logger.info(f"View trace at: {LANGFUSE_HOST}/project/*/traces/{trace_id}")
    else:
        logger.warning("No trace ID generated - check Langfuse configuration")

    return final_response, trace_id


@app.get("/")
async def root():
    """Serve the frontend HTML"""
    # Get the path to the frontend HTML file
    frontend_path = pathlib.Path(__file__).parent.parent / "frontend" / "index.html"
    if frontend_path.exists():
        return FileResponse(frontend_path)
    else:
        # Fallback to API info if frontend not found
        return {
            "message": "LangGraph MCP Customer and Finance Service API",
            "version": "1.0.0",
            "status": "running",
            "available_tools": [t.name for t in all_tools],
            "note": "Frontend not found. Access /api for API info."
        }


@app.get("/api")
async def api_info():
    """API information endpoint"""
    return {
        "message": "LangGraph MCP Customer and Finance Service API",
        "version": "1.0.0",
        "status": "running",
        "available_tools": [t.name for t in all_tools]
    }


@app.get("/health")
async def health():
    """Health check endpoint"""
    return {
        "status": "healthy",
        "mcp_clients": list(mcp_clients.keys()),
        "tools_count": len(all_tools)
    }


@app.post("/chat", response_model=ChatResponse)
async def chat(request: ChatRequest):
    """
    Chat endpoint that processes user messages using LangGraph workflow

    Args:
        request: ChatRequest with message, optional session_id and user_id

    Returns:
        ChatResponse with reply, tool_result, and trace_id
    """
    try:
        logger.info(f"Received chat request: {request.message[:50]}...")

        # Process the chat message
        reply, trace_id = await process_chat(
            message=request.message,
            session_id=request.session_id,
            user_id=request.user_id
        )

        return ChatResponse(
            reply=reply,
            trace_id=trace_id
        )

    except Exception as e:
        logger.error(f"Error processing chat request: {str(e)}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/evaluate", response_model=EvaluationResponse)
async def run_evaluation_endpoint(request: EvaluationRequest):
    """
    Run evaluation against all test cases in the local dataset.

    - Optionally syncs local JSON to Langfuse dataset first
    - Executes each test case through process_chat
    - Scores responses using substring matching
    - Records results to Langfuse

    Returns detailed results for each test case and overall metrics.
    """
    # Path to test cases file
    test_cases_path = pathlib.Path(__file__).parent / "data" / "eval_test_cases.csv"

    if not test_cases_path.exists():
        raise HTTPException(
            status_code=404,
            detail=f"Test cases file not found: {test_cases_path}"
        )

    try:
        # Optionally sync to Langfuse first
        if request.sync_dataset:
            logger.info("Syncing test cases to Langfuse dataset...")
            sync_result = sync_to_langfuse(str(test_cases_path))
            logger.info(f"Synced {sync_result['items_synced']} items to {sync_result['dataset_name']}")

        # Run evaluation
        logger.info(f"Starting evaluation run: {request.run_name or 'auto-generated'}")
        result = await run_evaluation(
            test_cases_path=str(test_cases_path),
            process_chat_fn=process_chat,
            run_name=request.run_name,
            record_to_langfuse=request.record_to_langfuse
        )

        logger.info(f"Evaluation complete: {result.passed}/{result.total_tests} passed ({result.pass_rate:.1%})")

        # Convert dataclass to response model
        return EvaluationResponse(
            run_name=result.run_name,
            timestamp=result.timestamp,
            dataset_name=result.dataset_name,
            total_tests=result.total_tests,
            passed=result.passed,
            failed=result.failed,
            pass_rate=result.pass_rate,
            average_score=result.average_score,
            duration_ms=result.duration_ms,
            results=[
                TestCaseResultResponse(**asdict(r)) for r in result.results
            ]
        )

    except Exception as e:
        logger.error(f"Evaluation failed: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/sync-dataset", response_model=SyncDatasetResponse)
async def sync_dataset_endpoint(request: SyncDatasetRequest):
    """
    Sync local test cases JSON file to Langfuse dataset.

    Use this to update Langfuse with any changes made to the local file.
    """
    test_cases_path = pathlib.Path(__file__).parent / "data" / "eval_test_cases.csv"

    if not test_cases_path.exists():
        raise HTTPException(
            status_code=404,
            detail=f"Test cases file not found: {test_cases_path}"
        )

    try:
        result = sync_to_langfuse(
            str(test_cases_path),
            force_recreate=request.force_recreate
        )
        return SyncDatasetResponse(**result)

    except Exception as e:
        logger.error(f"Dataset sync failed: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/evaluation/test-cases")
async def get_test_cases():
    """
    Get the current local test cases for review.
    """
    test_cases_path = pathlib.Path(__file__).parent / "data" / "eval_test_cases.csv"

    if not test_cases_path.exists():
        raise HTTPException(
            status_code=404,
            detail=f"Test cases file not found: {test_cases_path}"
        )

    try:
        return load_local_test_cases(str(test_cases_path))
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/feedback", response_model=FeedbackResponse)
async def submit_feedback(request: FeedbackRequest):
    """
    Record user feedback (thumbs up/down) to Langfuse.

    - trace_id: The trace to attach feedback to
    - score: 1 for thumbs up, 0 for thumbs down
    - comment: Optional text feedback
    """
    try:
        langfuse = get_client()
        langfuse.create_score(
            trace_id=request.trace_id,
            name="user-feedback",
            value=request.score,
            comment=request.comment
        )
        langfuse.flush()

        logger.info(f"Recorded feedback for trace {request.trace_id}: score={request.score}")
        return FeedbackResponse(success=True, message="Feedback recorded")

    except Exception as e:
        logger.error(f"Failed to record feedback: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/feedback-report", response_model=FeedbackReportResponse)
async def get_feedback_report(limit: int = 100):
    """
    Get a report of all user feedback scores and comments.

    - limit: Maximum number of traces to check (default 100)
    """
    try:
        langfuse = get_client()

        # Get recent traces and extract user-feedback scores from each
        traces = langfuse.api.trace.list(limit=limit)

        feedback_items = []
        positive_count = 0
        negative_count = 0

        for trace in traces.data:
            # Get full trace details which includes scores
            trace_details = langfuse.api.trace.get(trace.id)

            if hasattr(trace_details, 'scores') and trace_details.scores:
                for score in trace_details.scores:
                    if score.name == "user-feedback":
                        is_positive = score.value == 1
                        if is_positive:
                            positive_count += 1
                        else:
                            negative_count += 1

                        feedback_items.append(FeedbackItem(
                            trace_id=trace.id,
                            score="thumbs_up" if is_positive else "thumbs_down",
                            comment=score.comment if hasattr(score, 'comment') else None,
                            created_at=str(score.created_at) if hasattr(score, 'created_at') and score.created_at else None
                        ))

        logger.info(f"Feedback report: {len(feedback_items)} items, {positive_count} positive, {negative_count} negative")

        return FeedbackReportResponse(
            total=len(feedback_items),
            positive=positive_count,
            negative=negative_count,
            feedback=feedback_items
        )

    except Exception as e:
        logger.error(f"Failed to get feedback report: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))


if __name__ == "__main__":
    import uvicorn

    port = PORT

    logger.info(f"Starting FastAPI server on port {port}...")

    uvicorn.run(
        app,
        host="0.0.0.0",
        port=port,
        log_level="info"
    )
