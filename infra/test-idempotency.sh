#!/usr/bin/env bash
# HU-01 · Integral idempotency test on AWS (criterion C3): the automated version of
# docs/evidencias/hu-01/15-procedimiento-idempotencia-aws.md. BILLABLE: it starts the approved
# servers for about 40 minutes. Steps:
#   snapshot S0 -> bootstrap-all (run 1) -> S1 -> bootstrap-all (run 2) -> S2
#   -> registry test (verify-infra.sh --registry) -> comparisons -> stop of the instances
# The instances are ALWAYS stopped at the end, also when a step fails or the time limit is hit.
# Acceptance: S1 and S2 identical, and run 2 with created=0 updated=0 and no CREATED or UPDATED
# line. Run 1 also checks persistence after the stop: managed passwords still valid and no
# factory password replaced again.
# Results go to ~/.circleguard/idempotency/<UTC timestamp>/ (outside the repository): snapshots,
# outputs, diffs, report.txt and masked/ (copies without the account id, public IPs or hashes of
# secret files, ready for docs/evidencias/hu-01/).
#   --plan (default)            prints the procedure; no AWS call
#   --apply --approve <roles>   runs it (asks for the phrase PROBAR IDEMPOTENCIA, or CG_CONFIRM)

# shellcheck source=bootstrap/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/bootstrap/lib/common.sh"
# shellcheck source=bootstrap/lib/aws.sh
source "$INFRA_DIR/bootstrap/lib/aws.sh"
# shellcheck source=bootstrap/lib/remote.sh
source "$INFRA_DIR/bootstrap/lib/remote.sh"

usage() {
  cat <<'EOF'
Uso: infra/test-idempotency.sh [--plan | --apply --approve <roles>]
  --plan (por defecto)        muestra el procedimiento, sin llamar a AWS.
  --apply --approve ci,nexus  ejecuta la prueba (FACTURABLE, unos 40 min) y detiene las instancias.
  Requiere la sesión del operador recién abierta: bash infra/aws-session.sh login operator
EOF
}

# Time with the servers running before aborting: the operator role lasts 1 h after the MFA.
LIMIT_SECONDS=${CG_TEST_LIMIT_SECONDS:-3000}

cg_parse_flags "$@"
cg_load_config
ROLES=${CG_APPROVED:-ci,nexus}
OUT="$CG_LOCAL_HOME/idempotency/$(date -u +%Y%m%dT%H%M%SZ)"

if ! is_apply; then
  cat >&2 <<EOF
Prueba de idempotencia integral (--plan: no se llama a AWS). Con --apply --approve $ROLES:
  0. comprueba la sesión del operador y pide la frase PROBAR IDEMPOTENCIA (servidores: $ROLES)
  1. S0 = verify-infra.sh --snapshot          (punto de partida; instancias detenidas)
  2. run1 = bootstrap-all.sh --apply --approve $ROLES   (inicia los servidores: FACTURABLE)
  3. S1 = verify-infra.sh --snapshot
  4. run2 = bootstrap-all.sh --apply --approve $ROLES   (no debe cambiar nada)
  5. S2 = verify-infra.sh --snapshot
  6. verify-infra.sh --registry               (publicar y descargar desde el host ci y desde Jenkins; REGISTRY_BACKEND=$REGISTRY_BACKEND)
  7. reiniciar los contenedores, esperar a que estén sanos, verify-infra.sh --health y S3 (debe ser igual a S2)
  8. comparaciones: diff S1 S2 vacío; run2 created=0 updated=0; persistencia en run1
  9. teardown.sh --stop --apply               (siempre, también si algo falla o se superan $LIMIT_SECONDS s)
Resultados: $CG_LOCAL_HOME/idempotency/<marca UTC>/ (report.txt, S0-S2, run1, run2, diffs, masked/)
Costo estimado: 0.12-0.21 USD (0.2075 USD/h con ci y nexus encendidas), más el EBS que ya se cobra.
EOF
  exit 0
