import logging
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import uvicorn

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize FastAPI app
app = FastAPI(
    title="Quick Quote Travel Insurance (Standard REST API)", 
    description="Standard REST API for Travel Insurance Quotes. Open to the internet via APIM.",
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

class QuoteRequest(BaseModel):
    destination: str
    age: int
    duration_days: int
    coverage_level: str

@app.post("/api/quote", summary="Get Travel Insurance Quote")
async def get_quote_rest(request: QuoteRequest):
    """
    Standard REST endpoint to get a quote.
    This relies purely on HTTP POST and JSON, requiring no special MCP protocols.
    ChatGPT can call this directly if provided with the OpenAPI (Swagger) schema.
    """
    base_rate = 10.0
    age_factor = 1.5 if request.age > 60 else 1.0
    coverage_multiplier = {"Basic": 1.0, "Standard": 1.5, "Premium": 2.5}.get(request.coverage_level, 1.0)
    
    total_cost = base_rate * request.duration_days * age_factor * coverage_multiplier
    
    return {
        "status": "success",
        "quote": {
            "estimated_cost_usd": round(total_cost, 2),
            "destination": request.destination,
            "duration_days": request.duration_days,
            "coverage_level": request.coverage_level,
            "notes": "This is a quick estimate. Please proceed to the full portal for purchase."
        }
    }

@app.get("/health")
async def health_check():
    """Health check endpoint for APIM and orchestrators."""
    return {"status": "healthy"}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
