#!/usr/bin/env bash
# Clone every repo in an org/group and run secure-code-review on each, one by one.
# Sources:
#   - GitHub org/user via `gh` (default):   scan-org.sh <org>
#   - Any git host via a clone-URL file:     scan-org.sh -f urls.txt
#     (one clone URL per line — works for GitHub/GitLab/Bitbucket/self-hosted)
# Options:
#   -f <file>   read clone URLs from a file instead of querying GitHub
#   -l <n>      limit number of repos (GitHub mode; default 200)
#   -o <dir>    output directory (default ~/code-review/<label>_ORGSCAN_<datetime>)
#   -k          keep full clones (default: shallow --depth 1, deleted after each scan)
set -euo pipefail

URLS_FILE=""
LIMIT=200
OUTDIR=""
KEEP=0
while getopts "f:l:o:k" opt; do
  case $opt in
    f) URLS_FILE="$OPTARG" ;;
    l) LIMIT="$OPTARG" ;;
    o) OUTDIR="$OPTARG" ;;
    k) KEEP=1 ;;
    *) echo "usage: scan-org.sh [-f urls.txt | <github-org>] [-l n] [-o dir] [-k]" >&2; exit 1 ;;
  esac
done
shift $((OPTIND-1))

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REVIEW="$SCRIPT_DIR/review.sh"
command -v git >/dev/null || { echo "git not installed" >&2; exit 1; }
command -v jq  >/dev/null || { echo "jq not installed" >&2; exit 1; }
docker info >/dev/null 2>&1 || { echo "Docker daemon not running" >&2; exit 1; }

# ---- enumerate clone URLs ----
declare -a URLS
if [ -n "$URLS_FILE" ]; then
  LABEL="$(basename "$URLS_FILE" | sed 's/\.[^.]*$//')"
  while IFS= read -r line; do
    line="$(echo "$line" | sed 's/[[:space:]]//g')"
    [ -n "$line" ] && [ "${line#\#}" = "$line" ] && URLS+=("$line")
  done < "$URLS_FILE"
else
  ORG="${1:?usage: scan-org.sh [-f urls.txt | <github-org>] [-l n] [-o dir] [-k]}"
  command -v gh >/dev/null || { echo "gh (GitHub CLI) not installed; use -f urls.txt instead" >&2; exit 1; }
  gh auth status >/dev/null 2>&1 || { echo "gh not authenticated (run: gh auth login)" >&2; exit 1; }
  LABEL="$ORG"
  echo ">> Listing repos for '$ORG' via gh (limit $LIMIT)..."
  while IFS= read -r url; do [ -n "$url" ] && URLS+=("$url"); done < <(
    gh repo list "$ORG" --limit "$LIMIT" --no-archived --json sshUrl --jq '.[].sshUrl'
  )
fi

COUNT=${#URLS[@]}
[ "$COUNT" -eq 0 ] && { echo "No repositories found." >&2; exit 1; }

TS=$(date +%Y%m%d_%H%M%S)
OUT="${OUTDIR:-$HOME/code-review/${LABEL}_ORGSCAN_${TS}}"
CLONES="$OUT/clones"
REPORTS="$OUT/reports"
mkdir -p "$CLONES" "$REPORTS"
echo ">> $COUNT repo(s) to scan. Output: $OUT"

SUMMARY="$OUT/summary.md"
{
  echo "# Org Secure Code Review — $LABEL"
  echo
  echo "- **Scanned:** $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "- **Repositories:** $COUNT"
  echo
  echo "| # | Repository | Errors | Warnings | Info | Total | Report |"
  echo "|---|-----------|--------|----------|------|-------|--------|"
} > "$SUMMARY"

i=0
for url in "${URLS[@]}"; do
  i=$((i+1))
  name="$(basename "$url" .git)"
  echo
  echo "==================== [$i/$COUNT] $name ===================="
  dest="$CLONES/$name"
  rm -rf "$dest"
  if [ "$KEEP" = 1 ]; then CLONE_ARGS=(); else CLONE_ARGS=(--depth 1); fi
  if ! git clone --quiet "${CLONE_ARGS[@]}" "$url" "$dest" 2>"$OUT/${name}.clone.log"; then
    echo ">> clone FAILED (see ${name}.clone.log) — skipping"
    echo "| $i | $name | - | - | - | - | clone failed |" >> "$SUMMARY"
    continue
  fi

  repdir="$REPORTS/$name"
  bash "$REVIEW" -o "$repdir" "$dest" || echo ">> review.sh returned non-zero for $name (continuing)"

  # per-repo severity counts from semgrep.json
  json="$repdir/semgrep.json"
  if [ -s "$json" ]; then
    err=$(jq '[.results[]|select(.extra.severity=="ERROR")]|length' "$json" 2>/dev/null || echo 0)
    wrn=$(jq '[.results[]|select(.extra.severity=="WARNING")]|length' "$json" 2>/dev/null || echo 0)
    inf=$(jq '[.results[]|select(.extra.severity=="INFO")]|length' "$json" 2>/dev/null || echo 0)
    tot=$(jq '.results|length' "$json" 2>/dev/null || echo 0)
    echo "| $i | $name | $err | $wrn | $inf | $tot | reports/$name/ |" >> "$SUMMARY"
  else
    echo "| $i | $name | ? | ? | ? | ? | reports/$name/ (no json) |" >> "$SUMMARY"
  fi

  [ "$KEEP" = 1 ] || rm -rf "$dest"
done

echo
echo ">> Done. Aggregate summary: $SUMMARY"
echo ">> Per-repo reports under: $REPORTS/"
