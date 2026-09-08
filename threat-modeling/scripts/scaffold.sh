#!/usr/bin/env bash
# Scaffold a new threat model from templates, and (optionally) launch OWASP Threat Dragon.
# Usage:
#   scaffold.sh <app-name> [target-dir]   # create <target-dir>/<app-name>/ from templates
#   scaffold.sh --serve                    # launch Threat Dragon locally via Docker
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATES="$SKILL_DIR/templates"

if [ "${1:-}" = "--serve" ]; then
  docker info >/dev/null 2>&1 || { echo "Docker daemon not running" >&2; exit 1; }
  command -v openssl >/dev/null || { echo "openssl not found (needed to generate keys)" >&2; exit 1; }
  # default to the :stable release; arm64 macs need the -arm64 tag (no multi-arch manifest)
  if [ -n "${THREAT_DRAGON_IMAGE:-}" ]; then
    TD_IMAGE="$THREAT_DRAGON_IMAGE"
  elif [ "$(uname -m)" = "arm64" ] || [ "$(uname -m)" = "aarch64" ]; then
    TD_IMAGE="owasp/threat-dragon:v2.6.2-arm64"
  else
    TD_IMAGE="owasp/threat-dragon:stable"
  fi
  echo ">> Pulling $TD_IMAGE ..."
  docker pull "$TD_IMAGE" || echo "(pull failed — using cached image if present)"
  # ephemeral encryption keys — the server refuses to start without them (local dev mode)
  K1=$(openssl rand -hex 16); K2=$(openssl rand -hex 16); K3=$(openssl rand -hex 16)
  echo ">> Starting Threat Dragon on http://localhost:3000 (Ctrl-C to stop)..."
  echo "   Click 'Login to Local Session' to open/save .json models from disk (no OAuth needed)."
  exec docker run --rm -it -p 3000:3000 --name threatdragon \
    -e ENCRYPTION_JWT_REFRESH_SIGNING_KEY="$K1" \
    -e ENCRYPTION_JWT_SIGNING_KEY="$K2" \
    -e ENCRYPTION_KEYS="[{\"isPrimary\": true, \"id\": 0, \"value\": \"$K3\"}]" \
    -e NODE_ENV="development" \
    -e SERVER_API_PROTOCOL="http" \
    "$TD_IMAGE"
fi

APP="${1:?usage: scaffold.sh <app-name> [target-dir]  |  scaffold.sh --serve}"
BASE="${2:-applications}"
DEST="$BASE/$APP"

if [ -e "$DEST" ]; then
  echo "Refusing to overwrite existing $DEST" >&2
  exit 1
fi
mkdir -p "$DEST"
cp "$TEMPLATES/architecture.mmd" "$TEMPLATES/data-flow.mmd" \
   "$TEMPLATES/threat-model.md" "$TEMPLATES/threat-register.md" \
   "$TEMPLATES/risks.md" "$TEMPLATES/README.md" "$DEST/"

# threat-dragon.json with the app name filled in
sed "s/__APP_NAME__/$APP/g" "$TEMPLATES/threat-dragon.json" > "$DEST/threat-dragon.json"

echo ">> Created threat model scaffold at $DEST:"
for f in "$DEST"/*; do [ -e "$f" ] && echo "   ${f##*/}"; done
echo
echo "Next:"
echo "  1) Fill in README.md, architecture.mmd, data-flow.mmd (see references/methodology.md)."
echo "  2) Run '$0 --serve' to open Threat Dragon and build the DFD + STRIDE threats."
echo "  3) Save the model over $DEST/threat-dragon.json, then complete threat-register.md."
