#!/usr/bin/env bash
# Scan Kubernetes configuration (manifests / Helm / kustomize) against best practices.
# Trivy config (primary) + kube-linter (fast lint) + optional kubescape (NSA/CIS/MITRE frameworks).
# Usage: scan.sh [-f framework] [-o output-dir] <manifests-dir>
#   -f  also run kubescape against a framework (nsa | mitre | cis-v1.23-t1.0.1 | allcontrols)
set -euo pipefail

FRAMEWORK=""
OUTDIR=""
while getopts "f:o:" opt; do
  case $opt in
    f) FRAMEWORK="$OPTARG" ;;
    o) OUTDIR="$OPTARG" ;;
    *) echo "usage: scan.sh [-f framework] [-o output-dir] <manifests-dir>" >&2; exit 1 ;;
  esac
done
shift $((OPTIND-1))

SRC="${1:?usage: scan.sh [-f framework] [-o output-dir] <manifests-dir>}"
SRC="$(cd "$SRC" && pwd)"
command -v jq >/dev/null || { echo "jq not installed" >&2; exit 1; }
docker info >/dev/null 2>&1 || { echo "Docker daemon not running" >&2; exit 1; }

TS=$(date +%Y%m%d_%H%M%S)
NAME="$(basename "$SRC")"
OUT="${OUTDIR:-$HOME/k8s-scan/${NAME}_REPORT_${TS}}"
mkdir -p "$OUT"

TRIVY_IMAGE="${TRIVY_IMAGE:-aquasec/trivy:latest}"
KUBELINTER_IMAGE="${KUBELINTER_IMAGE:-stackrox/kube-linter:latest}"
KUBESCAPE_IMAGE="${KUBESCAPE_IMAGE:-quay.io/kubescape/kubescape:latest}"

echo ">> Pulling scanners ..."
docker pull "$TRIVY_IMAGE"      >/dev/null 2>&1 || echo "(trivy pull failed — using cache)"
docker pull "$KUBELINTER_IMAGE" >/dev/null 2>&1 || echo "(kube-linter pull failed — using cache)"

echo ">> Trivy config (misconfiguration scan)..."
docker run --rm -v "$SRC:/src:ro" -v "$OUT:/out" "$TRIVY_IMAGE" \
  config /src --format json -o /out/trivy-config.json || true
[ -s "$OUT/trivy-config.json" ] || echo '{"Results":[]}' > "$OUT/trivy-config.json"

echo ">> kube-linter (best-practice lint)..."
docker run --rm -v "$SRC:/dir:ro" "$KUBELINTER_IMAGE" \
  lint /dir --format json > "$OUT/kube-linter.json" 2>"$OUT/kube-linter.log" || true
[ -s "$OUT/kube-linter.json" ] || echo '{"Reports":[]}' > "$OUT/kube-linter.json"

if [ -n "$FRAMEWORK" ]; then
  echo ">> kubescape (framework: $FRAMEWORK)..."
  docker pull "$KUBESCAPE_IMAGE" >/dev/null 2>&1 || echo "(kubescape pull failed — using cache)"
  docker run --rm -v "$SRC:/data:ro" -v "$OUT:/out" "$KUBESCAPE_IMAGE" \
    scan framework "$FRAMEWORK" /data --format json --output /out/kubescape.json 2>"$OUT/kubescape.log" || true
fi

# ---- normalize into ticket-ready findings.json ----
FINDINGS="$OUT/findings.json"
TMP="$OUT/.parts.json"
: > "$TMP"
# Trivy misconfigurations
jq -c '[.Results[]? | .Target as $t | (.Misconfigurations // [])[] | {
    tool:"trivy", target:$t, id:.AVDID, check:.ID, title:.Title,
    severity:.Severity, message:.Message, resolution:.Resolution,
    line:(.CauseMetadata.StartLine // 0), url:(.PrimaryURL // "")
  }]' "$OUT/trivy-config.json" >> "$TMP" 2>/dev/null || echo '[]' >> "$TMP"
# kube-linter reports
jq -c '[.Reports[]? | {
    tool:"kube-linter", target:(.Object.Metadata.FilePath // .Object.K8sObject.Namespace // ""),
    id:.Check, check:.Check, title:.Check,
    severity:"WARNING", message:.Diagnostic.Message, resolution:.Remediation, line:0, url:""
  }]' "$OUT/kube-linter.json" >> "$TMP" 2>/dev/null || echo '[]' >> "$TMP"
# kubescape failed controls (if run)
if [ -s "$OUT/kubescape.json" ]; then
  jq -c '[.results[]? as $r | ($r.controls // {}) | to_entries[] | select(.value.status.status=="failed") | {
      tool:"kubescape", target:($r.resourceID // ""), id:.value.controlID, check:.key,
      title:.key, severity:"WARNING", message:.key, resolution:"", line:0, url:""
    }]' "$OUT/kubescape.json" >> "$TMP" 2>/dev/null || echo '[]' >> "$TMP"
fi
jq -s 'add | sort_by(.severity)' "$TMP" > "$FINDINGS" 2>/dev/null || echo '[]' > "$FINDINGS"
rm -f "$TMP"

TOTAL=$(jq 'length' "$FINDINGS" 2>/dev/null || echo 0)
CRIT=$(jq '[.[]|select(.severity=="CRITICAL")]|length' "$FINDINGS" 2>/dev/null || echo 0)
HIGH=$(jq '[.[]|select(.severity=="HIGH")]|length' "$FINDINGS" 2>/dev/null || echo 0)

MD="$OUT/k8s-report.md"
{
  echo "# Kubernetes Config Scan — $NAME"
  echo
  echo "- **Scanned:** $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "- **Source:** $SRC"
  echo "- **Findings:** $TOTAL (CRITICAL: $CRIT, HIGH: $HIGH)"
  echo "- **Tools:** Trivy config, kube-linter${FRAMEWORK:+, kubescape ($FRAMEWORK)}"
  echo
  echo "| Tool | Severity | Check | Target:Line | Issue | Remediation |"
  echo "|------|----------|-------|-------------|-------|-------------|"
  jq -r '.[] | "| \(.tool) | \(.severity) | \(.check) | \(.target):\(.line) | \(.message | gsub("\n";" ") | gsub("\\|";"\\|") | .[0:80]) | \(.resolution | gsub("\n";" ") | gsub("\\|";"\\|") | .[0:80]) |"' "$FINDINGS" 2>/dev/null || true
} > "$MD"

echo
echo ">> $TOTAL finding(s) (CRITICAL: $CRIT, HIGH: $HIGH)."
echo ">> Reports written to $OUT:"
for f in "$OUT"/*; do [ -e "$f" ] && echo "   ${f##*/}"; done
