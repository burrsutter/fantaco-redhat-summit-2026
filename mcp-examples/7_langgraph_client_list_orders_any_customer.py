import asyncio
from langgraph.graph import StateGraph, END, START
from langchain_openai import ChatOpenAI
from langchain_mcp_adapters.client import MultiServerMCPClient
from langchain_core.messages import HumanMessage, AIMessage, ToolMessage
from typing import Annotated, Literal, Any, List
from typing_extensions import TypedDict
from langgraph.graph.message import add_messages

import os
import sys
import json
import logging
from dotenv import load_dotenv

load_dotenv()

# Suppress noisy httpx logging
logging.getLogger("httpx").setLevel(logging.WARNING)

MODEL_BASE_URL = os.getenv("MODEL_BASE_URL", "http://localhost:11434")
INFERENCE_MODEL = os.getenv("INFERENCE_MODEL", "qwen3:14b-q8_0")
API_KEY = os.getenv("API_KEY", "fake")
CUSTOMER_MCP_SERVER_URL = os.getenv("CUSTOMER_MCP_SERVER_URL", "http://localhost:9001/mcp")
FINANCE_MCP_SERVER_URL = os.getenv("FINANCE_MCP_SERVER_URL", "http://localhost:9002/mcp")

print(f"Model URL: {MODEL_BASE_URL}")
print(f"Model:     {INFERENCE_MODEL}")


class State(TypedDict):
    messages: Annotated[list, add_messages]


async def main():
    # Parse command line argument for customer email
    if len(sys.argv) < 2:
        print("Usage: python 7_langgraph_client_list_orders_any_customer.py <customer_email>")
        print("Example: python 7_langgraph_client_list_orders_any_customer.py thomashardy@example.com")
        sys.exit(1)

    customer_email = sys.argv[1]

    llm = ChatOpenAI(
        model=INFERENCE_MODEL,
        openai_api_key=API_KEY,
        base_url=f"{MODEL_BASE_URL}/v1",
    )

    print("Testing LLM connectivity...")
    connectivity_response = llm.invoke("Hello")
    print("LLM connectivity OK")

    # Connect to both MCP servers and get tools (client-side)
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
    tools = await mcp_client.get_tools()
    print(f"Available tools: {[t.name for t in tools]}")

    llm_with_tools = llm.bind_tools(tools)

    async def call_llm(state: State) -> State:
        response = await llm_with_tools.ainvoke(state["messages"])
        return {"messages": [response]}

    async def call_tools(state: State) -> State:
        last_message = state["messages"][-1]
        tool_messages = []
        if hasattr(last_message, 'tool_calls') and last_message.tool_calls:
            for tool_call in last_message.tool_calls:
                tool = next((t for t in tools if t.name == tool_call["name"]), None)
                if tool:
                    result = await tool.ainvoke(tool_call["args"])
                    result_text = result[0]['text'] if isinstance(result, list) else str(result)
                    tool_messages.append(
                        ToolMessage(content=result_text, tool_call_id=tool_call["id"], name=tool_call["name"])
                    )
        return {"messages": tool_messages}

    def should_continue(state: State) -> Literal["tools", "end"]:
        last_message = state["messages"][-1]
        if hasattr(last_message, 'tool_calls') and last_message.tool_calls:
            return "tools"
        return "end"

    workflow = StateGraph(State)
    workflow.add_node("llm", call_llm)
    workflow.add_node("tools", call_tools)
    workflow.set_entry_point("llm")
    workflow.add_conditional_edges("llm", should_continue, {"tools": "tools", "end": END})
    workflow.add_edge("tools", "llm")
    graph = workflow.compile()

    print("\n" + "=" * 50)
    print(f"Finding orders for: {customer_email}")
    print("=" * 50)

    response = await graph.ainvoke(
        {"messages": [{"role": "user", "content": f"Find all orders for {customer_email}"}]})

    # Extract and display the final AI response
    for msg in reversed(response['messages']):
        if isinstance(msg, AIMessage) and msg.content:
            print(f"\nAssistant: {msg.content}\n")
            break


if __name__ == "__main__":
    asyncio.run(main())
