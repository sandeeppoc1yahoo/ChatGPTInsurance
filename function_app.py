import azure.functions as func
import json

app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)

@app.route(route="quote", methods=["GET", "POST"])
def get_quote(req: func.HttpRequest) -> func.HttpResponse:
    """Quick Quote Travel Insurance - HTTP Trigger (no auth required)"""
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
