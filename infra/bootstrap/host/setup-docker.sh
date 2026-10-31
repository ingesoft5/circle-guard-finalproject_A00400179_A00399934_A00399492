#!/usr/bin/env bash
# Runs ON an EC2 host as root, streamed over SSH by infra/bootstrap-*.sh (never locally).
# Installs Docker Engine and the Compose plugin from Docker's official repository and applies
# the host settings of the role. Idempotent: it prints CG_RESULT lines and changes only what
# differs from the desired state.
#   usage: setup-docker.sh <role> <plan|apply>
set -Eeuo pipefail

ROLE=${1:?rol requerido}
MODE=${2:-plan}
result() { echo "CG_RESULT $*"; }
applying() { [[ "$MODE" == apply ]]; }
export DEBIAN_FRONTEND=noninteractive
APT=(apt-get -o DPkg::Lock::Timeout=600 -qq)

# On first boot cloud-init runs apt itself: wait for it before touching packages.
if command -v cloud-init >/dev/null 2>&1; then
  cloud-init status --wait >/dev/null 2>&1 || true
fi

installed() {
  # shellcheck disable=SC2016
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed'
}

# write_if_changed <path> <mode>: content from stdin. Returns 0 when the file differs (and
# writes it in apply mode), 1 when it already matches.
write_if_changed() {
  local tmp
  tmp=$(mktemp)
  cat >"$tmp"
  if [[ -f "$1" ]] && cmp -s "$tmp" "$1"; then
    rm -f "$tmp"
    return 1
  fi
  if applying; then install -D -m "$2" "$tmp" "$1"; fi
  rm -f "$tmp"
  return 0
}

# 1. Docker Engine and the Compose plugin.
if installed docker-ce && installed docker-compose-plugin; then
  result UNCHANGED "Docker $(docker version --format '{{.Server.Version}}' 2>/dev/null) y Compose $(docker compose version --short 2>/dev/null) instalados"
elif applying; then
  "${APT[@]}" update
  "${APT[@]}" install -y ca-certificates curl >/dev/null
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  # shellcheck disable=SC1091
  . /etc/os-release
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${UBUNTU_CODENAME:-$VERSION_CODENAME} stable" \
    >/etc/apt/sources.list.d/docker.list
  "${APT[@]}" update
  "${APT[@]}" install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null
  result CREATED "Docker $(docker version --format '{{.Server.Version}}') y Compose $(docker compose version --short) instalados desde el repositorio oficial de Docker"
else
  result PLAN "instalar Docker Engine y el plugin Compose (repositorio oficial de Docker)"
fi

# 2. Rotation of container logs, so a noisy container cannot fill the disk.
if printf '%s\n' '{' '  "log-driver": "json-file",' '  "log-opts": { "max-size": "10m", "max-file": "3" }' '}' |
  write_if_changed /etc/docker/daemon.json 0644; then
  if applying; then
    systemctl restart docker
    result UPDATED "/etc/docker/daemon.json con rotación de logs (10 MB x 3)"
  else
    result PLAN "configurar la rotación de logs de Docker en /etc/docker/daemon.json"
  fi
else
  result UNCHANGED "/etc/docker/daemon.json con rotación de logs"
fi

# 3. Docker starts on boot, so the stacks come back after a stop/start of the instance.
if installed docker-ce; then
  if systemctl is-enabled --quiet docker && systemctl is-active --quiet docker; then
    result UNCHANGED "servicio docker habilitado y activo"
  elif applying; then
    systemctl enable --now docker >/dev/null 2>&1
    result UPDATED "servicio docker habilitado y activo"
  else
    result PLAN "habilitar el servicio docker"
  fi
fi

# 4. SonarQube embeds Elasticsearch, which needs vm.max_map_count >= 524288. The value is only
#    raised, never lowered.
if [[ "$ROLE" == sonarqube ]]; then
  current=$(sysctl -n vm.max_map_count)
  if ((current >= 524288)); then
    result UNCHANGED "vm.max_map_count=$current (SonarQube requiere >= 524288)"
  elif applying; then
    printf 'vm.max_map_count=524288\n' | write_if_changed /etc/sysctl.d/99-circleguard-sonarqube.conf 0644 || true
    sysctl --system >/dev/null
    result UPDATED "vm.max_map_count=524288 para SonarQube"
  else
    result PLAN "subir vm.max_map_count a 524288 para SonarQube"
  fi
fi

# 5. Base directory of the stacks and environment files.
if [[ -d /opt/circleguard ]]; then
  result UNCHANGED "/opt/circleguard"
elif applying; then
  install -d -m 0755 /opt/circleguard
  result CREATED "/opt/circleguard"
else
  result PLAN "crear /opt/circleguard"
fi
