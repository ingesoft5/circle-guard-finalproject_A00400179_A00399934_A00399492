#!/usr/bin/env bash
# HU-01 · Read-only verification of the platform. Never changes anything.
#   --health       tools answer (on the host and from the operator through the security group)
#                  and environment hosts are ready
#   --isolation    allowed flows work and every flow between environments is blocked
#   --credentials  independent secrets per environment, .env files with mode 0600, and no
#                  managed secret value present in the repository
#   --snapshot     deterministic state listing, to compare two bootstrap runs (idempotency)
# Without options: --health --isolation --credentials (aws) or --health (local).

# shellcheck source=bootstrap/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/bootstrap/lib/common.sh"
# shellcheck source=bootstrap/lib/aws.sh
source "$INFRA_DIR/bootstrap/lib/aws.sh"
# shellcheck source=bootstrap/lib/remote.sh
source "$INFRA_DIR/bootstrap/lib/remote.sh"

usage() {
  cat <<'EOF'
Uso: infra/verify-infra.sh [--health] [--isolation] [--credentials] [--snapshot] [--target aws|local]
  Solo lectura. Termina con código 1 si alguna comprobación falla.
EOF
}

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); log PASS "$@"; }
fail() { FAIL=$((FAIL + 1)); log FAIL "$@"; }
expect() { # expect <description> <expected> <actual>
  if [[ "$3" == "$2" ]]; then pass "$1"; else fail "$1 (esperado '$2', obtenido '${3:-sin respuesta}')"; fi
}
remote() { cg_root "$1" 2>/dev/null || true; }
local_code() { curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$1" || true; }

# via_tunnel <local port> <remote port> <path>: HTTP code obtained through a temporary SSH
# tunnel to the selected host (the administrative access path of infra/tunnel.sh).
via_tunnel() {
  local pid code
  ssh -i "$HOST_KEY" -N -o BatchMode=yes -o ExitOnForwardFailure=yes -o StrictHostKeyChecking=accept-new \
    -o HostKeyAlias="$HOST_ID" -o UserKnownHostsFile="$SSH_KEY_DIR/known_hosts" -o LogLevel=ERROR \
    -L "127.0.0.1:$1:127.0.0.1:$2" "$SSH_USER@$HOST_PUBLIC_IP" &
  pid=$!
  sleep 3
  code=$(local_code "http://127.0.0.1:$1$3")
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  echo "$code"
}

# admin_access <tool> <ip> <port> <path> <tunnel port>: UI unreachable from the Internet and
# reachable through the SSH tunnel.
admin_access() {
  expect "$1: UI NO expuesta a Internet (puerto $3)" 000 "$(local_code "http://$2:$3$4")"
  expect "$1: UI accesible por túnel SSH" 200 "$(via_tunnel "$5" "$3" "$4")"
}

# present <tool>: with --target local only the stacks that are running are checked (stacks are
# validated one at a time on Docker Desktop and stopped afterwards).
present() {
  [[ "$CG_TARGET" == aws ]] && return 0
  [[ -n "$(docker ps -q --filter "name=^cg-$1$" --filter status=running)" ]] && return 0
  info "$1: stack local no desplegado o detenido; se omite"
  return 1
}

check_tools() {
  local ip
  if ! present jenkins; then
    :
  elif cg_resolve_host jenkins >/dev/null; then
    ip=$HOST_PUBLIC_IP
    expect "jenkins: /login en el host" 200 "$(remote "curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:$JENKINS_HTTP_PORT/login")"
    expect "jenkins: contenedor saludable" healthy "$(remote "docker inspect -f '{{.State.Health.Status}}' cg-jenkins")"
    if [[ "$CG_TARGET" == aws ]]; then admin_access jenkins "$ip" "$JENKINS_HTTP_PORT" /login 18080; fi
  else
    fail "jenkins: la instancia no está en ejecución"
  fi
  if ! present sonarqube; then
    :
  elif cg_resolve_host sonarqube >/dev/null; then
    ip=$HOST_PUBLIC_IP
    expect "sonarqube: estado del sistema" UP "$(remote "curl -s http://127.0.0.1:$SONARQUBE_HTTP_PORT/api/system/status | python3 -c 'import json,sys; print(json.load(sys.stdin)[\"status\"])'")"
    expect "sonarqube: contenedor saludable" healthy "$(remote "docker inspect -f '{{.State.Health.Status}}' cg-sonarqube")"
    expect "sonarqube: base de datos saludable" healthy "$(remote "docker inspect -f '{{.State.Health.Status}}' cg-sonarqube-db")"
    expect "sonarqube: acceso anónimo denegado" 401 "$(remote "curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:$SONARQUBE_HTTP_PORT/api/projects/search")"
    if [[ "$CG_TARGET" == aws ]]; then admin_access sonarqube "$ip" "$SONARQUBE_HTTP_PORT" /api/system/status 19000; fi
  else
    fail "sonarqube: la instancia no está en ejecución"
  fi
  if ! present nexus; then
    :
  elif cg_resolve_host nexus >/dev/null; then
    ip=$HOST_PUBLIC_IP
    local docker_port=$NEXUS_DOCKER_PORT
    [[ "$CG_TARGET" == local ]] && docker_port=$LOCAL_NEXUS_DOCKER_HOST_PORT
    expect "nexus: API de estado" 200 "$(remote "curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:$NEXUS_HTTP_PORT/service/rest/v1/status")"
    expect "nexus: contenedor saludable" healthy "$(remote "docker inspect -f '{{.State.Health.Status}}' cg-nexus")"
    expect "nexus: registro Docker exige autenticación" 401 "$(remote "curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:$docker_port/v2/")"
    if [[ "$CG_TARGET" == aws ]]; then
      admin_access nexus "$ip" "$NEXUS_HTTP_PORT" /service/rest/v1/status 18081
      expect "nexus: registro Docker NO expuesto a Internet" 000 "$(local_code "http://$ip:$NEXUS_DOCKER_PORT/v2/")"
    fi
  else
    fail "nexus: la instancia no está en ejecución"
  fi
}

check_envs() {
  local e
  for e in "${CG_ENVS[@]}"; do
    if ! cg_resolve_host "env-$e" >/dev/null; then
      fail "env-$e: la instancia no está en ejecución"
      continue
    fi
    expect "env-$e: Docker activo" active "$(remote "systemctl is-active docker")"
    expect "env-$e: plugin Compose disponible" yes "$(remote "docker compose version >/dev/null && echo yes")"
    expect "env-$e: .env propio con permisos 0600 root" "600 root" "$(remote "stat -c '%a %U' /opt/circleguard/$e/.env")"
    expect "env-$e: .env pertenece al ambiente" yes "$(remote "grep -qx 'ENV_NAME=$e' /opt/circleguard/$e/.env && echo yes")"
  done
}

private_ip() { cg_find_instances "$1" running | awk '{print $5}'; }

# flow <description> <open|closed> <from role> <to role> <port>
flow() {
  local target result
  target=$(private_ip "$4")
  nz "$target" || { fail "$1 (la instancia $4 no está en ejecución)"; return; }
  cg_resolve_host "$3" >/dev/null || { fail "$1 (la instancia $3 no está en ejecución)"; return; }
  if cg_root "nc -z -w 3 $target $5" >/dev/null 2>&1; then result=open; else result=closed; fi
  expect "$1" "$2" "$result"
}

check_isolation() {
  local e o
  for e in "${CG_ENVS[@]}"; do
    for o in "${CG_ENVS[@]}"; do
      [[ "$e" == "$o" ]] || flow "aislamiento: env-$e -> env-$o:22 bloqueado" closed "env-$e" "env-$o" 22
    done
    flow "aislamiento: env-$e -> jenkins:$JENKINS_HTTP_PORT bloqueado" closed "env-$e" jenkins "$JENKINS_HTTP_PORT"
    flow "aislamiento: env-$e -> sonarqube:$SONARQUBE_HTTP_PORT bloqueado" closed "env-$e" sonarqube "$SONARQUBE_HTTP_PORT"
    flow "permitido: env-$e -> nexus:$NEXUS_DOCKER_PORT (registro)" open "env-$e" nexus "$NEXUS_DOCKER_PORT"
    flow "permitido: jenkins -> env-$e:22" open jenkins "env-$e" 22
    flow "aislamiento: sonarqube -> env-$e:22 bloqueado" closed sonarqube "env-$e" 22
  done
  flow "permitido: jenkins -> sonarqube:$SONARQUBE_HTTP_PORT" open jenkins sonarqube "$SONARQUBE_HTTP_PORT"
  flow "permitido: jenkins -> nexus:$NEXUS_HTTP_PORT" open jenkins nexus "$NEXUS_HTTP_PORT"
}

check_credentials() {
  local name distinct entry scope tool
  mapfile -t ENV_NAMES < <(cg_catalog | awk '$1 == "dev" { print $2 }')
  for name in "${ENV_NAMES[@]}"; do
    distinct=$(for e in "${CG_ENVS[@]}"; do cg_secret_get "$e" "$name" | sha256sum; done | sort -u | grep -c .)
    expect "credenciales: $name distinto en dev, stage y prod" 3 "$distinct"
  done
  for tool in jenkins sonarqube nexus; do
    if cg_resolve_host "$tool" >/dev/null; then
      expect "credenciales: .env de $tool con permisos 0600 root" "600 root" "$(remote "stat -c '%a %U' /opt/circleguard/$tool/.env")"
    fi
  done
  # No managed value may appear in any file that would be committed.
  mapfile -t CATALOG < <(cg_catalog)
  found=$(for entry in "${CATALOG[@]}"; do
    read -r scope name _ <<<"$entry"
    cg_secret_get "$scope" "$name"
    echo
  done | python3 -c '
import subprocess, sys
values = {v for v in sys.stdin.read().split("\n") if len(v) >= 8}
files = subprocess.run(["git", "-C", sys.argv[1], "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
                       capture_output=True, check=True).stdout.decode().split("\0")
hits = 0
for f in filter(None, files):
    try:
        text = open(sys.argv[1] + "/" + f, encoding="utf-8", errors="ignore").read()
    except OSError:
        continue
    hits += sum(1 for v in values if v in text)
print(hits)' "$REPO_DIR")
  expect "credenciales: ningún secreto gestionado aparece en el repositorio" 0 "$found"
}

snapshot() {
  local role
  {
    aws_ ec2 describe-vpcs --filters "Name=tag:Project,Values=$PROJECT" --query 'Vpcs[].[Tags[?Key==`Name`]|[0].Value,VpcId,CidrBlock]' --output text | sed 's/^/vpc /'
    aws_ ec2 describe-subnets --filters "Name=tag:Project,Values=$PROJECT" --query 'Subnets[].[Tags[?Key==`Name`]|[0].Value,SubnetId,CidrBlock,MapPublicIpOnLaunch]' --output text | sed 's/^/subnet /'
    aws_ ec2 describe-internet-gateways --filters "Name=tag:Project,Values=$PROJECT" --query 'InternetGateways[].[InternetGatewayId,Attachments[0].VpcId]' --output text | sed 's/^/igw /'
    aws_ ec2 describe-route-tables --filters "Name=tag:Project,Values=$PROJECT" --query 'RouteTables[].[RouteTableId,length(Associations),Routes[?DestinationCidrBlock==`0.0.0.0/0`]|[0].GatewayId]' --output text | sed 's/^/rtb /'
    for g in $(aws_ ec2 describe-security-groups --filters "Name=tag:Project,Values=$PROJECT" --query 'SecurityGroups[].GroupId' --output text); do
      aws_ ec2 describe-security-group-rules --filters "Name=group-id,Values=$g" \
        --query 'SecurityGroupRules[].[GroupId,IsEgress,IpProtocol,FromPort,CidrIpv4,ReferencedGroupInfo.GroupId]' --output text | sed 's/^/sgrule /'
    done
    aws_ ec2 describe-key-pairs --filters "Name=tag:Project,Values=$PROJECT" --query 'KeyPairs[].[KeyName,KeyFingerprint]' --output text | sed 's/^/key /'
    aws_ ssm get-parameters-by-path --path "/$PROJECT" --recursive --query 'Parameters[].[Name,Version]' --output text | sed 's/^/ssm /'
    aws_ ec2 describe-instances --filters "Name=tag:Project,Values=$PROJECT" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
      --query 'Reservations[].Instances[].[Tags[?Key==`Role`]|[0].Value,InstanceId,InstanceType,ImageId,State.Name,MetadataOptions.HttpTokens]' --output text | sed 's/^/instance /'
    for role in "${CG_ROLES[@]}"; do
      cg_resolve_host "$role" >/dev/null 2>&1 || continue
      remote "find /opt/circleguard -type f -exec sha256sum {} + | sort -k2" | sed "s/^/file $role /"
      remote "docker ps -a --format '{{.Names}} {{.ID}} {{.Image}} {{.CreatedAt}}' | sort" | sed "s/^/container $role /"
    done
  } | sort
}

cg_parse_flags "$@"
cg_load_config
MODES=("${CG_ARGS[@]}")
if ((${#MODES[@]} == 0)); then
  if [[ "$CG_TARGET" == aws ]]; then MODES=(--health --isolation --credentials); else MODES=(--health); fi
fi
if [[ " ${MODES[*]} " == *" --snapshot "* ]]; then
  cg_aws_preflight 2>/dev/null
  snapshot
  exit 0
fi
CG_MODE=solo-lectura
cg_start_log verify-infra
cg_target_preflight
for mode in "${MODES[@]}"; do
  case "$mode" in
    --health)
      check_tools
      if [[ "$CG_TARGET" == aws ]]; then check_envs; fi
      ;;
    --isolation) [[ "$CG_TARGET" == aws ]] || die "--isolation solo aplica a AWS"; check_isolation ;;
    --credentials) [[ "$CG_TARGET" == aws ]] || die "--credentials solo aplica a AWS"; check_credentials ;;
    *) die "opción desconocida: $mode" ;;
  esac
done
log SUMMARY "verify-infra pass=$PASS fail=$FAIL"
[[ "$FAIL" -eq 0 ]] || exit 1
