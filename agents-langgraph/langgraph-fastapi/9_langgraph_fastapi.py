import asyncio
from contextlib import asynccontextmanager
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, EmailStr, Field
from langgraph.graph import StateGraph, END, START
from langchain_openai import ChatOpenAI
from langchain_mcp_adapters.client import MultiServerMCPClient
from langchain_core.messages import HumanMessage, AIMessage, ToolMessage
from typing import Annotated, Optional, Union, Literal, Any, List
from typing_extensions import TypedDict
from langgraph.graph.message import add_messages

import os
import json
import logging
from dotenv import load_dotenv

load_dotenv()

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Configuration
MODEL_BASE_URL = os.getenv("MODEL_BASE_URL", "http://localhost:11434")
INFERENCE_MODEL = os.getenv("INFERENCE_MODEL", "qwen3:14b-q8_0")
API_KEY = os.getenv("API_KEY", "fake")
CUSTOMER_MCP_SERVER_URL = os.getenv("CUSTOMER_MCP_SERVER_URL", "http://localhost:9001/mcp")
FINANCE_MCP_SERVER_URL = os.getenv("FINANCE_MCP_SERVER_URL", "http://localhost:9002/mcp")
FASTAPI_HOST = os.getenv("FASTAPI_HOST", "0.0.0.0")
FASTAPI_PORT = int(os.getenv("FASTAPI_PORT", "8000"))

logger.info("Configuration loaded:")
logger.info("  Model URL: %s", MODEL_BASE_URL)
logger.info("  Model: %s", INFERENCE_MODEL)
logger.info("  API Key: %s", "***" if API_KEY else "None")
logger.info("  Customer MCP: %s", CUSTOMER_MCP_SERVER_URL)
logger.info("  Finance MCP: %s", FINANCE_MCP_SERVER_URL)
logger.info("  FastAPI Host: %s", FASTAPI_HOST)
logger.info("  FastAPI Port: %s", FASTAPI_PORT)


# LangGraph State
class State(TypedDict):
    messages: Annotated[list, add_messages]


