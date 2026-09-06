#!/usr/bin/env bash
# AWS security audit via Prowler (official Docker image).
# Usage: audit.sh [-p aws-profile] [-r "region1 region2" | -r all] [-s "critical high"] [output-dir]
set -euo pipefail

PROFILE="${AWS_PROFILE:-default}"
REGIONS="all"
SEVERITIES=""
while getopts "p:r:s:" opt; do
  case $opt in
    p) PROFILE="$OPTARG" ;;
    r) REGIONS="$OPTARG" ;;
    s) SEVERITIES="$OPTARG" ;;
    *) echo "usage: audit.sh [-p profile] [-r \"regions\"|all] [-s \"severities\"] [output-dir]" >&2; exit 1 ;;
  esac
done
shift $((OPTIND-1))

command -v aws >/dev/null || { echo "aws CLI not installed (brew install awscli)" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq not installed" >&2; exit 1; }
docker info >/dev/null 2>&1 || { echo "Docker daemon not running" >&2; exit 1; }

echo ">> Verifying AWS credentials (profile: $PROFILE)..."
IDENTITY=$(aws sts get-caller-identity --profile "$PROFILE" --output json)
ACCOUNT=$(jq -r '.Account' <<<"$IDENTITY")
echo "   Account: $ACCOUNT | $(jq -r '.Arn' <<<"$IDENTITY")"

TS=$(date +%Y%m%d_%H%M%S)
OUT="${1:-$HOME/aws-audit/${ACCOUNT}_REPORT_${TS}}"
mkdir -p "$OUT"

# short-lived creds resolved by the CLI (works for SSO, MFA, assumed roles);
# fall back to mounting ~/.aws read-only if export-credentials is unavailable
CRED_ARGS=()
if CREDS=$(aws configure export-credentials --profile "$PROFILE" --format env-no-export 2>/dev/null); then
  while IFS= read -r line; do [ -n "$line" ] && CRED_ARGS+=(-e "$line"); done <<<"$CREDS"
else
  CRED_ARGS=(-v "$HOME/.aws:/home/prowler/.aws:ro" -e "AWS_PROFILE=$PROFILE")
fi

REGION_ARGS=()
if [ "$REGIONS" != all ]; then
  # shellcheck disable=SC2206  # intentional word-split of the region list
  REGION_ARGS=(-f $REGIONS)
fi
SEV_ARGS=()
if [ -n "$SEVERITIES" ]; then
  # shellcheck disable=SC2206
  SEV_ARGS=(--severity $SEVERITIES)
fi

PROWLER_IMAGE="${PROWLER_IMAGE:-prowlercloud/prowler:latest}"
echo ">> Pulling $PROWLER_IMAGE ..."
docker pull "$PROWLER_IMAGE" || echo "(pull failed — using cached image if present)"

echo ">> Running Prowler (regions: $REGIONS${SEVERITIES:+, severities: $SEVERITIES})..."
docker run --rm \
  "${CRED_ARGS[@]}" \
  -v "$OUT:/home/prowler/output" \
  "$PROWLER_IMAGE" aws \
  "${REGION_ARGS[@]}" \
  "${SEV_ARGS[@]}" \
  -M csv json-ocsf html \
  -F "prowler-${ACCOUNT}-${TS}" \
  -z

OCSF="$OUT/prowler-${ACCOUNT}-${TS}.ocsf.json"
echo
echo ">> Summary of FAILED findings by severity:"
if [ -s "$OCSF" ]; then
  jq -r '[.[] | select(.status_code == "FAIL")]
    | group_by(.severity) | map({s: .[0].severity, n: length})
    | sort_by(.s) | .[] | "   \(.s): \(.n)"' "$OCSF" 2>/dev/null \
    || echo "   (could not parse OCSF JSON — open the HTML report)"
  echo "   total FAIL: $(jq '[.[] | select(.status_code == "FAIL")] | length' "$OCSF" 2>/dev/null || echo '?')"
else
  echo "   (no OCSF report found — check prowler output above)"
fi

echo
echo ">> Reports written to $OUT:"
ls -1 "$OUT" | sed 's/^/   /'
