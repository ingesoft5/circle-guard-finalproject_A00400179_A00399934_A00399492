#!/usr/bin/env bash
# HU-01 · Read-only verification of the platform. Never changes anything.
#   --health       servers (Docker, auto-stop timer scheduled, swap, memory in use), tools answer
#                  (on the host and from the operator through the security group) and the memory
#                  each tool container uses (docker stats), state of the Nexus
#                  EULA, and the environments: their host if one exists, otherwise the isolation
#                  configured in their subnet and security group
#   --isolation    allowed flows work and blocked ones are refused, tested with nc from the hosts
#   --credentials  independent secrets per environment, .env files with mode 0600, and no
#                  managed secret value present in the repository
#   --snapshot     deterministic state listing, to compare two bootstrap runs (idempotency)
# Without options: --health --isolation --credentials (aws) or --health (local).
# Results are PASS, FAIL or PENDING (something that waits for a decision or for servers that
# HU-01 does not create: it is never counted as passed).

# shellcheck source=bootstrap/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/bootstrap/lib/common.sh"
# shellcheck source=bootstrap/lib/aws.sh
source "$INFRA_DIR/bootstrap/lib/aws.sh"
# shellcheck source=bootstrap/lib/remote.sh
source "$INFRA_DIR/bootstrap/lib/remote.sh"

usage() {
  cat <<'EOF'
Uso: infra/verify-infra.sh [--health] [--isolation] [--credentials] [--snapshot] [--roles=<lista>] [--target aws|local]
  Solo lectura. Termina con código 1 si alguna comprobación falla.
  --roles=ci,nexus  limita las comprobaciones a los servidores encendidos en la sesión en curso.
EOF
}

ROLES=""
# wanted <role>: with --roles only the listed roles are checked; flows need both ends listed.
wanted() { [[ -z "$ROLES" || ",$ROLES," == *",$1,"* ]]; }

PASS=0
FAIL=0
PENDING=0
pass() { PASS=$((PASS + 1)); log PASS "$@"; }
fail() { FAIL=$((FAIL + 1)); log FAIL "$@"; }
pending() { PENDING=$((PENDING + 1)); log PENDING "$@"; }
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
  if ! wanted "$(cg_tool_host "$1")"; then
    info "$1: su servidor $(cg_tool_host "$1") está fuera de --roles; se omite"
    return 1
  fi
  [[ "$CG_TARGET" == aws ]] && return 0
  [[ -n "$(docker ps -q --filter "name=^cg-$1$" --filter status=running)" ]] && return 0
  info "$1: stack local no desplegado o detenido; se omite"
  return 1
}

# check_hosts: settings of each running server that protect its memory and the budget.
check_hosts() {
  local role
  [[ "$CG_TARGET" == aws ]] || return 0
  for role in "${CG_ROLES[@]}"; do
    wanted "$role" || continue
    if ! cg_resolve_host "$role" >/dev/null; then
      fail "$role: la instancia no está en ejecución"
      continue
    fi
    expect "$role: Docker activo" active "$(remote "systemctl is-active docker")"
    if ((AUTO_STOP_HOURS > 0)); then
      # "waiting" means a stop is scheduled; an elapsed timer is still "active" but schedules nothing.
      expect "$role: parada automática programada (circleguard-autostop.timer en espera)" waiting "$(remote "systemctl show circleguard-autostop.timer -p SubState --value")"
      info "$role: temporizador de parada: $(remote "systemctl list-timers circleguard-autostop.timer --no-legend" | head -1 | tr -s ' ')"
    else
      pending "$role: parada automática desactivada (AUTO_STOP_HOURS=0): detenga la instancia al terminar"
    fi
    if ((SWAP_GB > 0)); then expect "$role: swap de seguridad activo" /swapfile "$(remote "swapon --show=NAME --noheadings")"; fi
    info "$role: memoria en uso $(remote "free -m | awk '/^Mem:/ { print \$3 \" de \" \$2 \" MiB\" } /^Swap:/ { print \"· swap \" \$3 \" de \" \$2 \" MiB\" }'" | tr '\n' ' ')"
  done
}

