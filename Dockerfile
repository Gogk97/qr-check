# ==============================================================================
# Multi-stage Dockerfile for Flutter Web (qr-check)
# Stage 1: Build Flutter Web assets
# Stage 2: Serve via ultra-lightweight Nginx Alpine
# ==============================================================================

# Stage 1: Build Environment
FROM ghcr.io/cirruslabs/flutter:3.24.0 AS builder

WORKDIR /app

# Optimize layer caching: copy dependency manifests first
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

# Copy source code and assets
COPY lib/ ./lib/
COPY web/ ./web/
COPY assets/ ./assets/

# Build production Flutter Web bundle
RUN flutter build web --release

# Stage 2: Production Server
FROM nginx:1.27-alpine AS runner

# Remove default nginx welcome page
RUN rm -rf /usr/share/nginx/html/*

# Copy custom Nginx configuration
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Copy compiled static assets from builder stage
COPY --from=builder /app/build/web /usr/share/nginx/html

EXPOSE 80

# Health check to ensure Nginx is serving
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD wget --quiet --tries=1 --spider http://127.0.0.1/ || exit 1

CMD ["nginx", "-g", "daemon off;"]
