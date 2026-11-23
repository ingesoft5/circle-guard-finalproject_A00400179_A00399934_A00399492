#!/usr/bin/env bash
# Local cost ESTIMATE of HU-01. Requires common.sh.
#
# It is a preventive check of these scripts, NOT a billing limit: AWS has no hard spending cap,
# the ledger only sees the operations made through the scripts, and prices are the reference
# values of infra/config/aws.env. The real figures are in the AWS Billing console (and in an
# AWS Budgets alert, if the team approves creating one).

CG_LEDGER="$CG_LOCAL_HOME/budget/ledger.tsv"

# cg_ledger <run|start|stop|terminate> <role> <instance id> <type> <GiB>
cg_ledger() { cg_ledger_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$@"; }

cg_ledger_at() { # cg_ledger_at <UTC time> <event> <role> <instance id> <type> <GiB>
  install -d -m 700 "$(dirname "$CG_LEDGER")"
  (umask 077 && printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$@" >>"$CG_LEDGER")
}

# cg_ledger_sync_stop <role> <instance id> <state transition reason>: records a stop the scripts
# did not make (the auto-stop timer, the console), so the estimate stops adding instance hours.
# The time is the one in AWS's transition reason (confirmed). Without it the time is ESTIMATED:
# the last start plus AUTO_STOP_HOURS (it ignores extensions of the session), or now when the
# auto-stop is disabled; a warning says so. The result always lies between the start and now.
cg_ledger_sync_stop() {
  local last since when now source
  [[ -s "$CG_LEDGER" ]] || return 0
  read -r last since < <(awk -F'\t' -v id="$2" '$4 == id { e = $2; t = $1 } END { print e, t }' "$CG_LEDGER")
  [[ "$last" == run || "$last" == start ]] || return 0
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  when=$(grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}' <<<"$3" | head -1 || true)
  if [[ -n "$when" ]]; then
    when=$(date -u -d "$when UTC" +%Y-%m-%dT%H:%M:%SZ)
    source=aws
  elif ((${AUTO_STOP_HOURS:-0} > 0)); then
    when=$(date -u -d "$since + $AUTO_STOP_HOURS hours" +%Y-%m-%dT%H:%M:%SZ)
    source=estimada
  else
    when=$now
    source=ahora
  fi
  if [[ ! "$when" < "$now" ]]; then
    when=$now
    [[ "$source" == aws ]] && source=ajustada
  fi
  if [[ ! "$when" > "$since" ]]; then
    when=$since
    [[ "$source" == aws ]] && source=ajustada
  fi
  cg_ledger_at "$when" stop "$1" "$2" - -
  case "$source" in
    aws) info "estimación: $2 detenida a las $when (hora confirmada por AWS; parada no hecha por los scripts)" ;;
    ajustada) warn "estimación: la hora de parada que da AWS para $2 queda fuera de [último arranque, ahora]; se registra $when" ;;
    estimada) warn "estimación: hora de parada de $2 ESTIMADA, $when (último arranque + $AUTO_STOP_HOURS h de la parada automática, como máximo ahora), porque AWS no la indica; si la sesión se amplió, el costo real es mayor: consulte Billing" ;;
    ahora) warn "estimación: hora de parada de $2 desconocida y parada automática desactivada: se registra la hora actual ($when), que puede sobrestimar el costo" ;;
  esac
}

# cg_budget_accrued: estimated USD of the running hours (instance + public IPv4) and of the
# volume hours recorded in the ledger, up to now.
cg_budget_accrued() {
  if [[ ! -s "$CG_LEDGER" ]]; then
    echo 0.00
    return
  fi
  python3 - "$CG_LEDGER" <<'PY'
import datetime as dt, os, sys
prices = {k[11:]: float(v) for k, v in os.environ.items() if k.startswith('PRICE_HOUR_')}
price = lambda itype: prices.get(itype.replace('.', '_').replace('-', '_'), max(prices.values()))
ipv4 = float(os.environ['PRICE_IPV4_HOUR'])
gb_hour = float(os.environ['PRICE_EBS_GP3_GB_MONTH']) / 730
now = dt.datetime.now(dt.timezone.utc)
hours = lambda a, b: (b - a).total_seconds() / 3600
running, volumes, total = {}, {}, 0.0
for line in open(sys.argv[1]):
    ts, event, _role, iid, itype, gib = line.rstrip('\n').split('\t')
    t = dt.datetime.fromisoformat(ts.replace('Z', '+00:00'))
    if event in ('run', 'start') and iid not in running:
        running[iid] = (t, price(itype) + ipv4)
    if event == 'run':
        volumes.setdefault(iid, (t, float(gib)))
    if event in ('stop', 'terminate') and iid in running:
        start, rate = running.pop(iid)
        total += hours(start, t) * rate
    if event == 'terminate' and iid in volumes:
        start, size = volumes.pop(iid)
        total += hours(start, t) * size * gb_hour
total += sum(hours(start, now) * rate for start, rate in running.values())
total += sum(hours(start, now) * size * gb_hour for start, size in volumes.values())
print(f'{total:.2f}')
PY
}

# cg_budget_check <projected USD> <description>: refuses the run when the estimate (accrued +
# projected + data transfer reserve) exceeds HU01_BUDGET_USD and warns above 80 %.
cg_budget_check() {
  local accrued reserve total
  accrued=$(cg_budget_accrued)
  reserve=$(awk -v g="${DATA_OUT_GB_RESERVE:-0}" -v p="${PRICE_DATA_OUT_GB:-0}" 'BEGIN { printf "%.2f", g * p }')
  total=$(awk -v a="$accrued" -v p="$1" -v r="$reserve" 'BEGIN { printf "%.2f", a + p + r }')
  info "estimación local (no es un límite de facturación): acumulado $accrued + $2 $(printf '%.2f' "$1") + transferencia $reserve = $total de $HU01_BUDGET_USD USD"
  if awk -v t="$total" -v l="$HU01_BUDGET_USD" 'BEGIN { exit !(t > l) }'; then
    die "La estimación supera el presupuesto de HU-01 ($HU01_BUDGET_USD USD): no se ejecuta. Revise el costo real en la consola de Billing y consulte al equipo."
  fi
  if awk -v t="$total" -v l="$HU01_BUDGET_USD" 'BEGIN { exit !(t > 0.8 * l) }'; then
    warn "la estimación supera el 80 % del presupuesto de HU-01"
  fi
  return 0
}
