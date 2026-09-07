#!/usr/bin/env bash
# Subdomain-takeover scanning via dnsReaper + nuclei takeover templates (Docker images).
# Usage: scan.sh [-n] [-o output-dir] <domains-file | domain[,domain2,...]>
#   -n  also run nuclei takeover templates (ACTIVE HTTP probing — requires authorization)
set -euo pipefail

RUN_NUCLEI=0
OUTDIR=""
while getopts "no:" opt; do
  case $opt in
    n) RUN_NUCLEI=1 ;;
    o) OUTDIR="$OPTARG" ;;
    *) echo "usage: scan.sh [-n] [-o output-dir] <domains-file | domain[,domain2,...]>" >&2; exit 1 ;;
  esac
done
shift $((OPTIND-1))

TARGET="${1:?usage: scan.sh [-n] [-o output-dir] <domains-file | domain[,domain2,...]>}"
command -v jq >/dev/null || { echo "jq not installed" >&2; exit 1; }
docker info >/dev/null 2>&1 || { echo "Docker daemon not running" >&2; exit 1; }

TS=$(date +%Y%m%d_%H%M%S)
if [ -f "$TARGET" ]; then
  LABEL="$(basename "$TARGET" | sed 's/\.[^.]*$//')"
else
  LABEL="${TARGET%%,*}"
fi
OUT="${OUTDIR:-$HOME/dns-takeover/${LABEL}_REPORT_${TS}}"
mkdir -p "$OUT"

# normalize the target into a domains file inside the output dir
DOMAINS_FILE="$OUT/domains.txt"
if [ -f "$TARGET" ]; then
  grep -vE '^\s*$' "$TARGET" | sed 's/[[:space:]]//g' | sort -u > "$DOMAINS_FILE"
else
  printf '%s\n' "${TARGET//,/$'\n'}" | grep -vE '^\s*$' | sort -u > "$DOMAINS_FILE"
fi
echo ">> $(grep -c . "$DOMAINS_FILE") target(s) in $DOMAINS_FILE"

DNSREAPER_IMAGE="${DNSREAPER_IMAGE:-punksecurity/dnsreaper:latest}"
echo ">> Pulling $DNSREAPER_IMAGE ..."
docker pull "$DNSREAPER_IMAGE" || echo "(pull failed — using cached image if present)"

echo ">> Running dnsReaper (passive takeover fingerprinting)..."
# container workdir is /etc/dnsreaper; mount output dir there for the input file.
# dnsReaper writes findings only (empty output when none), so stream JSON to stdout
# and normalize; progress/banner goes to a log.
DR_JSON="$OUT/dnsreaper-results.json"
docker run --rm -v "$OUT:/etc/dnsreaper" "$DNSREAPER_IMAGE" \
  file --filename /etc/dnsreaper/domains.txt \
  --out stdout --out-format json \
  > "$DR_JSON" 2> "$OUT/dnsreaper.log" || true
# normalize empty / non-JSON (no findings) to an empty array
jq -e . "$DR_JSON" >/dev/null 2>&1 || echo '[]' > "$DR_JSON"

DR_COUNT=$(jq 'length' "$DR_JSON" 2>/dev/null || echo 0)
echo ">> dnsReaper findings: $DR_COUNT"

NUCLEI_COUNT=0
if [ "$RUN_NUCLEI" = 1 ]; then
  NUCLEI_IMAGE="${NUCLEI_IMAGE:-projectdiscovery/nuclei:latest}"
  echo ">> ACTIVE mode: nuclei will send live HTTP requests to the targets."
  echo ">> Pulling $NUCLEI_IMAGE ..."
  docker pull "$NUCLEI_IMAGE" || echo "(pull failed — using cached image if present)"
  echo ">> Running nuclei takeover templates..."
  # persistent named volume caches nuclei-templates between runs
  docker run --rm \
    -v nuclei-templates:/root/nuclei-templates \
    -v "$OUT:/app" \
    "$NUCLEI_IMAGE" \
    -l /app/domains.txt -tags takeover -jsonl -o /app/nuclei-results.jsonl \
    -stats -silent || true
  NU_JSONL="$OUT/nuclei-results.jsonl"
  [ -s "$NU_JSONL" ] && NUCLEI_COUNT=$(grep -c . "$NU_JSONL" || echo 0)
  echo ">> nuclei findings: $NUCLEI_COUNT"
fi

# markdown report
MD="$OUT/takeover-report.md"
{
  echo "# Subdomain Takeover Scan — $LABEL"
  echo
  echo "- **Scanned:** $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "- **Targets:** $(grep -c . "$DOMAINS_FILE")"
  echo "- **dnsReaper findings:** $DR_COUNT"
  echo "- **nuclei findings:** $([ "$RUN_NUCLEI" = 1 ] && echo "$NUCLEI_COUNT" || echo 'not run (passive only)')"
  echo
  echo "## dnsReaper (takeover fingerprints)"
  echo
  if [ "$DR_COUNT" -gt 0 ]; then
    echo "| Domain | Service (signature) | Confidence | More info |"
    echo "|--------|---------------------|------------|-----------|"
    jq -r '.[] | "| \(.domain) | \(.signature) | \(.confidence) | \(.more_info_url // "-") |"' "$DR_JSON" 2>/dev/null || true
  else
    echo "_No takeover fingerprints matched._"
  fi
  if [ "$RUN_NUCLEI" = 1 ]; then
    echo
    echo "## nuclei (takeover templates)"
    echo
    if [ "$NUCLEI_COUNT" -gt 0 ]; then
      echo "| Template | Severity | Host |"
      echo "|----------|----------|------|"
      jq -r '"| \(.["template-id"]) | \(.info.severity) | \(.host) |"' "$NU_JSONL" 2>/dev/null || true
    else
      echo "_No takeover templates matched._"
    fi
  fi
} > "$MD"

echo
echo ">> Reports written to $OUT:"
ls -1 "$OUT" | sed 's/^/   /'
