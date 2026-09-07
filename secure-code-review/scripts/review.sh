#!/usr/bin/env bash
# Multi-language secure code review via Semgrep (+ dart analyze for Flutter).
# Maps to OWASP Top 10 and CWE/SANS Top 25 via registry rule packs.
# Usage: review.sh [-o output-dir] <source-dir>
set -euo pipefail

OUTDIR=""
while getopts "o:" opt; do
  case $opt in
    o) OUTDIR="$OPTARG" ;;
    *) echo "usage: review.sh [-o output-dir] <source-dir>" >&2; exit 1 ;;
  esac
done
shift $((OPTIND-1))

SRC="${1:?usage: review.sh [-o output-dir] <source-dir>}"
SRC="$(cd "$SRC" && pwd)"
command -v jq >/dev/null || { echo "jq not installed" >&2; exit 1; }
docker info >/dev/null 2>&1 || { echo "Docker daemon not running" >&2; exit 1; }

TS=$(date +%Y%m%d_%H%M%S)
NAME="$(basename "$SRC")"
OUT="${OUTDIR:-$HOME/code-review/${NAME}_REPORT_${TS}}"
mkdir -p "$OUT"

SEMGREP_IMAGE="${SEMGREP_IMAGE:-semgrep/semgrep:latest}"
echo ">> Pulling $SEMGREP_IMAGE ..."
docker pull "$SEMGREP_IMAGE" || echo "(pull failed — using cached image if present)"

# cross-cutting security packs + per-language packs (Semgrep applies only the
# rules matching each file's language, so bundling all is safe)
CONFIGS=(
  --config p/security-audit
  --config p/owasp-top-ten
  --config p/cwe-top-25
  --config p/secrets
  --config p/java --config p/python --config p/php
  --config p/react --config p/typescript --config p/javascript
  --config p/golang
)

echo ">> Running Semgrep SAST (OWASP Top 10 + CWE Top 25)..."
# code mounted read-only; results to a writable mount; run as caller to avoid root-owned files
docker run --rm \
  -u "$(id -u):$(id -g)" \
  -e SEMGREP_SEND_METRICS=off \
  -e HOME=/tmp \
  -v "$SRC:/src:ro" \
  -v "$OUT:/out" \
  "$SEMGREP_IMAGE" semgrep scan \
  "${CONFIGS[@]}" \
  --metrics=off \
  --sarif -o /out/semgrep.sarif /src || true

# also emit JSON for the summary
docker run --rm \
  -u "$(id -u):$(id -g)" \
  -e SEMGREP_SEND_METRICS=off \
  -e HOME=/tmp \
  -v "$SRC:/src:ro" \
  -v "$OUT:/out" \
  "$SEMGREP_IMAGE" semgrep scan \
  "${CONFIGS[@]}" \
  --metrics=off \
  --json -o /out/semgrep.json /src || true

# Flutter/Dart: Semgrep Dart support is only experimental — use dart analyze
if [ -f "$SRC/pubspec.yaml" ]; then
  echo ">> Dart/Flutter project detected — running dart analyze..."
  docker run --rm \
    -v "$SRC:/app" -w /app \
    dart:stable sh -c "dart pub get >/dev/null 2>&1 || true; dart analyze --format=machine || true" \
    > "$OUT/dart-analyze.txt" 2>&1 || true
fi

JSON="$OUT/semgrep.json"
echo
echo ">> Findings by severity:"
if [ -s "$JSON" ]; then
  jq -r '.results | group_by(.extra.severity) | map({s: .[0].extra.severity, n: length})
    | .[] | "   \(.s): \(.n)"' "$JSON" 2>/dev/null || echo "   (parse error — see semgrep.sarif)"
  echo "   total: $(jq '.results | length' "$JSON" 2>/dev/null || echo '?')"
  echo
  echo ">> Top findings (severity | rule | file:line):"
  jq -r '.results
    | sort_by(.extra.severity) | reverse | .[:25][]
    | "   \(.extra.severity) | \(.check_id | split(".") | last) | \(.path):\(.start.line)"' \
    "$JSON" 2>/dev/null || true
else
  echo "   (no semgrep JSON produced — check output above)"
fi

echo
echo ">> Reports written to $OUT:"
ls -1 "$OUT" | sed 's/^/   /'