# Global variables for MCP tools and graph
all_tools = []
graph = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Initialize MCP clients and build graph on startup"""
    global all_tools, graph

    logger.info("Initializing LLM...")
    llm = ChatOpenAI(
        model=INFERENCE_MODEL,
        openai_api_key=API_KEY,
        base_url=f"{MODEL_BASE_URL}/v1",
    )

    logger.info("Testing LLM connectivity...")
    connectivity_response = llm.invoke("Hello")
    logger.info("LLM connectivity test successful")

    logger.info("Initializing MCP clients...")
    mcp_client = MultiServerMCPClient(
        {
            "customer_mcp": {
                "transport": "http",
                "url": CUSTOMER_MCP_SERVER_URL,
            },
            "finance_mcp": {
                "transport": "http",
                "url": FINANCE_MCP_SERVER_URL,
            }
        }
    )

    all_tools = await mcp_client.get_tools()
    logger.info(f"MCP clients initialized. Available tools: {[t.name for t in all_tools]}")

    llm_with_tools = llm.bind_tools(all_tools)

    # Define workflow nodes
    async def call_llm(state: State) -> State:
        response = await llm_with_tools.ainvoke(state["messages"])
        return {"messages": [response]}

    async def call_tools(state: State) -> State:
        last_message = state["messages"][-1]
        tool_messages = []
        if hasattr(last_message, 'tool_calls') and last_message.tool_calls:
            for tool_call in last_message.tool_calls:
                tool_name = tool_call["name"]
                tool = next((t for t in all_tools if t.name == tool_name), None)
                if tool:
                    try:
                        result = await tool.ainvoke(tool_call["args"])
                        result_text = result[0]['text'] if isinstance(result, list) else str(result)
                        tool_messages.append(
                            ToolMessage(content=result_text, tool_call_id=tool_call["id"], name=tool_name)
                        )
                    except Exception as e:
                        logger.error(f"Tool execution error for {tool_name}: {e}")
                        tool_messages.append(
                            ToolMessage(content=f"Error: {str(e)}", tool_call_id=tool_call["id"], name=tool_name)
                        )
        return {"messages": tool_messages}

    def should_continue(state: State) -> Literal["tools", "end"]:
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
    workflow.add_edge("tools", "llm")
    graph = workflow.compile()

    logger.info("LangGraph workflow compiled and ready")

    yield

    logger.info("Shutting down...")


# FastAPI app
app = FastAPI(
    title="Customer Orders and Invoices API",
    lifespan=lifespan
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# Response models
class Customer(BaseModel):
    customerId: str
    companyName: Optional[str] = None
    contactName: Optional[str] = None
    contactEmail: Optional[str] = None


class Order(BaseModel):
    id: Optional[Union[str, int]] = None
    orderId: Optional[Union[str, int]] = None
    orderNumber: Optional[str] = None
    orderDate: Optional[str] = None
    status: Optional[str] = None
    totalAmount: Optional[Union[str, int, float]] = None
    freight: Optional[Union[str, int, float]] = None


class Invoice(BaseModel):
    id: Optional[Union[str, int]] = None
    invoiceId: Optional[Union[str, int]] = None
    invoiceNumber: Optional[str] = None
    invoiceDate: Optional[str] = None
    status: Optional[str] = None
    totalAmount: Optional[Union[str, int, float]] = None
    amount: Optional[Union[str, int, float]] = None
    customerId: Optional[str] = None
    customerEmail: Optional[str] = None
    contactName: Optional[str] = None


class OrdersResponse(BaseModel):
    customer: Optional[Customer] = None
    orders: list[Order] = []
    total_orders: int = 0


class InvoicesResponse(BaseModel):
    customer: Optional[Customer] = None
    invoices: list[Invoice] = []
    total_invoices: int = 0


def extract_final_response(response) -> str:
    """Extract the final AI text response from graph output"""
    for msg in reversed(response['messages']):
        if isinstance(msg, AIMessage) and msg.content:
            if isinstance(msg.content, str):
                return msg.content
            elif isinstance(msg.content, list):
                text_parts = []
                for item in msg.content:
                    if isinstance(item, dict) and item.get('type') == 'text':
                        text_parts.append(item.get('text', ''))
                    elif isinstance(item, str):
                        text_parts.append(item)
                return " ".join(text_parts)
    return "No response generated"


@app.get("/")
def read_root():
    return {
        "message": "Customer Orders and Invoices API",
        "endpoints": {
            "find_orders": "/find_orders?email=<customer_email>",
            "find_invoices": "/find_invoices?email=<customer_email>",
            "question": "/question?q=<your_question>"
        }
    }


@app.get("/health")
async def health():
    return {
        "status": "healthy",
        "tools_count": len(all_tools),
        "available_tools": [t.name for t in all_tools]
    }


@app.get("/find_orders", response_model=OrdersResponse)
async def find_orders(email: EmailStr):
    """Find all orders for a customer by email address"""
    logger.info("=" * 80)
    logger.info("API: Finding orders for: %s", email)
    logger.info("=" * 80)

    try:
        response = await graph.ainvoke(
            {"messages": [{"role": "user", "content": f"Find all orders for {email}"}]})

        answer = extract_final_response(response)
        return OrdersResponse(
            customer=None,
            orders=[],
            total_orders=0
        )

    except Exception as e:
        logger.error("Error finding orders: %s", str(e))
        raise HTTPException(status_code=500, detail=f"Error finding orders: {str(e)}")


@app.get("/find_invoices", response_model=InvoicesResponse)
async def find_invoices(email: EmailStr):
    """Find all invoices for a customer by email address"""
    logger.info("=" * 80)
    logger.info("API: Finding invoices for: %s", email)
    logger.info("=" * 80)

    try:
        response = await graph.ainvoke(
            {"messages": [{"role": "user", "content": f"Find all invoices for {email}"}]})

        answer = extract_final_response(response)
        return InvoicesResponse(
            customer=None,
            invoices=[],
            total_invoices=0
        )

    except Exception as e:
        logger.error("Error finding invoices: %s", str(e))
        raise HTTPException(status_code=500, detail=f"Error finding invoices: {str(e)}")


@app.get("/question")
async def ask_question(q: str):
    """Answer a natural language question using the LangGraph chatbot"""
    logger.info("=" * 80)
    logger.info("API: Processing question: %s", q)
    logger.info("=" * 80)

    try:
        response = await graph.ainvoke(
            {"messages": [{"role": "user", "content": q}]})

        answer = extract_final_response(response)
        return {"question": q, "answer": answer}

    except Exception as e:
        logger.error("Error processing question: %s", str(e))
        raise HTTPException(status_code=500, detail=f"Error processing question: {str(e)}")


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host=FASTAPI_HOST, port=FASTAPI_PORT)
