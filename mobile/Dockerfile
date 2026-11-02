# syntax=docker/dockerfile:1
# CircleGuard web client (HU-02): Expo static export served by an unprivileged nginx.
# Build from the mobile/ directory:
#   docker build -f Dockerfile -t <registry>/circleguard/circleguard-web:<semver> .
#
# The web image is environment-agnostic. At build time the absolute localhost URLs
# of the Expo client are rewritten to same-origin paths ("/auth", "/identity", ...)
# and nginx reverse-proxies those paths to the services on the Compose network.
# This is a build-time transformation: the repository source is not modified.
# bookworm-slim (glibc) avoids optional native-module issues in the Expo build stage.
ARG NODE_IMAGE=node:22.22-bookworm-slim@sha256:e21fc383b50d5347dc7a9f1cae45b8f4e2f0d39f7ade28e4eef7d2934522b752
ARG NGINX_IMAGE=nginxinc/nginx-unprivileged:1.27-alpine@sha256:65e3e85dbaed8ba248841d9d58a899b6197106c23cb0ff1a132b7bfe0547e4c0

FROM ${NODE_IMAGE} AS build
WORKDIR /app
ENV CI=1 \
    EXPO_NO_TELEMETRY=1
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY . .
RUN sed -i \
        -e "s|http://localhost:8180|/auth|g" \
        -e "s|http://localhost:8083|/identity|g" \
        -e "s|http://localhost:8084|/dashboard|g" \
        -e "s|http://localhost:8085|/file|g" \
        -e "s|http://localhost:8086|/form|g" \
        -e "s|http://localhost:8087|/gateway|g" \
        -e "s|http://localhost:8082|/notification|g" \
        -e "s|http://localhost:8088|/promotion|g" \
        constants/Config.ts \
    && sed -i "s|http://localhost:8088|/promotion|g" utils/proximityTask.ts \
    && npx expo export --platform web --output-dir dist

FROM ${NGINX_IMAGE} AS runtime
ARG VERSION=0.0.0
ARG REVISION=unknown
ARG CREATED=unknown
LABEL org.opencontainers.image.title="CircleGuard web client" \
      org.opencontainers.image.description="Expo (React Native) web client served by nginx" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${REVISION}" \
      org.opencontainers.image.created="${CREATED}" \
      org.opencontainers.image.source="https://github.com/ingesoft5/circle-guard-finalproject_A00400179_A00399934_A00399492" \
      org.opencontainers.image.base.name="nginxinc/nginx-unprivileged:1.27-alpine"
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY nginx-proxy.inc /etc/nginx/cg-proxy.inc
COPY --from=build --chown=101:101 /app/dist /usr/share/nginx/html
USER 101
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=5 \
    CMD wget -q --spider http://127.0.0.1:8080/healthz || exit 1
# Keep the image's default entrypoint/CMD (nginx -g "daemon off;").