fi

require_cmd diff sha256sum python3 git timeout
cg_start_log test-idempotency
install -d -m 700 "$OUT"
# Before the AWS identity check, so that a slow git status (WSL on a Windows folder) never eats
# the 1 h MFA window of the operator role. Tracked files only, bounded to 90 s.
COMMIT=$(cd "$REPO_DIR" && git rev-parse --short HEAD)
if ! changes=$(cd "$REPO_DIR" && timeout 90 git status --porcelain --untracked-files=no 2>/dev/null); then
  warn "git status no respondió en 90 s: no se comprobó si hay cambios sin confirmar"
elif [[ -n "$changes" ]]; then
  warn "el árbol de trabajo tiene cambios sin confirmar: la evidencia no corresponderá exactamente al commit $COMMIT"
fi
cg_aws_use operate
cg_aws_preflight
ACCOUNT=$(cut -d: -f5 <<<"$CG_AWS_ARN")
confirm "PROBAR IDEMPOTENCIA" "Se iniciarán (FACTURABLE) los servidores $ROLES durante unos 40 minutos y se detendrán al final."

REPORT="$OUT/report.txt"
FAILURES=0
STARTED=$(date +%s)
report() { printf '%s\n' "$*" | tee -a "$REPORT" >&2; }
check() { # check <description> <command...>: PASS or FAIL line in the report
  local description=$1
  shift
  if "$@"; then report "PASS  $description"; else report "FAIL  $description"; FAILURES=$((FAILURES + 1)); fi
}
elapsed() { echo $(($(date +%s) - STARTED)); }
within_limit() {
  (($(elapsed) < LIMIT_SECONDS)) || die "se superaron $LIMIT_SECONDS s con los servidores encendidos: se aborta y se detienen (ventana MFA de 1 h)"
}

stop_servers() {
  local rc=$?
  info "parada obligatoria de las instancias (rol de lectura)"
  if CG_CONFIRM=DETENER bash "$INFRA_DIR/teardown.sh" --stop --apply >"$OUT/stop.txt" 2>&1 &&
    bash "$INFRA_DIR/teardown.sh" --stop >>"$OUT/stop.txt" 2>&1; then
    report "INFO  instancias detenidas al terminar ($(grep -o 'no hay instancias de [a-z]* en ejecución' "$OUT/stop.txt" | tail -1))"
  else
    report "FAIL  la parada automática de la prueba falló: deténgalas YA con bash infra/teardown.sh --stop --apply"
    rc=1
  fi
  report "INFO  duración de la prueba (desde la confirmación hasta la parada): $(elapsed) s · resultados en $OUT"
  mask_copies
  exit "$rc"
}

# Masked copies for the evidence folder. Made last, so that report.txt includes the result and
# the stop of the instances.
mask_copies() {
  local f
  install -d -m 700 "$OUT/masked"
  report "INFO  copias enmascaradas en $OUT/masked (sin número de cuenta, IP públicas ni hashes de archivos secretos)"
  for f in S0 S1 S2 S3 run1 run2 diff-S0-S1 diff-S1-S2 diff-S2-S3 registry isolation health-after-restart stop report; do
    [[ -f "$OUT/$f.txt" ]] || continue
    cg_mask_evidence "$ACCOUNT" "$OUT/$f.txt" >"$OUT/masked/$f.txt"
  done
}
trap stop_servers EXIT

snapshot() { bash "$INFRA_DIR/verify-infra.sh" --snapshot >"$OUT/$1.txt" || die "falló la instantánea $1"; }
bootstrap_run() {
  bash "$INFRA_DIR/bootstrap-all.sh" --apply --approve "$ROLES" 2>&1 | tee "$OUT/$1.txt"
  return "${PIPESTATUS[0]}"
}

