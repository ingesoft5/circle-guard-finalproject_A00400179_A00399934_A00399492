# Jenkins controller of CircleGuard (HU-01): pinned LTS core plus the pinned Configuration as
# Code plugin, so the controller starts fully configured by casc/jenkins.yaml.
FROM jenkins/jenkins:2.580.2-lts-jdk21

COPY --chown=jenkins:jenkins plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt
