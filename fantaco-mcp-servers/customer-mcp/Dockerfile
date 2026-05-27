FROM python:3.11-slim

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application
COPY customer-api-mcp-server.py .

# Run the MCP server with OTEL auto-instrumentation
CMD ["opentelemetry-instrument", "python", "customer-api-mcp-server.py"]
