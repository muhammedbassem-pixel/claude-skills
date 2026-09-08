#!/usr/bin/env bash
# Scan Infrastructure-as-Code + K8s manifests for misconfigurations against best practices.
# Checkov (primary, broad: terraform/cloudformation/arm/bicep/dockerfile/serverless/k8s/helm)
# + Trivy config (fast second opinion).
# Usage: scan.sh [-f framework] [-s SEVERITIES] [-o output-dir] <iac-dir>
#   -f  restrict Checkov to a framework (terraform|cloudformation|arm|bicep|dockerfile|
#       serverless|kubernetes|helm|kustomize|secrets|... ; default: all, auto-detected)
#   -s  Trivy severities (default HIGH,CRITICAL)
set -euo pipefail

FRAMEWORK=""
SEVERITIES="HIGH,CRITICAL"
OUTDIR=""
while getopts "f:s:o:" opt; do
  case $opt in
    f) FRAMEWORK="$OPTARG" ;;
    s) SEVERITIES="$OPTARG" ;;
    o) OUTDIR="$OPTARG" ;;
    *) echo "usage: scan.sh [-f framework] [-s SEVERITIES] [-o output-dir] <iac-dir>" >&2; exit 1 ;;
  esac
done
shift $((OPTIND-1))

SRC="${1:?usage: scan.sh [-f framework] [-s SEVERITIES] [-o output-dir] <iac-dir>}"
SRC="$(cd "$SRC" && pwd)"
command -v jq >/dev/null || { echo "jq not installed" >&2; exit 1; }
docker info >/dev/null 2>&1 || { echo "Docker daemon not running" >&2; exit 1; }

TS=$(date +%Y%m%d_%H%M%S)
NAME="$(basename "$SRC")"
OUT="${OUTDIR:-$HOME/iac-scan/${NAME}_REPORT_${TS}}"
mkdir -p "$OUT"

CHECKOV_IMAGE="${CHECKOV_IMAGE:-bridgecrew/checkov:latest}"
TRIVY_IMAGE="${TRIVY_IMAGE:-aquasec/trivy:latest}"
echo ">> Pulling scanners ..."
docker pull "$CHECKOV_IMAGE" >/dev/null 2>&1 || echo "(checkov pull failed — using cache)"
docker pull "$TRIVY_IMAGE"   >/dev/null 2>&1 || echo "(trivy pull failed — using cache)"

# 1) Checkov (primary) — all frameworks by default; built-in policies, no account/network
echo ">> Checkov (IaC misconfiguration scan${FRAMEWORK:+, framework=$FRAMEWORK})..."
CKV_ARGS=(-d /iac -o json --compact --quiet --soft-fail)
[ -n "$FRAMEWORK" ] && CKV_ARGS+=(--framework "$FRAMEWORK")
docker run --rm -v "$SRC:/iac:ro" "$CHECKOV_IMAGE" \
  "${CKV_ARGS[@]}" > "$OUT/checkov.json" 2>"$OUT/checkov.log" || true
[ -s "$OUT/checkov.json" ] || echo '{}' > "$OUT/checkov.json"

# 2) Trivy config (second opinion)
echo ">> Trivy config (second opinion)..."
docker run --rm -v "$SRC:/iac:ro" -v "$OUT:/out" -v "$HOME/.cache/trivy:/root/.cache/" \
  "$TRIVY_IMAGE" config /iac --severity "$SEVERITIES" \
  --format json -o /out/trivy-config.json >/dev/null 2>&1 || true
[ -s "$OUT/trivy-config.json" ] || echo '{"Results":[]}' > "$OUT/trivy-config.json"

# ---- normalize into ticket-ready findings.json ----
FINDINGS="$OUT/findings.json"
TMP="$OUT/.parts.json"
: > "$TMP"
# Checkov failed checks (results may be an object or an array of framework-objects)
jq -c '[ (if type=="array" then .[] else . end)
         | (.results.failed_checks // [])[]
         | { tool:"checkov", id:.check_id, title:.check_name,
             severity:(.severity // "MEDIUM"),
             resource:.resource, file:(.file_path // ""),
             line:((.file_line_range // [0])[0]), guideline:(.guideline // "") } ]' \
  "$OUT/checkov.json" >> "$TMP" 2>/dev/null || echo '[]' >> "$TMP"
# Trivy misconfigurations
jq -c '[ .Results[]? | .Target as $t | (.Misconfigurations // [])[]
         | { tool:"trivy", id:(.AVDID // .ID // ""), title:.Title, severity:.Severity,
             resource:$t, file:$t, line:(.CauseMetadata.StartLine // 0),
             guideline:(.PrimaryURL // "") } ]' \
  "$OUT/trivy-config.json" >> "$TMP" 2>/dev/null || echo '[]' >> "$TMP"
jq -s 'add | sort_by(.severity)' "$TMP" > "$FINDINGS" 2>/dev/null || echo '[]' > "$FINDINGS"
rm -f "$TMP"

TOTAL=$(jq 'length' "$FINDINGS" 2>/dev/null || echo 0)
CKV_N=$(jq '[.[]|select(.tool=="checkov")]|length' "$FINDINGS" 2>/dev/null || echo 0)
TRV_N=$(jq '[.[]|select(.tool=="trivy")]|length' "$FINDINGS" 2>/dev/null || echo 0)
CRIT=$(jq '[.[]|select(.severity=="CRITICAL")]|length' "$FINDINGS" 2>/dev/null || echo 0)
HIGH=$(jq '[.[]|select(.severity=="HIGH")]|length' "$FINDINGS" 2>/dev/null || echo 0)

MD="$OUT/iac-report.md"
{
  echo "# IaC & Manifest Scan — $NAME"
  echo
  echo "- **Scanned:** $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "- **Findings:** $TOTAL (Checkov: $CKV_N, Trivy: $TRV_N)"
  echo "- **Severity:** CRITICAL: $CRIT, HIGH: $HIGH"
  echo
  echo "| Tool | Severity | Check | Resource | File:Line | Guideline |"
  echo "|------|----------|-------|----------|-----------|-----------|"
  jq -r '.[] | "| \(.tool) | \(.severity) | \(.id): \(.title|gsub("\\|";"\\|")|.[0:50]) | \(.resource|.[0:40]) | \(.file):\(.line) | \(.guideline|.[0:40]) |"' "$FINDINGS" 2>/dev/null || true
} > "$MD"

echo
echo ">> $TOTAL finding(s) — Checkov: $CKV_N, Trivy: $TRV_N (CRITICAL: $CRIT, HIGH: $HIGH)"
echo ">> Reports written to $OUT:"
for f in "$OUT"/*; do [ -e "$f" ] && echo "   ${f##*/}"; done
