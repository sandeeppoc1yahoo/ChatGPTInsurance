FROM python:3.11-slim

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy source code
COPY main_mcp_gateway.py .

# Expose port
EXPOSE 8000

# Run FastAPI app
CMD ["uvicorn", "main_mcp_gateway:app", "--host", "0.0.0.0", "--port", "8000"]
