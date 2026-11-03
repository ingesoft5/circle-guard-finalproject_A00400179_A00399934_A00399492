#!/usr/bin/env bash
# HU-01 · Isolation test of dev, stage and prod with real traffic (criterion C2). BILLABLE.
# The vCPU quota (QUOTA_VCPU_LIMIT) runs two 2-vCPU servers at once, so the test goes in phases of
# two servers. Each phase creates or starts its servers (bootstrap-servers.sh), prepares the
# environment hosts (bootstrap-env.sh: Docker, auto-stop timer, credentials of that environment
# only), runs verify-infra.sh on exactly those servers and stops them before the next phase:
#   1. env-dev + env-stage   dev <-> stage blocked (nc from each host)
#   2. env-dev + env-prod    dev <-> prod blocked
#   3. env-stage + env-prod  stage <-> prod blocked
#   4. ci + env-dev          ci -> env:22 allowed (deployment); env -> Jenkins and SonarQube blocked
#   5. nexus + env-dev       env -> registry 8082 allowed; nexus -> env:22 blocked
# Phase 5 needs the registry deployed (infra/test-idempotency.sh or bootstrap-registry.sh first).
# The instances are ALWAYS stopped at the end, also when a phase fails.
# Results in ~/.circleguard/isolation/<UTC timestamp>/ with masked/ copies for the evidence.
#   --plan (default)  prints the phases and their estimated cost; no AWS call
#   --apply           runs them (asks for the phrase PROBAR AISLAMIENTO, or CG_CONFIRM)

# shellcheck source=bootstrap/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/bootstrap/lib/common.sh"
# shellcheck source=bootstrap/lib/aws.sh
source "$INFRA_DIR/bootstrap/lib/aws.sh"
# shellcheck source=bootstrap/lib/remote.sh
source "$INFRA_DIR/bootstrap/lib/remote.sh"

usage() {
  cat <<'EOF'
Uso: infra/test-isolation.sh [--plan | --apply] [--phases=1,2,3]
  --plan (por defecto)  muestra las fases y su costo estimado, sin llamar a AWS.
  --apply               ejecuta las fases (FACTURABLE) y detiene las instancias al terminar.
  --phases=<lista>      solo esas fases: las cinco no caben en una ventana MFA de 1 h, así que se
                        ejecutan en dos sesiones (--phases=1,2,3 y, tras un nuevo inicio de sesión,
                        --phases=4,5).
  Requiere ENV_SERVERS=dev,stage,prod y la sesión del operador recién abierta.
EOF
}

PHASES=(
  "env-dev,env-stage"
  "env-dev,env-prod"
  "env-stage,env-prod"
  "ci,env-dev"
  "nexus,env-dev"
)
LIMIT_SECONDS=${CG_TEST_LIMIT_SECONDS:-3000}

cg_parse_flags "$@"
cg_load_config
SELECTED="1,2,3,4,5"
for arg in "${CG_ARGS[@]}"; do
  case "$arg" in
    --phases=*) SELECTED=${arg#--phases=} ;;
    *) die "opción desconocida: $arg" ;;
  esac
done
[[ "$SELECTED" =~ ^[1-5](,[1-5])*$ ]] || die "--phases admite números del 1 al 5 separados por comas"
for e in "${CG_ENVS[@]}"; do
  [[ " ${CG_ROLES[*]} " == *" env-$e "* ]] || die "env-$e no está en ENV_SERVERS (infra/config/aws.env): la prueba necesita los tres ambientes"
done

if ! is_apply; then
  {
    echo "Prueba de aislamiento con tráfico (--plan: no se llama a AWS). Con --apply, por fases de dos servidores"
    echo "(cuota QUOTA_VCPU_LIMIT=$QUOTA_VCPU_LIMIT vCPU):"
    echo "  0. bootstrap-network.sh --apply: regla 22 de la IP actual del operador (normalmente sin cambios)"
    n=1
    for p in "${PHASES[@]}"; do
      [[ ",$SELECTED," == *",$n,"* ]] && echo "  $n. $p: bootstrap-servers + bootstrap-env + verify-infra.sh --roles=$p; parada"
      n=$((n + 1))
    done
    echo "  Duración: 10-15 min por fase; las cinco no caben en la ventana MFA de 1 h: use --phases=1,2,3 y --phases=4,5."
    echo "  Al final, siempre: teardown.sh --stop --apply. Resultados en $CG_LOCAL_HOME/isolation/<marca UTC>/"
    echo "  Costo estimado: ≈ 0.15 USD de horas de instancia (fases de 15-20 min) más el EBS de los ambientes"
    echo "  creados (3 x ${ENV_VOLUME_GB:-10} GiB gp3 a $PRICE_EBS_GP3_GB_MONTH USD/GB-mes mientras existan)."
  } >&2
  exit 0
fi

