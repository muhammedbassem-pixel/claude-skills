#!/usr/bin/env bash
# Inspect logs for Indicators of Compromise (IoCs).
# Extracts IoCs from a feed/report (iocextract) — or takes a ready IoC list — then matches
# them against your logs with fixed-string grep.
# Usage: hunt-logs.sh -i <ioc-source> [-o output-dir] <logs-path>
#   -i  a file to pull IoCs from (a threat report / feed / an existing IoC list)
set -euo pipefail

IOC_SRC=""
OUTDIR=""
while getopts "i:o:" opt; do
  case $opt in
    i) IOC_SRC="$OPTARG" ;;
    o) OUTDIR="$OPTARG" ;;
    *) echo "usage: hunt-logs.sh -i <ioc-source> [-o output-dir] <logs-path>" >&2; exit 1 ;;
  esac
done
shift $((OPTIND-1))

LOGS="${1:?usage: hunt-logs.sh -i <ioc-source> [-o output-dir] <logs-path>}"
[ -n "$IOC_SRC" ] || { echo "provide an IoC source with -i" >&2; exit 1; }
[ -e "$LOGS" ] || { echo "logs path not found: $LOGS" >&2; exit 1; }
[ -f "$IOC_SRC" ] || { echo "IoC source not found: $IOC_SRC" >&2; exit 1; }
docker info >/dev/null 2>&1 || { echo "Docker daemon not running" >&2; exit 1; }

LOGS="$(cd "$(dirname "$LOGS")" && pwd)/$(basename "$LOGS")"
IOC_SRC="$(cd "$(dirname "$IOC_SRC")" && pwd)/$(basename "$IOC_SRC")"
TS=$(date +%Y%m%d_%H%M%S)
OUT="${OUTDIR:-$HOME/threat-hunting/logs_${TS}}"
mkdir -p "$OUT"

PY_IMAGE="${PY_IMAGE:-python:3.12-slim}"
echo ">> Extracting IoCs from $(basename "$IOC_SRC") with iocextract..."
# iocextract (needs requests) pulls IPs, URLs, hashes, emails — refanged (hxxp://, 1[.]2[.]3[.]4).
# No extractor flags = extract all types; -r refangs defanged indicators.
docker run --rm -v "$IOC_SRC:/src.txt:ro" -v "$OUT:/out" "$PY_IMAGE" \
  sh -c "pip install --quiet iocextract requests >/dev/null 2>&1 && \
    iocextract -i /src.txt -r 2>/dev/null | sort -u > /out/iocs.raw" || true
# build the hunt list: extracted IoCs + bare hostnames derived from any URLs
# (so a domain IoC matches log lines that reference the host without the scheme/path)
{
  cat "$OUT/iocs.raw" 2>/dev/null || true
  sed -nE 's#^[a-zA-Z][a-zA-Z0-9+.-]*://([^/:]+).*#\1#p' "$OUT/iocs.raw" 2>/dev/null || true
} | grep -vE '^\s*$' | sort -u > "$OUT/iocs.txt"
rm -f "$OUT/iocs.raw"
# fallback: if iocextract yielded nothing, use the source lines verbatim
[ -s "$OUT/iocs.txt" ] || { grep -vE '^\s*$' "$IOC_SRC" | sort -u > "$OUT/iocs.txt"; }
IOC_N=$(grep -c . "$OUT/iocs.txt" 2>/dev/null || echo 0)
echo ">> $IOC_N unique IoC(s) to hunt."

echo ">> Matching IoCs against logs ($LOGS)..."
HITS="$OUT/hits.txt"
: > "$HITS"
if [ "$IOC_N" -gt 0 ]; then
  # fixed-string, show file:line; recurse if a directory
  if [ -d "$LOGS" ]; then
    grep -RFf "$OUT/iocs.txt" "$LOGS" -n 2>/dev/null >> "$HITS" || true
  else
    grep -Ff "$OUT/iocs.txt" "$LOGS" -n 2>/dev/null >> "$HITS" || true
  fi
fi
HIT_N=$(grep -c . "$HITS" 2>/dev/null || echo 0)

# which IoCs actually matched
MATCHED="$OUT/matched-iocs.txt"
: > "$MATCHED"
while IFS= read -r ioc; do
  [ -n "$ioc" ] || continue
  if grep -qF -- "$ioc" "$HITS" 2>/dev/null; then
    c=$(grep -cF -- "$ioc" "$HITS" 2>/dev/null || echo 0)
    echo "$c  $ioc" >> "$MATCHED"
  fi
done < "$OUT/iocs.txt"
sort -rn "$MATCHED" -o "$MATCHED" 2>/dev/null || true

{
  echo "# Log IoC Hunt"
  echo
  echo "- **Scanned:** $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "- **Logs:** $LOGS"
  echo "- **IoCs hunted:** $IOC_N"
  echo "- **Log line matches:** $HIT_N"
  echo "- **Distinct IoCs matched:** $(grep -c . "$MATCHED" 2>/dev/null || echo 0)"
  echo
  if [ -s "$MATCHED" ]; then
    echo "## ⚠️  Matched IoCs (count  indicator)"
    echo
    echo '```'
    cat "$MATCHED"
    echo '```'
    echo
    echo "See \`hits.txt\` for the matching log lines (file:line)."
  else
    echo "_No IoCs matched the logs._"
  fi
} > "$OUT/log-hunt-report.md"

echo
echo ">> $HIT_N matching log line(s); $(grep -c . "$MATCHED" 2>/dev/null || echo 0) distinct IoC(s) matched."
echo ">> Reports written to $OUT:"
for f in "$OUT"/*; do [ -e "$f" ] && echo "   ${f##*/}"; done
