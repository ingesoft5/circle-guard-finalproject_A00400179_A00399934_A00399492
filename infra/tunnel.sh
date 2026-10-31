#!/usr/bin/env bash
# HU-01 · Administrative access to Jenkins, SonarQube and Nexus through an SSH tunnel.
# The tool UIs speak plain HTTP, so they are never opened to the Internet: the security groups
# only allow SSH from ADMIN_CIDRS, and this script forwards a local port over that encrypted
# connection. It does not create or modify AWS resources.

# shellcheck source=bootstrap/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/bootstrap/lib/common.sh"
# shellcheck source=bootstrap/lib/aws.sh
source "$INFRA_DIR/bootstrap/lib/aws.sh"
# shellcheck source=bootstrap/lib/remote.sh
source "$INFRA_DIR/bootstrap/lib/remote.sh"

usage() {
  cat <<'EOF'
Uso: infra/tunnel.sh <jenkins|sonarqube|nexus> [puerto-local]
  Abre un túnel SSH y deja la interfaz en http://localhost:<puerto-local> (Ctrl+C para cerrarlo).
  Puertos locales por defecto: jenkins 8080, sonarqube 9000, nexus 8081.
EOF
}

cg_parse_flags "$@"
cg_load_config
TOOL=${CG_ARGS[0]:-}
case "$TOOL" in
  jenkins) REMOTE_PORT=$JENKINS_HTTP_PORT ;;
  sonarqube) REMOTE_PORT=$SONARQUBE_HTTP_PORT ;;
  nexus) REMOTE_PORT=$NEXUS_HTTP_PORT ;;
  *) usage; exit 1 ;;
esac
LOCAL_PORT=${CG_ARGS[1]:-$REMOTE_PORT}
[[ "$LOCAL_PORT" =~ ^[0-9]+$ ]] || die "Puerto local inválido: $LOCAL_PORT"

CG_MODE=apply # cg_resolve_host stops with guidance when the instance is not running
cg_aws_preflight
cg_resolve_host "$TOOL"
info "$TOOL disponible en http://localhost:$LOCAL_PORT (túnel SSH hacia $HOST_ID). Ctrl+C para cerrar."
exec ssh -i "$HOST_KEY" -N -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 \
  -o StrictHostKeyChecking=accept-new -o HostKeyAlias="$HOST_ID" -o UserKnownHostsFile="$SSH_KEY_DIR/known_hosts" \
  -L "127.0.0.1:$LOCAL_PORT:127.0.0.1:$REMOTE_PORT" "$SSH_USER@$HOST_PUBLIC_IP"
