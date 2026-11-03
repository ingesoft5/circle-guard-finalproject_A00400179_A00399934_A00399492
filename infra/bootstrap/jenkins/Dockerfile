# Jenkins controller of CircleGuard (HU-01): pinned LTS core plus the pinned Configuration as
# Code plugin, so the controller starts fully configured by casc/jenkins.yaml.
FROM jenkins/jenkins:2.580.2-lts-jdk21

COPY --chown=jenkins:jenkins plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt

# crane (go-containerregistry, Apache 2.0) publishes and pulls images in the CircleGuard registry
# (CNCF Distribution) without a Docker daemon: Jenkins never gets the host's Docker socket.
# Pinned release, verified against the sha256 of its published checksums.txt.
ARG CRANE_VERSION=v0.22.1
ARG CRANE_SHA256=0ab7a1d6932a213aed964ce97666c3077fe691c8606413674a8b3e0b9ec4cda0
USER root
RUN curl -fsSLo /tmp/crane.tgz "https://github.com/google/go-containerregistry/releases/download/${CRANE_VERSION}/go-containerregistry_Linux_x86_64.tar.gz" \
  && echo "${CRANE_SHA256}  /tmp/crane.tgz" | sha256sum -c - \
  && tar -xzf /tmp/crane.tgz -C /usr/local/bin crane \
  && rm -f /tmp/crane.tgz \
  && crane version
USER jenkins
