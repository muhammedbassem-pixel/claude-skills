#!/usr/bin/env bash
# Perimeter recon via OWASP Amass (official Docker image).
# Usage: recon.sh [-a] [-t minutes] [-o output-dir] <domain[,domain2,...]>
#   -a  active mode (zone transfers, cert grabs, brute force) — REQUIRES AUTHORIZATION
#   -t  enum timeout in minutes (default 30)
set -euo pipefail

ACTIVE=0
TIMEOUT=30
OUTDIR=""
while getopts "at:o:" opt; do
  case $opt in
    a) ACTIVE=1 ;;
    t) TIMEOUT="$OPTARG" ;;
    o) OUTDIR="$OPTARG" ;;
    *) echo "usage: recon.sh [-a] [-t minutes] [-o output-dir] <domain[,domain2,...]>" >&2; exit 1 ;;
  esac
done
shift $((OPTIND-1))

DOMAINS="${1:?usage: recon.sh [-a] [-t minutes] [-o output-dir] <domain[,domain2,...]>}"
command -v jq >/dev/null || { echo "jq not installed" >&2; exit 1; }
docker info >/dev/null 2>&1 || { echo "Docker daemon not running" >&2; exit 1; }

TS=$(date +%Y%m%d_%H%M%S)
FIRST="${DOMAINS%%,*}"
OUT="${OUTDIR:-$HOME/amass-recon/${FIRST}_REPORT_${TS}}"
mkdir -p "$OUT"
# amass image runs as a non-root user; make the mounted dir writable by it
chmod 777 "$OUT"

AMASS_IMAGE="${AMASS_IMAGE:-owaspamass/amass:latest}"
echo ">> Pulling $AMASS_IMAGE ..."
docker pull "$AMASS_IMAGE" || echo "(pull failed — using cached image if present)"

MODE_ARGS=()
if [ "$ACTIVE" = 1 ]; then
  echo ">> ACTIVE mode: zone transfers, cert grabs, and brute force WILL touch $DOMAINS."
  MODE_ARGS=(-active -brute)
else
  echo ">> Passive mode (default) — no brute force / zone transfers."
fi

echo ">> Enumerating $DOMAINS (timeout ${TIMEOUT}m)..."
# -dir points amass at the mounted output dir (holds asset.db + logs)
docker run --rm \
  -v "$OUT:/data" \
  "$AMASS_IMAGE" \
  enum -d "$DOMAINS" -timeout "$TIMEOUT" -dir /data "${MODE_ARGS[@]+"${MODE_ARGS[@]}"}" || true

echo ">> Extracting discovered subdomains..."
docker run --rm \
  -v "$OUT:/data" \
  "$AMASS_IMAGE" \
  subs -names -d "$DOMAINS" -dir /data -o /data/subdomains.txt 2>/dev/null || true

# also pull names with IPs for the report, if available
docker run --rm \
  -v "$OUT:/data" \
  "$AMASS_IMAGE" \
  subs -d "$DOMAINS" -ip -dir /data -o /data/subdomains_with_ips.txt 2>/dev/null || true

NAMES="$OUT/subdomains.txt"
COUNT=0
[ -s "$NAMES" ] && COUNT=$(grep -c . "$NAMES" || echo 0)

# markdown report
MD="$OUT/amass-report.md"
{
  echo "# Amass Perimeter Recon — $DOMAINS"
  echo
  echo "- **Scanned:** $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "- **Targets:** $DOMAINS"
  echo "- **Mode:** $([ "$ACTIVE" = 1 ] && echo 'active (brute + zone transfer + cert grab)' || echo 'passive')"
  echo "- **Subdomains discovered:** $COUNT"
  echo
  echo "## Discovered subdomains"
  echo
  echo '```'
  [ -s "$NAMES" ] && sort -u "$NAMES" || echo "(none)"
  echo '```'
  if [ -s "$OUT/subdomains_with_ips.txt" ]; then
    echo
    echo "## Subdomains with resolved IPs"
    echo
    echo '```'
    sort -u "$OUT/subdomains_with_ips.txt"
    echo '```'
  fi
} > "$MD"

echo
echo ">> $COUNT subdomain(s) discovered."
echo ">> Reports written to $OUT:"
for f in "$OUT"/*; do [ -e "$f" ] && echo "   ${f##*/}"; done