require_cmd diff python3
OUT="$CG_LOCAL_HOME/isolation/$(date -u +%Y%m%dT%H%M%SZ)"
cg_start_log test-isolation
install -d -m 700 "$OUT"
cg_aws_use operate
cg_aws_preflight
ACCOUNT=$(cut -d: -f5 <<<"$CG_AWS_ARN")
confirm "PROBAR AISLAMIENTO" "Se crearán o iniciarán (FACTURABLE) los servidores de ambiente por pares y se detendrán al final."

REPORT="$OUT/report.txt"
FAILURES=0
STARTED=$(date +%s)
report() { printf '%s\n' "$*" | tee -a "$REPORT" >&2; }
# wait_healthy <role>: SSH available and every container of the server healthy (up to 10 min), so
# that the flows are tested against services that already listen.
wait_healthy() {
  cg_resolve_host "$1" >/dev/null || return 1
  cg_wait_ssh
  cg_root "for _ in \$(seq 1 60); do
      [ -n \"\$(docker ps -q)\" ] && [ \"\$(docker ps --format '{{.Status}}' | grep -vc '(healthy)')\" -eq 0 ] && exit 0
      sleep 10
    done
    exit 1"
}
stop_all() { CG_CONFIRM=DETENER bash "$INFRA_DIR/teardown.sh" --stop --apply >>"$OUT/stops.txt" 2>&1; }
finish() {
  local rc=$?
  if stop_all && bash "$INFRA_DIR/teardown.sh" --stop >>"$OUT/stops.txt" 2>&1 &&
    grep -q 'no hay instancias de [a-z]* en ejecución' "$OUT/stops.txt"; then
    report "INFO  instancias detenidas al terminar"
  else
    report "FAIL  la parada final falló: deténgalas YA con bash infra/teardown.sh --stop --apply"
    rc=1
  fi
  install -d -m 700 "$OUT/masked"
  for f in "$OUT"/*.txt; do cg_mask_evidence "$ACCOUNT" "$f" >"$OUT/masked/${f##*/}"; done
  report "INFO  duración: $(($(date +%s) - STARTED)) s · resultados en $OUT (copias enmascaradas en masked/)"
  exit "$rc"
}
trap finish EXIT

report "Prueba de aislamiento de HU-01 · $(date -u +%Y-%m-%dT%H:%M:%SZ) · commit $(cd "$REPO_DIR" && git rev-parse --short HEAD) · ENV_SERVERS=$ENV_SERVERS · fases $SELECTED"
# The SSH rule (22 from the operator's IP) must be current before reaching new hosts; usually
# UNCHANGED (it updates the rule of the 5 groups only if the operator's public IP changed).
if bash "$INFRA_DIR/bootstrap-network.sh" --apply >"$OUT/network.txt" 2>&1; then
  report "INFO  red convergida: $(grep 'SUMMARY' "$OUT/network.txt" | tail -1 | sed -E 's/.*bootstrap-network //' || true)"
else
  report "FAIL  bootstrap-network.sh falló (network.txt): no se ejecuta ninguna fase"
  exit 1
fi
n=0
for phase in "${PHASES[@]}"; do
  n=$((n + 1))
  [[ ",$SELECTED," == *",$n,"* ]] || continue
  (($(date +%s) - STARTED < LIMIT_SECONDS)) || die "se superaron $LIMIT_SECONDS s: se aborta (la ventana MFA del rol de operación es de 1 h)"
  log_file="$OUT/fase$n-${phase//,/-}.txt"
  report "INFO  fase $n: $phase"
  # Phases with a tool server only test the flows: the tools' own health is covered by
  # test-idempotency.sh. The subshell keeps a failed step inside its phase.
  modes=(--isolation)
  [[ "$phase" == env-*,env-* ]] && modes=(--health --isolation)
  (
    bash "$INFRA_DIR/bootstrap-servers.sh" --apply --approve "$phase" || exit 1
    for role in ${phase//,/ }; do
      if [[ "$role" == env-* ]]; then
        bash "$INFRA_DIR/bootstrap-env.sh" "${role#env-}" --apply || exit 1
      else
        wait_healthy "$role" || exit 1
      fi
    done
    bash "$INFRA_DIR/verify-infra.sh" "${modes[@]}" --roles="$phase" || exit 1
  ) >"$log_file" 2>&1 && rc=0 || rc=$?
  summary=$(grep 'SUMMARY   verify-infra' "$log_file" | tail -1 | sed -E 's/.*verify-infra //' || true)
  if ((rc == 0)); then
    report "PASS  fase $n ($phase): $summary"
  else
    report "FAIL  fase $n ($phase): código $rc ${summary:+· $summary} (ver ${log_file##*/})"
    FAILURES=$((FAILURES + 1))
  fi
  grep -E ' (PASS|FAIL) +(aislamiento|permitido|env-)' "$log_file" | sed -E 's/^[0-9:]+ +/      /' >>"$REPORT" || true
  stop_all || { report "FAIL  no se pudieron detener las instancias tras la fase $n"; exit 1; }
done
report "RESULTADO: $([[ $FAILURES -eq 0 ]] && echo 'AISLAMIENTO VERIFICADO CON TRÁFICO (todas las fases en PASS)' || echo "$FAILURES fases en FAIL")"
((FAILURES == 0)) || exit 1
