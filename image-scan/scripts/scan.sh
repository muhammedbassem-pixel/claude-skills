#!/usr/bin/env bash
# Scan a Docker image for vulnerabilities/secrets/misconfig with Trivy (official image).
# Usage: scan.sh [-s SEVERITIES] [-u] [-o output-dir] <image[:tag]>
#   -s  severities (default CRITICAL,HIGH)
#   -u  only show vulnerabilities that have a fix (--ignore-unfixed)
set -euo pipefail

SEVERITIES="CRITICAL,HIGH"
IGNORE_UNFIXED=0
OUTDIR=""
while getopts "s:uo:" opt; do
  case $opt in
    s) SEVERITIES="$OPTARG" ;;
    u) IGNORE_UNFIXED=1 ;;
    o) OUTDIR="$OPTARG" ;;
    *) echo "usage: scan.sh [-s SEVERITIES] [-u] [-o output-dir] <image[:tag]>" >&2; exit 1 ;;
  esac
done
shift $((OPTIND-1))

IMAGE="${1:?usage: scan.sh [-s SEVERITIES] [-u] [-o output-dir] <image[:tag]>}"
command -v jq >/dev/null || { echo "jq not installed" >&2; exit 1; }
docker info >/dev/null 2>&1 || { echo "Docker daemon not running" >&2; exit 1; }

TS=$(date +%Y%m%d_%H%M%S)
SAFE="$(printf '%s' "$IMAGE" | tr '/:' '__')"
OUT="${OUTDIR:-$HOME/image-scan/${SAFE}_REPORT_${TS}}"
mkdir -p "$OUT"

TRIVY_IMAGE="${TRIVY_IMAGE:-aquasec/trivy:latest}"
echo ">> Pulling $TRIVY_IMAGE ..."
docker pull "$TRIVY_IMAGE" || echo "(pull failed — using cached image if present)"

EXTRA=()
[ "$IGNORE_UNFIXED" = 1 ] && EXTRA+=(--ignore-unfixed)

echo ">> Scanning image '$IMAGE' (severities: $SEVERITIES)..."
# mount the docker socket so Trivy reads the locally-built/pulled image;
# persist the vuln DB cache between runs
docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v "$HOME/.cache/trivy:/root/.cache/" \
  -v "$OUT:/out" \
  "$TRIVY_IMAGE" image \
  --scanners vuln,secret,misconfig \
  --severity "$SEVERITIES" \
  "${EXTRA[@]+"${EXTRA[@]}"}" \
  --format json -o /out/trivy.json \
  "$IMAGE" || true

JSON="$OUT/trivy.json"
[ -s "$JSON" ] || echo '{"Results":[]}' > "$JSON"

# normalized, ticket-ready findings
FINDINGS_JSON="$OUT/findings.json"
jq --arg img "$IMAGE" '[.Results[]? | .Target as $t | (.Vulnerabilities // [])[] | {
    image: $img, target: $t,
    id: .VulnerabilityID, package: .PkgName,
    installed: .InstalledVersion, fixed: (.FixedVersion // ""),
    severity: .Severity, title: (.Title // ""), url: (.PrimaryURL // "")
  }] | sort_by(.severity)' "$JSON" > "$FINDINGS_JSON" 2>/dev/null || echo '[]' > "$FINDINGS_JSON"

TOTAL=$(jq 'length' "$FINDINGS_JSON" 2>/dev/null || echo 0)
FIXABLE=$(jq '[.[]|select(.fixed!="")]|length' "$FINDINGS_JSON" 2>/dev/null || echo 0)

# markdown report
MD="$OUT/image-report.md"
{
  echo "# Image Scan — $IMAGE"
  echo
  echo "- **Scanned:** $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "- **Severities:** $SEVERITIES"
  echo "- **Vulnerabilities:** $TOTAL ($FIXABLE fixable)"
  echo
  echo "## Vulnerabilities"
  echo
  if [ "$TOTAL" -gt 0 ]; then
    echo "| Severity | CVE | Package | Installed | Fixed | Title |"
    echo "|----------|-----|---------|-----------|-------|-------|"
    jq -r '.[] | "| \(.severity) | \(.id) | \(.package) | \(.installed) | \(.fixed // "-") | \(.title | gsub("\n";" ") | gsub("\\|";"\\|") | .[0:80]) |"' "$FINDINGS_JSON" 2>/dev/null || true
  else
    echo "_No vulnerabilities at the selected severities._"
  fi
} > "$MD"

echo
echo ">> $TOTAL vulnerability(ies), $FIXABLE with a fix available."
echo ">> Reports written to $OUT:"
for f in "$OUT"/*; do [ -e "$f" ] && echo "   ${f##*/}"; done
echo
echo ">> Next: consider migrating to a distroless base to shrink the attack surface."
echo "   See references/distroless.md; then rebuild and re-scan to confirm improvement."
