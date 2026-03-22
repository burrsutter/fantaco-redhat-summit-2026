FROM python:3.11-slim

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application
COPY sales-order-api-mcp-server.py .

# Run the MCP server
CMD ["python", "sales-order-api-mcp-server.py"]
