FROM python:3.11-slim

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application
COPY hr-policy-search-api-mcp-server.py .

# Run the MCP server
CMD ["python", "hr-policy-search-api-mcp-server.py"]
