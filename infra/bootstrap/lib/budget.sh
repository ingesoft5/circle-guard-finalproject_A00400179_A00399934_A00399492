#!/usr/bin/env bash
# Local cost ESTIMATE of HU-01. Requires common.sh.
#
# It is a preventive check of these scripts, NOT a billing limit: AWS has no hard spending cap,
# the ledger only sees the operations made through the scripts, and prices are the reference
# values of infra/config/aws.env. The real figures are in the AWS Billing console (and in an
# AWS Budgets alert, if the team approves creating one).

CG_LEDGER="$CG_LOCAL_HOME/budget/ledger.tsv"

# cg_ledger <run|start|stop|terminate> <role> <instance id> <type> <GiB>
cg_ledger() {
  install -d -m 700 "$(dirname "$CG_LEDGER")"
  (umask 077 && printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$@" >>"$CG_LEDGER")
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
# projected) exceeds HU01_BUDGET_USD and warns above 80 %.
cg_budget_check() {
  local accrued total
  accrued=$(cg_budget_accrued)
  total=$(awk -v a="$accrued" -v p="$1" 'BEGIN { printf "%.2f", a + p }')
  info "estimación local (no es un límite de facturación): acumulado $accrued + $2 $(printf '%.2f' "$1") = $total de $HU01_BUDGET_USD USD"
  if awk -v t="$total" -v l="$HU01_BUDGET_USD" 'BEGIN { exit !(t > l) }'; then
    die "La estimación supera el presupuesto de HU-01 ($HU01_BUDGET_USD USD): no se ejecuta. Revise el costo real en la consola de Billing y consulte al equipo."
  fi
  if awk -v t="$total" -v l="$HU01_BUDGET_USD" 'BEGIN { exit !(t > 0.8 * l) }'; then
    warn "la estimación supera el 80 % del presupuesto de HU-01"
  fi
  return 0
}
