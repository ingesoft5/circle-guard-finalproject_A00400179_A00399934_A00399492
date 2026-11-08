# Jenkins controller of CircleGuard (HU-01): pinned LTS core plus the pinned Configuration as
# Code plugin, so the controller starts fully configured by casc/jenkins.yaml.
FROM jenkins/jenkins:2.580.2-lts-jdk21

COPY --chown=jenkins:jenkins plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt

# crane (go-containerregistry, Apache 2.0) publishes and pulls images in the CircleGuard registry
# (CNCF Distribution) without a Docker daemon.
# Pinned release, verified against the sha256 of its published checksums.txt.
ARG CRANE_VERSION=v0.22.1
ARG CRANE_SHA256=0ab7a1d6932a213aed964ce97666c3077fe691c8606413674a8b3e0b9ec4cda0
USER root
RUN curl -fsSLo /tmp/crane.tgz "https://github.com/google/go-containerregistry/releases/download/${CRANE_VERSION}/go-containerregistry_Linux_x86_64.tar.gz" \
  && echo "${CRANE_SHA256}  /tmp/crane.tgz" | sha256sum -c - \
  && tar -xzf /tmp/crane.tgz -C /usr/local/bin crane \
  && rm -f /tmp/crane.tgz \
  && crane version

# Docker CLI + Compose/buildx plugins for the DinD daemon (HU-06 pipeline and HU-04 Testcontainers).
ARG DOCKER_VERSION=27.5.1
ARG COMPOSE_VERSION=v2.32.4
ARG BUILDX_VERSION=v0.20.1
RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates curl gnupg \
  && curl -fsSLo /tmp/docker.tgz "https://download.docker.com/linux/static/stable/x86_64/docker-${DOCKER_VERSION}.tgz" \
  && tar -xzf /tmp/docker.tgz -C /tmp \
  && install -m 0755 /tmp/docker/docker /usr/local/bin/docker \
  && mkdir -p /usr/local/lib/docker/cli-plugins \
  && curl -fsSLo /usr/local/lib/docker/cli-plugins/docker-compose "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-x86_64" \
  && curl -fsSLo /usr/local/lib/docker/cli-plugins/docker-buildx "https://github.com/docker/buildx/releases/download/${BUILDX_VERSION}/buildx-${BUILDX_VERSION}.linux-amd64" \
  && chmod +x /usr/local/lib/docker/cli-plugins/docker-compose /usr/local/lib/docker/cli-plugins/docker-buildx \
  && rm -rf /tmp/docker /tmp/docker.tgz

# Node 22 + Playwright OS dependencies for the E2E gate (HU-06). The browser itself is downloaded
# into the jenkins_home cache on the first E2E run.
ARG NODE_MAJOR=22
ARG PLAYWRIGHT_VERSION=1.55.0
RUN curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash - \
  && apt-get install -y --no-install-recommends nodejs \
  && npx --yes "playwright@${PLAYWRIGHT_VERSION}" install-deps chromium \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

USER jenkins