report "Prueba de idempotencia integral de HU-01 · $(date -u +%Y-%m-%dT%H:%M:%SZ) · commit $COMMIT · servidores $ROLES · REGISTRY_BACKEND=$REGISTRY_BACKEND"
snapshot S0
report "INFO  punto de partida (S0): $(grep -c '^instance ' "$OUT/S0.txt") instancias; $(grep '^instance ' "$OUT/S0.txt" | awk '{print $2"="$6}' | tr '\n' ' ')"
bootstrap_run run1 || die "la primera ejecución de bootstrap-all.sh falló (ver $OUT/run1.txt)"
within_limit
snapshot S1
bootstrap_run run2 || die "la segunda ejecución de bootstrap-all.sh falló (ver $OUT/run2.txt)"
within_limit
snapshot S2
approved() { [[ "$ROLES" == all || ",$ROLES," == *",$1,"* ]]; }
# Flows between the servers on the converged state, including ci -> registry 8082 (the
# credentials check reads the whole repository and is left out to protect the 1 h MFA window).
if approved ci && approved nexus; then
  check "red: verify-infra.sh --isolation en PASS, incluido ci -> registro 8082 (isolation.txt)" \
    bash -c "bash '$INFRA_DIR/verify-infra.sh' --isolation --roles=ci,nexus >'$OUT/isolation.txt' 2>&1"
fi
if [[ "$REGISTRY_BACKEND" == distribution ]] && approved ci && approved nexus; then
  if bash "$INFRA_DIR/verify-infra.sh" --registry --roles=ci,nexus >"$OUT/registry.txt" 2>&1; then
    report "PASS  registro: publicación y descarga con el usuario ci desde el servidor ci (registry.txt)"
  else
    report "FAIL  registro: la publicación o la descarga falló (registry.txt)"
    FAILURES=$((FAILURES + 1))
  fi
fi

