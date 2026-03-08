# ─────────────────────────────────────────────────────────────────────────────
# Frontend Dockerfile — multi-stage build
# Stage 1: Build React app with Node.js
# Stage 2: Serve with Nginx (very lightweight — ~23MB image)
# ─────────────────────────────────────────────────────────────────────────────

# Stage 1: Build
FROM node:20-alpine AS builder
WORKDIR /app

COPY package*.json ./
RUN npm ci

COPY vite.config.js ./
COPY index.html ./
COPY src/ ./src/
COPY public/ ./public/

# Build for production (minified, optimized)
RUN npm run build -- --outDir /app/dist && ls -la /app

# Stage 2: Serve with Nginx
FROM nginx:1.25-alpine AS production

# Remove default Nginx config
RUN rm /etc/nginx/conf.d/default.conf

# Copy custom Nginx config
COPY nginx.conf /etc/nginx/conf.d/

# Copy built React app
COPY --from=builder /app/dist /usr/share/nginx/html

# Security: run Nginx as non-root
RUN chown -R nginx:nginx /usr/share/nginx/html && \
    chown -R nginx:nginx /var/cache/nginx && \
    chown -R nginx:nginx /var/log/nginx && \
    chown -R nginx:nginx /etc/nginx/conf.d && \
    touch /var/run/nginx.pid && \
    chown -R nginx:nginx /var/run/nginx.pid

USER nginx

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:8080/health || exit 1

CMD ["nginx", "-g", "daemon off;"]
