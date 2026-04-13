# ============================================================
# Production-ready Dockerfile for Portfolio Website
# Multi-stage build using Nginx Alpine for serving static files
# ============================================================

# Stage 1: Build / Validation stage
FROM alpine:3.20 AS validator
WORKDIR /app
COPY . .
# Validate that critical files exist
RUN test -f index.html && echo "index.html found" || (echo "ERROR: index.html not found" && exit 1)
RUN test -f style.css && echo "style.css found" || (echo "ERROR: style.css not found" && exit 1)
# Stage optional JS files for conditional copy
RUN mkdir -p /transfer && \
    if ls /app/app.js* 1>/dev/null 2>&1; then cp /app/app.js* /transfer/; fi

# Stage 2: Production stage
FROM nginx:1.27-alpine AS production

# Add labels for container metadata
LABEL maintainer="sakshiths@ideyalabs.com"
LABEL description="Portfolio Website - Production Container"
LABEL version="1.0.0"

# Install curl for healthcheck
RUN apk add --no-cache curl

# Remove default Nginx static assets and config
RUN rm -rf /usr/share/nginx/html/* \
    && rm -f /etc/nginx/conf.d/default.conf

# Copy custom Nginx configuration
COPY nginx/nginx.conf /etc/nginx/nginx.conf
COPY nginx/default.conf /etc/nginx/conf.d/default.conf

# Copy static website files from validator stage
COPY --from=validator /app/index.html /usr/share/nginx/html/
COPY --from=validator /app/style.css /usr/share/nginx/html/
COPY --from=validator /app/image.jpeg /usr/share/nginx/html/

# Copy any additional JS files if they exist (staged in validator)
COPY --from=validator /transfer/ /usr/share/nginx/html/

# Set proper file ownership for Nginx
RUN chown -R nginx:nginx /usr/share/nginx/html \
    && chmod -R 755 /usr/share/nginx/html

# Create required directories for Nginx to run as non-root
RUN mkdir -p /var/cache/nginx/client_temp \
    && mkdir -p /var/cache/nginx/proxy_temp \
    && mkdir -p /var/cache/nginx/fastcgi_temp \
    && mkdir -p /var/cache/nginx/uwsgi_temp \
    && mkdir -p /var/cache/nginx/scgi_temp \
    && chown -R nginx:nginx /var/cache/nginx \
    && chown -R nginx:nginx /var/log/nginx \
    && touch /var/run/nginx.pid \
    && chown nginx:nginx /var/run/nginx.pid

# Expose port 8080 (non-privileged port)
EXPOSE 8080

# Healthcheck to verify the container is serving content
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:8080/healthz || exit 1

# Switch to non-root user
USER nginx

# Run Nginx in the foreground
CMD ["nginx", "-g", "daemon off;"]