# Recovery after restarting the containers: every container of the approved servers is restarted
# and must become healthy again; the state afterwards (S3) must equal S2 (nothing recreated, the
# same files and data) and verify-infra.sh --health must pass.
UP=()
for role in ci nexus; do approved "$role" && UP+=("$role"); done
for role in "${UP[@]}"; do
  cg_resolve_host "$role" >/dev/null || continue
  if cg_root "docker restart \$(docker ps -q) >/dev/null
    for _ in \$(seq 1 60); do
      [ \"\$(docker ps --format '{{.Status}}' | grep -vc '(healthy)')\" -eq 0 ] && exit 0
      sleep 10
    done
    exit 1"; then
    report "INFO  $role: contenedores reiniciados y saludables de nuevo"
  else
    report "FAIL  $role: algún contenedor no volvió a estar saludable tras reiniciarlo"
    FAILURES=$((FAILURES + 1))
  fi
done
within_limit
if ((${#UP[@]})); then
  roles_up=$(IFS=,; echo "${UP[*]}")
  check "recuperación: verify-infra.sh --health en PASS tras reiniciar los contenedores (health-after-restart.txt)" \
    bash -c "bash '$INFRA_DIR/verify-infra.sh' --health --roles=$roles_up >'$OUT/health-after-restart.txt' 2>&1"
  snapshot S3
  diff "$OUT/S2.txt" "$OUT/S3.txt" >"$OUT/diff-S2-S3.txt" || true
  check "recuperación: diff S2 S3 vacío (mismos contenedores, archivos y datos tras el reinicio)" test ! -s "$OUT/diff-S2-S3.txt"
fi

# --- Comparisons -------------------------------------------------------------------------
diff "$OUT/S1.txt" "$OUT/S2.txt" >"$OUT/diff-S1-S2.txt" || true
diff "$OUT/S0.txt" "$OUT/S1.txt" >"$OUT/diff-S0-S1.txt" || true
summary2=$(grep 'SUMMARY   bootstrap-all' "$OUT/run2.txt" | tail -1 || true)
check "diff S1 S2 vacío: la segunda ejecución no cambió el estado" test ! -s "$OUT/diff-S1-S2.txt"
check "run2: bootstrap-all con created=0 updated=0 ($(sed -E 's/.*bootstrap-all //' <<<"$summary2"))" \
  grep -q 'created=0 updated=0' <<<"$summary2"
check "run2: ninguna línea CREATED ni UPDATED en ningún paso" bash -c "! grep -qE ' (CREATED|UPDATED) ' '$OUT/run2.txt'"
report "INFO  run2: acciones pendientes de decisión (PLAN): $(grep -c ' PLAN ' "$OUT/run2.txt" || true) · $(grep ' PLAN ' "$OUT/run2.txt" | sed -E 's/^.* PLAN +//' | cut -c1-90 | sort -u | paste -sd ';' -)"
same_ids() { [[ "$(grep '^instance ' "$OUT/S1.txt" | awk '{print $2, $3}')" == "$(grep '^instance ' "$OUT/S2.txt" | awk '{print $2, $3}')" ]]; }
check "S1 y S2: mismas instancias" same_ids
approved_running() { # every approved instance of S2 is running with IMDSv2 required
  local role state tokens
  while read -r _ role _ _ _ state tokens; do
    approved "$role" || continue
    [[ "$state" == running && "$tokens" == required ]] || return 1
  done < <(grep '^instance ' "$OUT/S2.txt")
}
check "S2: instancias aprobadas en ejecución con IMDSv2 obligatorio" approved_running
# Persistence after the stop: a lost data volume would bring back the factory passwords, which
# the configure scripts would then replace (UPDATED). The managed passwords must still work.
check "persistencia (run1): ninguna contraseña de fábrica reemplazada de nuevo" \
  bash -c "! grep -qE ' UPDATED .*contraseña (de fábrica|inicial) del administrador reemplazada' '$OUT/run1.txt'"
# volume_before_test <role> <volume>: the named volume existed before this test, so its data is the
# one kept on the EBS volume since the last stop (the container itself may be recreated: run 1
# rebuilds the Jenkins image).
volume_before_test() {
  local created
  cg_resolve_host "$1" >/dev/null || return 1
  created=$(cg_root "docker volume inspect -f '{{.CreatedAt}}' $2" 2>/dev/null) || return 1
  [[ -n "$created" ]] && (($(date -u -d "$created" +%s) < STARTED))
}
if approved ci; then
  check "persistencia (run1): el volumen jenkins_home es anterior a la prueba (datos de Jenkins conservados)" \
    volume_before_test ci circleguard-jenkins_jenkins_home
  check "persistencia (run1): SonarQube usa la contraseña gestionada" grep -q 'UNCHANGED .*sonarqube: el administrador usa la contraseña gestionada' "$OUT/run1.txt"
fi
if approved nexus; then
  check "persistencia (run1): Nexus usa la contraseña gestionada" grep -q 'UNCHANGED .*nexus: el administrador usa la contraseña gestionada' "$OUT/run1.txt"
fi
unexpected=$(grep -E '^[<>] (vpc|subnet|igw|rtb|key) ' "$OUT/diff-S0-S1.txt" || true)
check "S0 -> S1: la red y las llaves no cambiaron" test -z "$unexpected"
report "INFO  S0 -> S1: $(grep -c '^[<>] sgrule ' "$OUT/diff-S0-S1.txt" || true) líneas de reglas (solo el 22 si cambió la IP del operador), $(grep -c '^> ssm ' "$OUT/diff-S0-S1.txt" || true) parámetros SSM nuevos, $(grep -c '^[<>] instance ' "$OUT/diff-S0-S1.txt" || true) líneas de instancias"
(cd "$OUT" && sha256sum S0.txt S1.txt S2.txt run1.txt run2.txt; [[ -f S3.txt ]] && sha256sum S3.txt) >"$OUT/sha256sums.txt"

# The masked copies are made by stop_servers (EXIT trap), after the result and the stop.
report "RESULTADO: $([[ $FAILURES -eq 0 ]] && echo 'IDEMPOTENTE (todas las comprobaciones en PASS)' || echo "$FAILURES comprobaciones en FAIL")"
((FAILURES == 0)) || exit 1
