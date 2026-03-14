# syntax=docker/dockerfile:1

# ─── Build stage ─────────────────────────────────────────────
FROM node:18-alpine AS builder

WORKDIR /app

# Copy dependency manifests first (layer cache)
COPY package.json package-lock.json ./
RUN npm ci --only=production

COPY . .

# ─── Frontend build ───────────────────────────────────────────
RUN npm run build

# ─── Production stage ────────────────────────────────────────
FROM node:18-alpine AS production

WORKDIR /app

# Copy backend
COPY server/package.json server/package-lock.json ./server/
RUN cd server && npm ci --only=production

COPY server/ ./server/

# Copy built frontend (served by Express in production)
COPY --from=builder /app/dist ./dist

EXPOSE 5000

ENV NODE_ENV=production

CMD ["node", "server/index.js"]
