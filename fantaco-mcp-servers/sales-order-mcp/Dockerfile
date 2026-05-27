FROM python:3.11-slim

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application
COPY sales-order-api-mcp-server.py .

# Run the MCP server with OTEL auto-instrumentation
CMD ["opentelemetry-instrument", "python", "sales-order-api-mcp-server.py"]
