#!/usr/bin/env bash
# HU-14 · Helpers of the infrastructure-as-code scan (security/scan-iac.sh): read a Trivy "config" JSON report and apply the
# exceptions of security/exceptions.tsv (same file, same rules and same validator as the vulnerability exceptions: security/lib/exceptions.sh).
# Sourced, not run. Uses only awk and grep (no jq, no python), like the other gates.
#
# Identity of an IaC finding, in the columns of the exceptions file:
#   id       the Trivy rule id                      AWS-0104, KSV-0014
#   package  the resource: the Terraform address (aws_security_group.node, module.compute), or, for Kubernetes, the Trivy message,
#            which names the container and the workload ("Container 'auth' of Deployment 'auth' should set ...")
#   scope    "iac:" + the file                      iac:infra/terraform/modules/compute/main.tf
#   severity CRITICAL or HIGH
# So an exception covers ONE rule on ONE resource of ONE file; a new finding, another resource or another file is not covered.

# iac_extract <report.json>: one line per finding: severity<TAB>id<TAB>resource<TAB>file<TAB>title
iac_extract() {
  awk '
    # A message may quote lists (KSV-0056: resources ["services", ...] and the verb "*"); the exceptions file forbids wildcard and
    # bracket characters in an identity, so they are removed here, the same way on both sides of the comparison.
    function clean(s) { gsub(/\\"/, "", s); gsub(/[][*?|"\\]/, "", s); return s }
    function flush() {
      if (id != "") printf "%s\t%s\t%s\t%s\t%s\n", sev, id, (res != "" ? res : clean(msg)), target, title
      id = ""; res = ""; msg = ""; sev = ""; title = ""
    }
    function value(line,   v) { v = line; sub(/^[^:]*: *"/, "", v); sub(/",?$/, "", v); return v }
    /^ *"Target": *"/    { flush(); target = value($0) }
    /^ *"ID": *"/        { flush(); id = value($0) }
    /^ *"Title": *"/     { if (id != "" && title == "") title = value($0) }
    /^ *"Message": *"/   { if (id != "" && msg == "") msg = value($0) }
    /^ *"Severity": *"/  { if (id != "" && sev == "") sev = value($0) }
    /^ *"Resource": *"/  { if (id != "" && res == "") res = value($0) }
    END { flush() }
  ' "$1"
}

# iac_annotate <valid exceptions file>: reads the lines of iac_extract on stdin and adds a sixth column: EXCEPTED (a valid exception
# covers it) or "-". The valid file is the one written by exc_prepare ($EXC_VALID).
iac_annotate() {
  if [[ ! -s "$1" ]]; then awk -F'\t' '{ print $0 "\t-" }'; return 0; fi
  awk -F'\t' 'NR == FNR { valid[$1 SUBSEP $2 SUBSEP $3 SUBSEP $4] = 1; next }
              { key = $2 SUBSEP $3 SUBSEP ("iac:" $4) SUBSEP $1; print $0 "\t" ((key in valid) ? "EXCEPTED" : "-") }' "$1" -
}