# container_memory <container...>: memory in use per container on the selected host, one line
# each. docker stats only measures running containers: stopped or missing ones, or a Docker that
# does not answer, are reported as such and never as zero.
container_memory() {
  local c
  if [[ "$(remote "docker info >/dev/null 2>&1 && echo ok")" != ok ]]; then
    echo "Docker no disponible: no se mide la memoria de $*"
    return 0
  fi
  for c in "$@"; do
    remote "s=\$(docker inspect -f '{{.State.Status}}' $c 2>/dev/null) || { echo '$c: ausente'; exit 0; }
      if [ \"\$s\" = running ]; then
        m=\$(docker stats --no-stream --format '{{.MemUsage}} ({{.MemPerc}})' $c 2>/dev/null)
        echo \"$c: \${m:-sin datos de docker stats}\"
      else
        echo \"$c: \$s, sin consumo medible\"
      fi"
  done
}

# memory_line <tool> <container...>: logs the memory of the tool's containers.
memory_line() {
  local tool=$1
  shift
  info "$tool: memoria por contenedor: $(container_memory "$@" | paste -sd ';' | sed 's/;/ · /g')"
}

# nexus_eula: "aceptado", "pendiente" or "desconocido", read with the managed admin password from
# the stack's .env (it reaches curl through stdin; printf is a shell builtin, not a process).
nexus_eula() {
  local envf
  envf="$(cg_stack_dir nexus)/.env"
  remote "set -a; . $(printf '%q' "$envf"); set +a; printf 'user = \"admin:%s\"\n' \"\$NEXUS_ADMIN_PASSWORD\" | curl -s --max-time 10 -K - \"http://127.0.0.1:\$NEXUS_HTTP_PORT/service/rest/v1/system/eula\"" |
    python3 -c 'import json, sys
try:
    print("aceptado" if json.load(sys.stdin).get("accepted") else "pendiente")
except Exception:
    print("desconocido")'
}

check_tools() {
  local ip
  if ! present jenkins; then
    :
  elif cg_resolve_host "$(cg_tool_host jenkins)" >/dev/null; then
    ip=$HOST_PUBLIC_IP
    expect "jenkins: /login en el host" 200 "$(remote "curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:$JENKINS_HTTP_PORT/login")"
    expect "jenkins: contenedor saludable" healthy "$(remote "docker inspect -f '{{.State.Health.Status}}' cg-jenkins")"
    memory_line jenkins cg-jenkins
    if [[ "$CG_TARGET" == aws ]]; then admin_access jenkins "$ip" "$JENKINS_HTTP_PORT" /login 18080; fi
  else
    fail "jenkins: la instancia $(cg_tool_host jenkins) no está en ejecución"
  fi
  if ! present sonarqube; then
    :
  elif cg_resolve_host "$(cg_tool_host sonarqube)" >/dev/null; then
    ip=$HOST_PUBLIC_IP
    expect "sonarqube: estado del sistema" UP "$(remote "curl -s http://127.0.0.1:$SONARQUBE_HTTP_PORT/api/system/status | python3 -c 'import json,sys; print(json.load(sys.stdin)[\"status\"])'")"
    expect "sonarqube: contenedor saludable" healthy "$(remote "docker inspect -f '{{.State.Health.Status}}' cg-sonarqube")"
    expect "sonarqube: base de datos saludable" healthy "$(remote "docker inspect -f '{{.State.Health.Status}}' cg-sonarqube-db")"
    memory_line sonarqube cg-sonarqube cg-sonarqube-db
    expect "sonarqube: acceso anónimo denegado" 401 "$(remote "curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:$SONARQUBE_HTTP_PORT/api/projects/search")"
    if [[ "$CG_TARGET" == aws ]]; then admin_access sonarqube "$ip" "$SONARQUBE_HTTP_PORT" /api/system/status 19000; fi
  else
    fail "sonarqube: la instancia $(cg_tool_host sonarqube) no está en ejecución"
  fi
  if ! present nexus; then
    :
  elif cg_resolve_host "$(cg_tool_host nexus)" >/dev/null; then
    ip=$HOST_PUBLIC_IP
    local docker_port=$NEXUS_DOCKER_PORT
    [[ "$CG_TARGET" == local ]] && docker_port=$LOCAL_NEXUS_DOCKER_HOST_PORT
    expect "nexus: API de estado" 200 "$(remote "curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:$NEXUS_HTTP_PORT/service/rest/v1/status")"
    expect "nexus: contenedor saludable" healthy "$(remote "docker inspect -f '{{.State.Health.Status}}' cg-nexus")"
    memory_line nexus cg-nexus
    case "$(nexus_eula)" in
      aceptado)
        pass "nexus: EULA de Community Edition aceptado"
        expect "nexus: registro Docker exige autenticación" 401 "$(remote "curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:$docker_port/v2/")"
        ;;
      pendiente)
        pending "nexus: EULA de Community Edition PENDIENTE de la decisión del equipo: no se pueden descargar ni subir componentes y circleguard-docker no existe"
        expect "nexus: conector Docker sin publicar mientras el EULA está pendiente" 000 "$(remote "curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:$docker_port/v2/")"
        ;;
      *) fail "nexus: no se pudo leer el estado del EULA (¿se aplicó la contraseña gestionada?)" ;;
    esac
    if [[ "$CG_TARGET" == aws ]]; then
      admin_access nexus "$ip" "$NEXUS_HTTP_PORT" /service/rest/v1/status 18081
      expect "nexus: registro Docker NO expuesto a Internet" 000 "$(local_code "http://$ip:$NEXUS_DOCKER_PORT/v2/")"
    fi
  else
    fail "nexus: la instancia $(cg_tool_host nexus) no está en ejecución"
  fi
}

