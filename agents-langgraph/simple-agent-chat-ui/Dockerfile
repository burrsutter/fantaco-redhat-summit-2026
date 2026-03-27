# Use Red Hat UBI Node.js image - works perfectly with OpenShift
FROM registry.access.redhat.com/ubi9/nodejs-20:latest

# Set working directory
WORKDIR /opt/app-root/src

# Copy package files and fix permissions for OpenShift arbitrary UID
COPY --chown=1001:0 package*.json ./

# Install dependencies
RUN npm ci --omit=dev && \
    npm cache clean --force

# Copy application files
COPY --chown=1001:0 server.js ./
COPY --chown=1001:0 public ./public

# Ensure group 0 can read all files (OpenShift runs with arbitrary UID in group 0)
RUN chmod -R g=u /opt/app-root/src

# Expose port (default 3000)
EXPOSE 3000

# Run as non-root user (already set by base image)
USER 1001

# Start the application
CMD ["node", "server.js"]
