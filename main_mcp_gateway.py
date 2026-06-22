import asyncio
import json
import logging
from typing import Optional

from fastapi import FastAPI, Request, HTTPException
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from sse_starlette.sse import EventSourceResponse
import uvicorn

from mcp.server import Server
from mcp.types import Tool, TextContent
from mcp.server.sse import SseServerTransport

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize FastAPI app
app = FastAPI(
    title="Quick Quote Travel Insurance (MCP Gateway)", 
    description="MCP Server providing tools over Server-Sent Events (SSE).",
    version="1.0.0"
)

# Enable CORS for open demo access
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"], # Open demo access
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Initialize MCP Server
mcp_server = Server("quick-quote-travel-insurance")

@mcp_server.list_tools()
async def list_tools() -> list[Tool]:
    """List available tools for the MCP server."""
    return [
        Tool(
            name="get_travel_insurance_quote",
            description="Calculate a quick travel insurance quote based on destination, age, duration, and coverage level.",
            inputSchema={
                "type": "object",
                "properties": {
                    "destination": {
                        "type": "string",
                        "description": "The destination country (e.g., 'USA', 'Europe', 'Japan')"
                    },
                    "age": {
                        "type": "integer",
                        "description": "Age of the traveler"
                    },
                    "duration_days": {
                        "type": "integer",
                        "description": "Duration of the trip in days"
                    },
                    "coverage_level": {
                        "type": "string",
                        "enum": ["Basic", "Standard", "Premium"],
                        "description": "Level of coverage desired (Basic, Standard, Premium)"
                    }
                },
                "required": ["destination", "age", "duration_days", "coverage_level"]
            }
        )
    ]

@mcp_server.call_tool()
async def call_tool(name: str, arguments: dict) -> list[TextContent]:
    """Handle tool calls from MCP clients."""
    if name != "get_travel_insurance_quote":
        raise ValueError(f"Unknown tool: {name}")
    
    destination = arguments.get("destination")
    age = arguments.get("age", 30)
    duration = arguments.get("duration_days", 7)
    coverage = arguments.get("coverage_level", "Standard")
    
    # Mock logic for quoting
    base_rate = 10.0
    age_factor = 1.5 if int(age) > 60 else 1.0
    coverage_multiplier = {"Basic": 1.0, "Standard": 1.5, "Premium": 2.5}.get(coverage, 1.0)
    
    total_cost = base_rate * int(duration) * age_factor * coverage_multiplier
    
    result = {
        "status": "success",
        "quote": {
            "estimated_cost_usd": round(total_cost, 2),
            "destination": destination,
            "duration_days": duration,
            "coverage_level": coverage,
            "notes": "This is a quick estimate from the MCP Server."
        }
    }
    return [TextContent(type="text", text=json.dumps(result, indent=2))]


# --- MCP Protocol Endpoints (SSE & JSON-RPC) ---
# Note: For production with multiple clients, we need a session manager. 
# This simple setup allows a basic connection for demo purposes.
sse_transports = {}

@app.get("/mcp/sse")
async def mcp_sse(request: Request):
    """
    MCP Server-Sent Events endpoint.
    Clients connect here FIRST to establish a long-lived streaming connection.
    APIM must NOT buffer this response.
    """
    transport = SseServerTransport("/mcp/messages")
    session_id = id(transport)
    sse_transports[session_id] = transport
    
    logger.info(f"New MCP SSE connection established. Session: {session_id}")
    
    async def sse_handler():
        try:
            asyncio.create_task(mcp_server.run(transport, transport.options, transport))
            async for message in transport.handle_sse(request):
                yield message
        finally:
            if session_id in sse_transports:
                del sse_transports[session_id]
                logger.info(f"MCP SSE connection closed. Session: {session_id}")

    return EventSourceResponse(sse_handler())

@app.post("/mcp/messages")
async def mcp_messages(request: Request):
    """
    MCP endpoint for clients to send JSON-RPC messages (like Tool calls).
    Clients POST here AFTER connecting to /mcp/sse.
    """
    if not sse_transports:
        raise HTTPException(status_code=400, detail="No active SSE connection")
    
    # Just grab the first one for the demo
    transport_id, transport = next(iter(sse_transports.items()))
    
    # process the POST message
    await transport.handle_post_message(request.scope, request.receive, request._send)
    return JSONResponse({"status": "ok"})


@app.get("/health")
async def health_check():
    """Health check endpoint for APIM and orchestrators."""
    return {"status": "healthy"}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