# check_envs: the environment's host if one exists; otherwise (HU-01) the isolation configured in
# its subnet and security group, which is not the same as isolation exercised by traffic.
check_envs() {
  local e o sg other peers allowed bad cidr
  for e in "${CG_ENVS[@]}"; do
    wanted "env-$e" || continue
    if [[ -n "$(cg_find_instances "env-$e" running)" ]] && cg_resolve_host "env-$e" >/dev/null; then
      expect "env-$e: Docker activo" active "$(remote "systemctl is-active docker")"
      expect "env-$e: plugin Compose disponible" yes "$(remote "docker compose version >/dev/null && echo yes")"
      expect "env-$e: .env propio con permisos 0600 root" "600 root" "$(remote "stat -c '%a %U' /opt/circleguard/$e/.env")"
      expect "env-$e: .env pertenece al ambiente" yes "$(remote "grep -qx 'ENV_NAME=$e' /opt/circleguard/$e/.env && echo yes")"
      continue
    fi
    cidr=$(cg_env_value "$e" ENV_SUBNET_CIDR)
    expect "env-$e: subred propia $cidr" "$cidr" "$(cg_find describe-subnets 'Subnets[].CidrBlock' "$PROJECT-subnet-$e")"
    sg=$(cg_sg_id "env-$e")
    if ! nz "$sg"; then
      fail "env-$e: falta el grupo de seguridad $(cg_sg_name "env-$e")"
      continue
    fi
    pass "env-$e: grupo de seguridad propio ($sg)"
    peers=$(aws_ ec2 describe-security-group-rules --filters "Name=group-id,Values=$sg" \
      --query 'SecurityGroupRules[].ReferencedGroupInfo.GroupId' --output text | tr '\t' ' ')
    for o in "${CG_ENVS[@]}"; do
      [[ "$o" == "$e" ]] && continue
      other=$(cg_sg_id "env-$o")
      if nz "$other" && [[ " $peers " == *" $other "* ]]; then
        fail "env-$e: tiene reglas que referencian a env-$o ($other)"
      else
        pass "env-$e: ninguna regla hacia ni desde env-$o"
      fi
    done
    allowed=" $(cg_sg_id ci) $(cg_sg_id nexus) "
    bad=$(for p in $peers; do [[ "$allowed" == *" $p "* ]] || echo "$p"; done | sort -u | tr '\n' ' ')
    expect "env-$e: sus reglas solo referencian a ci y nexus" "" "${bad% }"
    pending "env-$e: aislamiento CONFIGURADO (subred y grupo de seguridad), no verificado con tráfico: HU-01 no crea servidores de ambiente"
  done
}

private_ip() { cg_find_instances "$1" running | awk '{print $5}'; }

