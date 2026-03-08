# ─────────────────────────────────────────────────────────────────────────────
# Backend Dockerfile — multi-stage build for minimal production image
# Stage 1: Install dependencies (heavy, node_modules)
# Stage 2: Production image (only runtime deps + compiled code)
# ─────────────────────────────────────────────────────────────────────────────

# Stage 1: Builder
FROM node:20-alpine AS builder
WORKDIR /app

# Copy package files first — leverages Docker layer caching
# npm install only re-runs when package.json/lock changes
COPY package*.json ./
RUN npm ci --omit=dev

# Stage 2: Production
FROM node:20-alpine AS production
WORKDIR /app

# node:20-alpine already has a built-in 'node' user (UID/GID 1000)
# Copy only what we need from the builder stage
COPY --from=builder /app/node_modules ./node_modules
COPY src/ ./src/
COPY package.json ./

# Change ownership to built-in node user
RUN chown -R node:node /app

USER node

EXPOSE 3000

# Health check — used by Docker and K8s liveness probe
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:3000/health || exit 1

CMD ["node", "src/server.js"]
