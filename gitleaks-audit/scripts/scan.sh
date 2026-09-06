#!/usr/bin/env bash
# Full-history gitleaks scan across all branches + unredacted markdown report.
# Usage: scan.sh <repo-path> [output-dir]
set -euo pipefail

REPO="${1:?usage: scan.sh <repo-path> [output-dir]}"
REPO="$(cd "$REPO" && pwd)"
# reports always land under ~/gitleaks (outside any repo, so the unredacted
# report can't be committed by accident), one timestamped dir per run
OUT="${2:-$HOME/gitleaks/$(basename "$REPO")_REPORT_$(date +%Y%m%d_%H%M%S)}"
mkdir -p "$OUT"
JSON="$OUT/gitleaks-report.json"
MD="$OUT/gitleaks-report.md"

command -v jq >/dev/null || { echo "jq not installed" >&2; exit 1; }

# Prefer the official Docker image; fall back to a local gitleaks binary.
# Override with GITLEAKS_MODE=docker|binary and GITLEAKS_IMAGE=<image:tag>.
GITLEAKS_IMAGE="${GITLEAKS_IMAGE:-ghcr.io/gitleaks/gitleaks:latest}"
MODE="${GITLEAKS_MODE:-auto}"
if [ "$MODE" = auto ]; then
  if docker info >/dev/null 2>&1; then MODE=docker
  elif command -v gitleaks >/dev/null; then MODE=binary
  else
    echo "Neither a running Docker daemon nor a gitleaks binary found." >&2
    echo "Start Docker, or install gitleaks (brew install gitleaks)." >&2
    exit 1
  fi
fi

echo ">> Fetching all refs..."
git -C "$REPO" fetch --all --prune --tags 2>/dev/null || echo "(fetch skipped — no remote or offline)"

echo ">> Scanning all branches and commits (unredacted) via $MODE..."
if [ "$MODE" = docker ]; then
  # always refresh the image — `docker run` alone won't update a cached :latest
  echo ">> Pulling $GITLEAKS_IMAGE ..."
  docker pull "$GITLEAKS_IMAGE" || echo "(pull failed — using cached image if present)"
  # repo mounted read-only; report written to the mounted output dir.
  # GIT_CONFIG_* marks the mounted repo safe.directory (host UID != container UID).
  docker run --rm \
    -v "$REPO:/repo:ro" \
    -v "$OUT:/out" \
    -e GIT_CONFIG_COUNT=1 \
    -e GIT_CONFIG_KEY_0=safe.directory \
    -e GIT_CONFIG_VALUE_0='*' \
    "$GITLEAKS_IMAGE" \
    git /repo \
    --log-opts="--all --full-history" \
    --report-format json \
    --report-path /out/gitleaks-report.json \
    --exit-code 0
else
  gitleaks git "$REPO" \
    --log-opts="--all --full-history" \
    --report-format json \
    --report-path "$JSON" \
    --exit-code 0
fi

# some gitleaks versions skip writing the report when there are zero findings
[ -s "$JSON" ] || echo '[]' > "$JSON"

COUNT=$(jq 'length' "$JSON")
echo ">> $COUNT finding(s)."

DEFAULT_BRANCH=$(git -C "$REPO" symbolic-ref --short HEAD 2>/dev/null || echo "")

# escape one jq field of $f for a single-line markdown table cell
# (backtick -> ´ and newline -> \n so the table can't break; exact raw values
#  are preserved in the JSON report and the fenced detail blocks below)
cell() {
  jq -r "$1"' | tostring
    | gsub("\r"; "")
    | gsub("\n"; "\\n")
    | gsub("\\|"; "\\|")
    | gsub("`"; "´")' <<<"$f"
}

{
  echo "# Gitleaks Audit Report — $(basename "$REPO")"
  echo
  echo "- **Scanned:** $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "- **Repo:** $REPO"
  echo "- **Default branch:** ${DEFAULT_BRANCH:-unknown}"
  echo "- **Scope:** all branches, full history (\`--log-opts=\"--all --full-history\"\`)"
  echo "- **Total findings:** $COUNT"
  echo "- **Unique secrets:** $(jq '[.[].Secret] | unique | length' "$JSON")"
  echo "- **Files affected:** $(jq '[.[].File] | unique | length' "$JSON")"
  echo "- **Rules triggered:** $(jq -r '[.[].RuleID] | unique | join(", ")' "$JSON")"
  echo
  echo "> Secrets are intentionally **unredacted** for rotation. Do not commit this file."
  echo "> Table cells escape backticks as ´ and newlines as \\n; exact raw values are in the"
  echo "> JSON report and the fenced blocks under *Full finding details*."
  echo
  echo "| # | Rule | Secret | File | Lines | Commit | Branches | Live@HEAD | Author | Date |"
  echo "|---|------|--------|------|-------|--------|----------|-----------|--------|------|"
} > "$MD"

i=0
jq -c '.[]' "$JSON" | while IFS= read -r f; do
  i=$((i+1))
  rule=$(cell '.RuleID')
  secret=$(cell '.Secret')
  file=$(cell '.File')
  lines="$(jq -r '.StartLine' <<<"$f")-$(jq -r '.EndLine' <<<"$f")"
  commit=$(jq -r '.Commit' <<<"$f")
  author=$(cell '.Author')
  date=$(jq -r '.Date' <<<"$f")
  # BSD/GNU paste cycle multi-char -d lists, so join with "," then widen
  branches=$(git -C "$REPO" branch -a --contains "$commit" --format='%(refname:short)' 2>/dev/null \
    | sed 's|^origin/||' | sort -u | paste -sd, - | sed 's/,/, /g' || true)
  live="n/a"
  if [ -n "$DEFAULT_BRANCH" ]; then
    # multi-line secrets (PEM keys): grep for the first line only
    probe=$(jq -r '.Secret | split("\n")[0]' <<<"$f")
    if [ -n "$probe" ] && git -C "$REPO" grep -qF -e "$probe" "$DEFAULT_BRANCH" -- 2>/dev/null; then
      live="yes"
    else
      live="no"
    fi
  fi
  echo "| $i | $rule | \`$secret\` | \`$file\` | $lines | \`${commit:0:10}\` | ${branches:-none} | $live | $author | $date |" >> "$MD"
done

{
  echo
  echo "## Full finding details"
  echo
  jq -r '.[] | "### \(.RuleID) — \(.File):\(.StartLine)-\(.EndLine)\n- **Commit:** \(.Commit)\n- **Author:** \(.Author) <\(.Email)>\n- **Date:** \(.Date)\n- **Message:** \(.Message | split("\n")[0])\n- **Entropy:** \(.Entropy)\n- **Fingerprint:** \(.Fingerprint)\n- **Secret (raw):**\n\n````text\n\(.Secret)\n````\n\n- **Match (raw):**\n\n````text\n\(.Match)\n````\n"' "$JSON"
} >> "$MD"

echo ">> Reports written:"
echo "   JSON: $JSON"
echo "   MD:   $MD"
