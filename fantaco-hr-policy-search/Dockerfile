FROM python:3.11-slim

WORKDIR /app

# Install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Set cache directories to /app/.cache so they are accessible by any UID.
# OpenShift runs containers with a random UID (not root), so the default
# /root/.cache is not writable. These env vars tell HuggingFace/transformers
# to use /app/.cache instead.
ENV HF_HOME=/app/.cache \
    SENTENCE_TRANSFORMERS_HOME=/app/.cache/sentence_transformers

# Pre-download the embedding model at build time (avoids runtime download).
# Then make the cache world-readable AND writable so any OpenShift random UID
# can use it. HuggingFace Hub writes .no_exist cache files at runtime.
RUN python -c "from sentence_transformers import SentenceTransformer; SentenceTransformer('nomic-ai/nomic-embed-text-v1.5', trust_remote_code=True)" \
    && chmod -R a+rwX /app/.cache

# Copy application
COPY . .

# Expose port
EXPOSE 8091

# Run the application
CMD ["python", "app.py"]
