# syntax=docker/dockerfile:1
# CircleGuard auth service (HU-02). Reproducible multi-stage build, non-root runtime.
# Build from the repository root:
#   docker build -f services/circleguard-auth-service/Dockerfile -t <registry>/circleguard/circleguard-auth-service:<semver> .
ARG GRADLE_IMAGE=gradle:8.14-jdk21@sha256:aa72246029828dd4b4ddb5d4aba31f72ee070cafe52dc85ad5cc3296007ace6f
ARG RUNTIME_IMAGE=eclipse-temurin:21.0.13_9-jre-alpine-3.22@sha256:f816ce16bcad97d2e68420362bf37edd914a2a986b2b5aa4a7b3e7492128a0e8

FROM ${GRADLE_IMAGE} AS build
USER root
RUN mkdir -p /workspace && chown -R gradle:gradle /workspace
WORKDIR /workspace
COPY --chown=gradle:gradle gradle gradle
COPY --chown=gradle:gradle gradlew settings.gradle.kts build.gradle.kts ./
COPY --chown=gradle:gradle services services
USER gradle
RUN --mount=type=cache,target=/home/gradle/.gradle,uid=1000,gid=1000 \
    gradle :services:circleguard-auth-service:bootJar -x test --no-daemon --console=plain

FROM ${RUNTIME_IMAGE} AS runtime
ARG VERSION=0.0.0
ARG REVISION=unknown
ARG CREATED=unknown
LABEL org.opencontainers.image.title="CircleGuard auth service" \
      org.opencontainers.image.description="Dual-chain LDAP/local authentication and signed QR tokens" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${REVISION}" \
      org.opencontainers.image.created="${CREATED}" \
      org.opencontainers.image.source="https://github.com/ingesoft5/circle-guard-finalproject_A00400179_A00399934_A00399492" \
      org.opencontainers.image.base.name="eclipse-temurin:21.0.13_9-jre-alpine-3.22"
RUN addgroup -S -g 10001 circleguard \
    && adduser -S -u 10001 -G circleguard -h /app -s /sbin/nologin circleguard \
    && apk add --no-cache curl
WORKDIR /app
COPY --from=build --chown=10001:10001 /workspace/services/circleguard-auth-service/build/libs/*.jar /app/app.jar
USER 10001:10001
EXPOSE 8180
ENV JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=75 -XX:+ExitOnOutOfMemoryError"
HEALTHCHECK --interval=30s --timeout=5s --start-period=90s --retries=5 \
    CMD curl -sS -o /dev/null -w "%{http_code}" http://127.0.0.1:8180/ | grep -qE "^(200|301|302|400|401|403|404)$" || exit 1
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
