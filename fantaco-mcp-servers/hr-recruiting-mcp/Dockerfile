FROM python:3.11-slim

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application
COPY hr-recruiting-api-mcp-server.py .

# Run the MCP server
CMD ["python", "hr-recruiting-api-mcp-server.py"]
