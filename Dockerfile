# ── Args ──────────────────────────────────────────────────────────────
ARG BACKEND_REPO=https://github.com/galinilin/docgemma-connect.git
ARG BACKEND_REF=main
ARG FRONTEND_REPO=https://github.com/galinilin/docgemma-frontend.git
ARG FRONTEND_REF=main

# ── Stage 1: Clone sources ───────────────────────────────────────────
FROM alpine/git:latest AS sources

ARG BACKEND_REPO
ARG BACKEND_REF
ARG FRONTEND_REPO
ARG FRONTEND_REF

RUN git clone --depth 1 --branch ${BACKEND_REF} ${BACKEND_REPO} /src/backend
RUN git clone --depth 1 --branch ${FRONTEND_REF} ${FRONTEND_REPO} /src/frontend

# ── Stage 2: Build frontend ─────────────────────────────────────────
FROM node:20-alpine AS frontend-build

WORKDIR /build
COPY --from=sources /src/frontend/package.json /src/frontend/package-lock.json ./
RUN npm ci

COPY --from=sources /src/frontend/ .
ENV VITE_API_URL=/api
RUN npm run build

# ── Stage 3: Production image ───────────────────────────────────────
FROM python:3.12-slim AS production

COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/

WORKDIR /app

# Install Python dependencies (README.md needed by hatchling build)
COPY --from=sources /src/backend/pyproject.toml /src/backend/uv.lock /src/backend/README.md ./
RUN uv sync --frozen --no-dev

# Copy backend source
COPY --from=sources /src/backend/src/ src/

# Copy FHIR seed data to a separate location (entrypoint copies if /app/data is empty)
COPY --from=sources /src/backend/data/ data-seed/

# Copy built frontend into static/ (where FastAPI serves it)
COPY --from=frontend-build /build/dist/ static/

# Entrypoint: seed data on first run, then start server
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

ENV FHIR_DATA_DIR=/app/data/fhir
ENV DOCGEMMA_SESSIONS_DIR=/app/data/sessions

EXPOSE 8000

ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["uv", "run", "docgemma-serve"]
