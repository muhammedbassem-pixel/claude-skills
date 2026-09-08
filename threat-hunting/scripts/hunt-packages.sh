#!/usr/bin/env bash
# Hunt vulnerable AND malicious dependencies in a codebase.
# OSV-Scanner (known vulns + OpenSSF MAL- malicious advisories) + GuardDog (heuristic malware).
# Usage: hunt-packages.sh [-e pypi|npm] [-o output-dir] <project-dir>
#   -e  also run GuardDog against the ecosystem's manifest (pypi -> requirements.txt, npm -> package.json)
set -euo pipefail

ECOSYSTEM=""
OUTDIR=""
while getopts "e:o:" opt; do
  case $opt in
    e) ECOSYSTEM="$OPTARG" ;;
    o) OUTDIR="$OPTARG" ;;
    *) echo "usage: hunt-packages.sh [-e pypi|npm] [-o output-dir] <project-dir>" >&2; exit 1 ;;
  esac
done
shift $((OPTIND-1))

SRC="${1:?usage: hunt-packages.sh [-e pypi|npm] [-o output-dir] <project-dir>}"
SRC="$(cd "$SRC" && pwd)"
command -v jq >/dev/null || { echo "jq not installed" >&2; exit 1; }
docker info >/dev/null 2>&1 || { echo "Docker daemon not running" >&2; exit 1; }

TS=$(date +%Y%m%d_%H%M%S)
NAME="$(basename "$SRC")"
OUT="${OUTDIR:-$HOME/threat-hunting/${NAME}_PACKAGES_${TS}}"
mkdir -p "$OUT"

OSV_IMAGE="${OSV_IMAGE:-ghcr.io/google/osv-scanner:latest}"
echo ">> Pulling $OSV_IMAGE ..."
docker pull "$OSV_IMAGE" >/dev/null 2>&1 || echo "(pull failed — using cache)"

echo ">> OSV-Scanner (known vulns + MAL- malicious advisories)..."
docker run --rm -v "$SRC:/src:ro" -v "$OUT:/out" "$OSV_IMAGE" \
  scan source -r --format json --output /out/osv.json /src >/dev/null 2>&1 || true
[ -s "$OUT/osv.json" ] || echo '{"results":[]}' > "$OUT/osv.json"

# separate malicious (MAL-) advisories from ordinary CVEs
jq -r '[.results[]?.packages[]? | .package as $p | .vulnerabilities[]?
        | {ecosystem:$p.ecosystem, package:$p.name, version:$p.version, id:.id,
           summary:(.summary // ""), malicious:((.id|startswith("MAL-")) or ((.aliases//[])|any(startswith("MAL-"))))}]' \
  "$OUT/osv.json" > "$OUT/osv-findings.json" 2>/dev/null || echo '[]' > "$OUT/osv-findings.json"

VULN=$(jq 'length' "$OUT/osv-findings.json" 2>/dev/null || echo 0)
MAL=$(jq '[.[]|select(.malicious)]|length' "$OUT/osv-findings.json" 2>/dev/null || echo 0)
echo ">> OSV: $VULN advisory(ies), $MAL flagged MALICIOUS (MAL-)."

if [ -n "$ECOSYSTEM" ]; then
  GD_IMAGE="${GUARDDOG_IMAGE:-ghcr.io/datadog/guarddog:latest}"
  case "$ECOSYSTEM" in
    pypi) MANIFEST="requirements.txt" ;;
    npm)  MANIFEST="package.json" ;;
    *) echo "unknown ecosystem '$ECOSYSTEM' (use pypi|npm)"; MANIFEST="" ;;
  esac
  if [ -n "$MANIFEST" ] && [ -f "$SRC/$MANIFEST" ]; then
    echo ">> Pulling $GD_IMAGE ..."
    docker pull "$GD_IMAGE" >/dev/null 2>&1 || echo "(pull failed — using cache)"
    echo ">> GuardDog ($ECOSYSTEM verify $MANIFEST) — heuristic malware detection..."
    docker run --rm -v "$SRC:/src:ro" "$GD_IMAGE" \
      "$ECOSYSTEM" verify "/src/$MANIFEST" --output-format json > "$OUT/guarddog.json" 2>"$OUT/guarddog.log" || true
  else
    echo ">> (skipping GuardDog — $MANIFEST not found in $SRC)"
  fi
fi

# markdown report
MD="$OUT/packages-report.md"
{
  echo "# Package Threat Hunt — $NAME"
  echo
  echo "- **Scanned:** $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "- **OSV advisories:** $VULN (MALICIOUS: $MAL)"
  echo
  if [ "$MAL" -gt 0 ]; then
    echo "## ⚠️  MALICIOUS packages (OpenSSF MAL- advisories)"
    echo
    echo "| Ecosystem | Package | Version | ID | Summary |"
    echo "|-----------|---------|---------|----|---------|"
    jq -r '.[] | select(.malicious) | "| \(.ecosystem) | \(.package) | \(.version) | \(.id) | \(.summary|.[0:80]) |"' "$OUT/osv-findings.json" 2>/dev/null || true
    echo
  fi
  echo "## Known-vulnerable dependencies"
  echo
  echo "| Ecosystem | Package | Version | Advisory | Summary |"
  echo "|-----------|---------|---------|----------|---------|"
  jq -r '.[] | select(.malicious|not) | "| \(.ecosystem) | \(.package) | \(.version) | \(.id) | \(.summary|.[0:80]) |"' "$OUT/osv-findings.json" 2>/dev/null || true
} > "$MD"

echo
echo ">> Reports written to $OUT:"
for f in "$OUT"/*; do [ -e "$f" ] && echo "   ${f##*/}"; done