# flow <description> <open|closed> <from role> <to role> <port>
flow() {
  local target result
  if ! wanted "$3" || ! wanted "$4"; then return 0; fi
  target=$(private_ip "$4")
  nz "$target" || { fail "$1 (la instancia $4 no está en ejecución)"; return; }
  cg_resolve_host "$3" >/dev/null || { fail "$1 (la instancia $3 no está en ejecución)"; return; }
  if cg_root "nc -z -w 3 $target $5" >/dev/null 2>&1; then result=open; else result=closed; fi
  expect "$1" "$2" "$result"
}

check_isolation() {
  local e o envs=0
  for e in "${CG_ENVS[@]}"; do
    [[ -n "$(cg_find_instances "env-$e" running)" ]] || continue
    envs=$((envs + 1))
    for o in "${CG_ENVS[@]}"; do
      [[ "$e" == "$o" ]] || flow "aislamiento: env-$e -> env-$o:22 bloqueado" closed "env-$e" "env-$o" 22
    done
    flow "aislamiento: env-$e -> ci:$JENKINS_HTTP_PORT bloqueado" closed "env-$e" ci "$JENKINS_HTTP_PORT"
    flow "aislamiento: env-$e -> ci:$SONARQUBE_HTTP_PORT bloqueado" closed "env-$e" ci "$SONARQUBE_HTTP_PORT"
    flow "permitido: env-$e -> nexus:$NEXUS_DOCKER_PORT (registro)" open "env-$e" nexus "$NEXUS_DOCKER_PORT"
    flow "permitido: ci -> env-$e:22" open ci "env-$e" 22
    flow "aislamiento: nexus -> env-$e:22 bloqueado" closed nexus "env-$e" 22
  done
  if ((envs == 0)); then
    pending "aislamiento entre ambientes: no hay servidores de ambiente (HU-01), así que no se prueba con tráfico; la configuración se comprueba con --health"
  fi
  # SonarQube and Jenkins share the ci server and only listen on its 127.0.0.1.
  flow "permitido: ci -> nexus:$NEXUS_HTTP_PORT" open ci nexus "$NEXUS_HTTP_PORT"
  flow "aislamiento: nexus -> ci:$JENKINS_HTTP_PORT bloqueado" closed nexus ci "$JENKINS_HTTP_PORT"
  flow "aislamiento: nexus -> ci:$SONARQUBE_HTTP_PORT bloqueado" closed nexus ci "$SONARQUBE_HTTP_PORT"
}

check_credentials() {
  local name distinct entry scope tool
  mapfile -t ENV_NAMES < <(cg_catalog | awk '$1 == "dev" { print $2 }')
  for name in "${ENV_NAMES[@]}"; do
    distinct=$(for e in "${CG_ENVS[@]}"; do cg_secret_get "$e" "$name" | sha256sum; done | sort -u | grep -c .)
    expect "credenciales: $name distinto en dev, stage y prod" 3 "$distinct"
  done
  for tool in jenkins sonarqube nexus; do
    if wanted "$(cg_tool_host "$tool")" && cg_resolve_host "$(cg_tool_host "$tool")" >/dev/null; then
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
MODES=()
for arg in "${CG_ARGS[@]}"; do
  if [[ "$arg" == --roles=* ]]; then
    ROLES=${arg#--roles=}
    for r in ${ROLES//,/ }; do
      case "$r" in ci | nexus | env-dev | env-stage | env-prod) ;; *) die "rol desconocido en --roles: $r (use ci, nexus o env-<ambiente>)" ;; esac
    done
  else
    MODES+=("$arg")
  fi
done
if ((${#MODES[@]} == 0)); then
  if [[ "$CG_TARGET" == aws ]]; then MODES=(--health --isolation --credentials); else MODES=(--health); fi
fi
# The checks read hosts and secrets (with decryption): operator role.
if [[ "$CG_TARGET" == aws ]]; then cg_aws_use operate; fi
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
      check_hosts
      check_tools
      if [[ "$CG_TARGET" == aws ]]; then check_envs; fi
      ;;
    --isolation) [[ "$CG_TARGET" == aws ]] || die "--isolation solo aplica a AWS"; check_isolation ;;
    --credentials) [[ "$CG_TARGET" == aws ]] || die "--credentials solo aplica a AWS"; check_credentials ;;
    *) die "opción desconocida: $mode" ;;
  esac
done
log SUMMARY "verify-infra pass=$PASS fail=$FAIL pendiente=$PENDING"
[[ "$FAIL" -eq 0 ]] || exit 1
