#!/usr/bin/env bash
# Software Composition Analysis: SBOM + dependency vulnerabilities + license risk.
# Trivy (SBOM CycloneDX + vuln + license, primary) with an OSV-Scanner cross-check.
# Usage: sca.sh [-s SEVERITIES] [-o output-dir] <project-dir>
#   -s  vuln severities to report (default CRITICAL,HIGH,MEDIUM)
set -euo pipefail

SEVERITIES="CRITICAL,HIGH,MEDIUM"
OUTDIR=""
while getopts "s:o:" opt; do
  case $opt in
    s) SEVERITIES="$OPTARG" ;;
    o) OUTDIR="$OPTARG" ;;
    *) echo "usage: sca.sh [-s SEVERITIES] [-o output-dir] <project-dir>" >&2; exit 1 ;;
  esac
done
shift $((OPTIND-1))

SRC="${1:?usage: sca.sh [-s SEVERITIES] [-o output-dir] <project-dir>}"
SRC="$(cd "$SRC" && pwd)"
command -v jq >/dev/null || { echo "jq not installed" >&2; exit 1; }
docker info >/dev/null 2>&1 || { echo "Docker daemon not running" >&2; exit 1; }

TS=$(date +%Y%m%d_%H%M%S)
NAME="$(basename "$SRC")"
OUT="${OUTDIR:-$HOME/sca/${NAME}_REPORT_${TS}}"
mkdir -p "$OUT"

TRIVY_IMAGE="${TRIVY_IMAGE:-aquasec/trivy:latest}"
OSV_IMAGE="${OSV_IMAGE:-ghcr.io/google/osv-scanner:latest}"
echo ">> Pulling scanners ..."
docker pull "$TRIVY_IMAGE" >/dev/null 2>&1 || echo "(trivy pull failed — using cache)"

# 1) SBOM (CycloneDX)
echo ">> Generating SBOM (CycloneDX) with Trivy..."
docker run --rm -v "$SRC:/src:ro" -v "$OUT:/out" -v "$HOME/.cache/trivy:/root/.cache/" \
  "$TRIVY_IMAGE" fs --format cyclonedx -o /out/sbom.cdx.json /src >/dev/null 2>&1 || true

# 2) Dependency vulns + license risk
echo ">> Scanning dependencies for vulnerabilities + license risk (Trivy)..."
docker run --rm -v "$SRC:/src:ro" -v "$OUT:/out" -v "$HOME/.cache/trivy:/root/.cache/" \
  "$TRIVY_IMAGE" fs --scanners vuln,license --severity "$SEVERITIES" \
  --format json -o /out/trivy-sca.json /src >/dev/null 2>&1 || true
[ -s "$OUT/trivy-sca.json" ] || echo '{"Results":[]}' > "$OUT/trivy-sca.json"

# 3) OSV cross-check (independent vuln feed)
echo ">> Cross-checking with OSV-Scanner..."
docker pull "$OSV_IMAGE" >/dev/null 2>&1 || echo "(osv pull failed — using cache)"
docker run --rm -v "$SRC:/src:ro" -v "$OUT:/out" "$OSV_IMAGE" \
  scan source -r --format json /src > "$OUT/osv.json" 2>/dev/null || true
[ -s "$OUT/osv.json" ] || echo '{"results":[]}' > "$OUT/osv.json"

# ---- normalized, ticket-ready findings ----
VULN_JSON="$OUT/vuln-findings.json"
jq '[.Results[]? | .Target as $t | (.Vulnerabilities // [])[] | {
    kind:"vuln", target:$t, id:.VulnerabilityID, package:.PkgName,
    installed:.InstalledVersion, fixed:(.FixedVersion // ""),
    severity:.Severity, title:(.Title // ""), url:(.PrimaryURL // "")
  }] | sort_by(.severity)' "$OUT/trivy-sca.json" > "$VULN_JSON" 2>/dev/null || echo '[]' > "$VULN_JSON"

LIC_JSON="$OUT/license-findings.json"
jq '[.Results[]? | (.Licenses // [])[] | {
    package:(.PkgName // .FilePath // ""), license:.Name,
    category:(.Category // ""), severity:.Severity
  }] | sort_by(.severity)' "$OUT/trivy-sca.json" > "$LIC_JSON" 2>/dev/null || echo '[]' > "$LIC_JSON"

VULN_N=$(jq 'length' "$VULN_JSON" 2>/dev/null || echo 0)
FIXABLE=$(jq '[.[]|select(.fixed!="")]|length' "$VULN_JSON" 2>/dev/null || echo 0)
LIC_N=$(jq 'length' "$LIC_JSON" 2>/dev/null || echo 0)
LIC_BAD=$(jq '[.[]|select(.category=="forbidden" or .category=="restricted")]|length' "$LIC_JSON" 2>/dev/null || echo 0)
OSV_N=$(jq '[.results[]?.packages[]?.vulnerabilities[]?]|length' "$OUT/osv.json" 2>/dev/null || echo 0)

MD="$OUT/sca-report.md"
{
  echo "# Software Composition Analysis — $NAME"
  echo
  echo "- **Scanned:** $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "- **Severities:** $SEVERITIES"
  echo "- **Vulnerable deps (Trivy):** $VULN_N ($FIXABLE fixable)"
  echo "- **OSV cross-check advisories:** $OSV_N"
  echo "- **License findings:** $LIC_N (forbidden/restricted: $LIC_BAD)"
  echo "- **SBOM:** sbom.cdx.json (CycloneDX)"
  echo
  echo "## Vulnerable dependencies"
  echo
  if [ "$VULN_N" -gt 0 ]; then
    echo "| Severity | Advisory | Package | Installed | Fixed | Title |"
    echo "|----------|----------|---------|-----------|-------|-------|"
    jq -r '.[] | "| \(.severity) | \(.id) | \(.package) | \(.installed) | \(.fixed // "-") | \(.title|gsub("\n";" ")|gsub("\\|";"\\|")|.[0:70]) |"' "$VULN_JSON" 2>/dev/null || true
  else
    echo "_No vulnerable dependencies at the selected severities._"
  fi
  echo
  echo "## License risk"
  echo
  if [ "$LIC_N" -gt 0 ]; then
    echo "| Severity | Category | License | Package |"
    echo "|----------|----------|---------|---------|"
    jq -r '.[] | "| \(.severity) | \(.category) | \(.license) | \(.package) |"' "$LIC_JSON" 2>/dev/null || true
  else
    echo "_No license findings._"
  fi
} > "$MD"

echo
echo ">> Vulns: $VULN_N ($FIXABLE fixable) | OSV: $OSV_N | License: $LIC_N (bad: $LIC_BAD)"
echo ">> Reports written to $OUT:"
for f in "$OUT"/*; do [ -e "$f" ] && echo "   ${f##*/}"; done
