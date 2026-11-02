# syntax=docker/dockerfile:1
# CircleGuard dashboard service (HU-02). Reproducible multi-stage build, non-root runtime.
# Build from the repository root:
#   docker build -f services/circleguard-dashboard-service/Dockerfile -t <registry>/circleguard/circleguard-dashboard-service:<semver> .
ARG GRADLE_IMAGE=gradle:8.14-jdk21@sha256:aa72246029828dd4b4ddb5d4aba31f72ee070cafe52dc85ad5cc3296007ace6f
ARG RUNTIME_IMAGE=eclipse-temurin:21.0.9_10-jre-alpine@sha256:08eecc477dbe3f2e33daac27f36e41daf7f4ec51d2f3396006e54fa41832c74c

FROM ${GRADLE_IMAGE} AS build
USER root
RUN mkdir -p /workspace && chown -R gradle:gradle /workspace
WORKDIR /workspace
COPY --chown=gradle:gradle gradle gradle
COPY --chown=gradle:gradle gradlew settings.gradle.kts build.gradle.kts ./
COPY --chown=gradle:gradle services services
USER gradle
RUN --mount=type=cache,target=/home/gradle/.gradle,uid=1000,gid=1000 \
    gradle :services:circleguard-dashboard-service:bootJar -x test --no-daemon --console=plain

FROM ${RUNTIME_IMAGE} AS runtime
ARG VERSION=0.0.0
ARG REVISION=unknown
ARG CREATED=unknown
LABEL org.opencontainers.image.title="CircleGuard dashboard service" \
      org.opencontainers.image.description="Privacy-preserving geospatial hotspot analytics" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${REVISION}" \
      org.opencontainers.image.created="${CREATED}" \
      org.opencontainers.image.source="https://github.com/ingesoft5/circle-guard-finalproject_A00400179_A00399934_A00399492" \
      org.opencontainers.image.base.name="eclipse-temurin:21.0.9_10-jre-alpine"
RUN addgroup -S -g 10001 circleguard \
    && adduser -S -u 10001 -G circleguard -h /app -s /sbin/nologin circleguard \
    && apk add --no-cache curl
WORKDIR /app
COPY --from=build --chown=10001:10001 /workspace/services/circleguard-dashboard-service/build/libs/*.jar /app/app.jar
USER 10001:10001
EXPOSE 8084
ENV JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=75 -XX:+ExitOnOutOfMemoryError"
HEALTHCHECK --interval=30s --timeout=5s --start-period=90s --retries=5 \
    CMD curl -sS -o /dev/null -w "%{http_code}" http://127.0.0.1:8084/ | grep -qE "^(200|301|302|400|401|403|404)$" || exit 1
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
