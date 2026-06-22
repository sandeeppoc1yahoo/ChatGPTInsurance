import azure.functions as func
import json
import os

app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)

_BASE_DIR = os.path.dirname(os.path.abspath(__file__))
_HTML_PATH = os.path.join(_BASE_DIR, "index.html")


def _apim_base_url(req: func.HttpRequest) -> str:
    for header in ("X-Forwarded-Host", "X-Original-Host", "Host"):
        host = req.headers.get(header, "")
        if host and "azure-api.net" in host:
            return f"https://{host.split(',')[0].strip()}/quote"

    site = os.environ.get("WEBSITE_SITE_NAME", "")
    if site.endswith("-func"):
        apim_host = site.replace("-func", "-apim") + ".azure-api.net"
        return f"https://{apim_host}/quote"

    host = req.headers.get("Host", "localhost")
    return f"https://{host}/quote"


def _build_openapi_spec(base_url: str) -> dict:
    return {
        "openapi": "3.1.0",
        "info": {
            "title": "Quick Quote Travel Insurance API",
            "description": (
                "Returns an estimated travel insurance quote. Use when the user asks "
                "for a travel insurance price, quote, or cost estimate."
            ),
            "version": "1.0.0",
        },
        "servers": [{"url": base_url, "description": "Azure API Management gateway"}],
        "paths": {
            "/quote": {
                "post": {
                    "operationId": "getTravelInsuranceQuote",
                    "summary": "Get a travel insurance quote",
                    "description": (
                        "Calculates an estimated travel insurance premium in USD. "
                        "Extract destination, age, duration_days, and coverage_level "
                        "from the conversation. If coverage is not specified, use Standard."
                    ),
                    "requestBody": {
                        "required": True,
                        "content": {
                            "application/json": {
                                "schema": {
                                    "type": "object",
                                    "required": ["destination", "age", "duration_days", "coverage_level"],
                                    "properties": {
                                        "destination": {
                                            "type": "string",
                                            "description": "Country or region being visited (e.g. Japan, Europe, USA)",
                                        },
                                        "age": {
                                            "type": "integer",
                                            "description": "Age of the traveler in years",
                                            "minimum": 1,
                                            "maximum": 120,
                                        },
                                        "duration_days": {
                                            "type": "integer",
                                            "description": "Total trip length in days",
                                            "minimum": 1,
                                            "maximum": 365,
                                        },
                                        "coverage_level": {
                                            "type": "string",
                                            "description": "Basic (budget), Standard (recommended), or Premium (comprehensive)",
                                            "enum": ["Basic", "Standard", "Premium"],
                                        },
                                    },
                                },
                                "example": {
                                    "destination": "Japan",
                                    "age": 35,
                                    "duration_days": 10,
                                    "coverage_level": "Standard",
                                },
                            }
                        },
                    },
                    "responses": {
                        "200": {
                            "description": "Quote calculated successfully",
                            "content": {
                                "application/json": {
                                    "schema": {
                                        "type": "object",
                                        "properties": {
                                            "status": {"type": "string"},
                                            "quote": {
                                                "type": "object",
                                                "properties": {
                                                    "estimated_cost_usd": {
                                                        "type": "number",
                                                        "description": "Estimated premium in US dollars",
                                                    },
                                                    "destination": {"type": "string"},
                                                    "traveler_age": {"type": "integer"},
                                                    "duration_days": {"type": "integer"},
                                                    "coverage_level": {"type": "string"},
                                                    "notes": {"type": "string"},
                                                },
                                            },
                                        },
                                    }
                                }
                            },
                        },
                        "400": {"description": "Invalid request body"},
                    },
                }
            }
        },
    }


@app.route(route="openapi.json", methods=["GET"])
def openapi_spec(req: func.HttpRequest) -> func.HttpResponse:
    """OpenAPI schema for ChatGPT Actions / GPT Store."""
    spec = _build_openapi_spec(_apim_base_url(req))
    return func.HttpResponse(
        json.dumps(spec, indent=2),
        mimetype="application/json",
        status_code=200,
    )


@app.route(route="ui", methods=["GET"])
def quote_ui(req: func.HttpRequest) -> func.HttpResponse:
    """Serve the browser UI for Quick Quote."""
    with open(_HTML_PATH, encoding="utf-8") as f:
        html = f.read()
    return func.HttpResponse(html, mimetype="text/html", status_code=200)


@app.route(route="quote", methods=["GET", "POST"])
def get_quote(req: func.HttpRequest) -> func.HttpResponse:
    """Quick Quote Travel Insurance - HTTP Trigger (no auth required)"""
    if req.method == "GET":
        return func.HttpResponse(
            json.dumps({"message": "POST JSON to this endpoint, or open /api/ui in your browser."}),
            mimetype="application/json",
            status_code=200,
        )

    try:
        body = req.get_json()
    except Exception:
        return func.HttpResponse(
            json.dumps({"error": "Please send a JSON body with destination, age, duration_days, coverage_level"}),
            mimetype="application/json", status_code=400
        )

    destination = body.get("destination", "Unknown")
    age = int(body.get("age", 30))
    duration = int(body.get("duration_days", 7))
    coverage = body.get("coverage_level", "Standard")

    base_rate = 10.0
    age_factor = 1.5 if age > 60 else 1.0
    coverage_multiplier = {"Basic": 1.0, "Standard": 1.5, "Premium": 2.5}.get(coverage, 1.0)
    total_cost = round(base_rate * duration * age_factor * coverage_multiplier, 2)

    result = {
        "status": "success",
        "quote": {
            "estimated_cost_usd": total_cost,
            "destination": destination,
            "traveler_age": age,
            "duration_days": duration,
            "coverage_level": coverage,
            "notes": "Quick estimate via Azure Functions behind APIM."
        }
    }
    return func.HttpResponse(json.dumps(result), mimetype="application/json", status_code=200)
