#!/usr/bin/env bash
# Tag and push a local image to Amazon ECR (creating the repo if missing).
# Usage: push-ecr.sh [-p aws-profile] [-r region] [-s] <local-image[:tag]> <ecr-repo[:tag]>
#   -s  enable scan-on-push (basic scanning) on the repository
set -euo pipefail

PROFILE="${AWS_PROFILE:-default}"
REGION="${AWS_REGION:-}"
SCAN_ON_PUSH=0
while getopts "p:r:s" opt; do
  case $opt in
    p) PROFILE="$OPTARG" ;;
    r) REGION="$OPTARG" ;;
    s) SCAN_ON_PUSH=1 ;;
    *) echo "usage: push-ecr.sh [-p profile] [-r region] [-s] <local-image> <ecr-repo[:tag]>" >&2; exit 1 ;;
  esac
done
shift $((OPTIND-1))

LOCAL="${1:?usage: push-ecr.sh [-p profile] [-r region] [-s] <local-image> <ecr-repo[:tag]>}"
REPO_TAG="${2:?provide the target ECR repo[:tag]}"
command -v aws >/dev/null || { echo "aws CLI not installed" >&2; exit 1; }
docker info >/dev/null 2>&1 || { echo "Docker daemon not running" >&2; exit 1; }

REPO="${REPO_TAG%%:*}"
TAG="latest"
case "$REPO_TAG" in *:*) TAG="${REPO_TAG##*:}";; esac

AWSCTX=(--profile "$PROFILE")
[ -n "$REGION" ] && AWSCTX+=(--region "$REGION")
[ -z "$REGION" ] && REGION="$(aws "${AWSCTX[@]}" configure get region 2>/dev/null || echo)"
[ -z "$REGION" ] && { echo "No region (use -r or set AWS_REGION / profile region)" >&2; exit 1; }

ACCOUNT="$(aws "${AWSCTX[@]}" sts get-caller-identity --query Account --output text)"
REGISTRY="${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com"
echo ">> Registry: $REGISTRY  (profile: $PROFILE, region: $REGION)"

# create repo if missing
if ! aws "${AWSCTX[@]}" ecr describe-repositories --repository-names "$REPO" >/dev/null 2>&1; then
  echo ">> Creating ECR repository '$REPO'..."
  CREATE=(ecr create-repository --repository-name "$REPO")
  [ "$SCAN_ON_PUSH" = 1 ] && CREATE+=(--image-scanning-configuration scanOnPush=true)
  aws "${AWSCTX[@]}" "${CREATE[@]}" >/dev/null
elif [ "$SCAN_ON_PUSH" = 1 ]; then
  aws "${AWSCTX[@]}" ecr put-image-scanning-configuration \
    --repository-name "$REPO" --image-scanning-configuration scanOnPush=true >/dev/null || true
fi

echo ">> Logging in to ECR (token valid ~12h)..."
aws "${AWSCTX[@]}" ecr get-login-password | docker login --username AWS --password-stdin "$REGISTRY"

TARGET="${REGISTRY}/${REPO}:${TAG}"
echo ">> Tagging $LOCAL -> $TARGET"
docker tag "$LOCAL" "$TARGET"
echo ">> Pushing $TARGET"
docker push "$TARGET"

if [ "$SCAN_ON_PUSH" = 1 ]; then
  echo ">> Scan-on-push enabled; fetching findings summary (may take a moment)..."
  aws "${AWSCTX[@]}" ecr describe-image-scan-findings \
    --repository-name "$REPO" --image-id imageTag="$TAG" \
    --query 'imageScanFindings.findingSeverityCounts' --output json 2>/dev/null \
    || echo "   (scan not ready yet — check the ECR console or re-run describe-image-scan-findings)"
fi

echo ">> Done: $TARGET"
