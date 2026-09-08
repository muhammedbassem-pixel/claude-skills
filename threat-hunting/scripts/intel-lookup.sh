#!/usr/bin/env bash
# Look up an indicator against public threat intelligence (abuse.ch ThreatFox).
# Requires a free abuse.ch Auth-Key (https://auth.abuse.ch/) in $ABUSECH_KEY.
# Usage: intel-lookup.sh <ioc>            # search ThreatFox for an IP/domain/URL/hash
#        intel-lookup.sh -f <iocs-file>   # look up each IoC in a file
set -euo pipefail

FILE=""
while getopts "f:" opt; do
  case $opt in
    f) FILE="$OPTARG" ;;
    *) echo "usage: intel-lookup.sh <ioc> | -f <iocs-file>" >&2; exit 1 ;;
  esac
done
shift $((OPTIND-1))

command -v curl >/dev/null || { echo "curl not installed" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq not installed" >&2; exit 1; }
: "${ABUSECH_KEY:?set ABUSECH_KEY (free key from https://auth.abuse.ch/)}"

lookup() {
  local ioc="$1"
  [ -n "$ioc" ] || return 0
  local resp
  resp=$(curl -sS -H "Auth-Key: $ABUSECH_KEY" -X POST https://threatfox-api.abuse.ch/api/v1/ \
    -d "{\"query\":\"search_ioc\",\"search_term\":\"$ioc\"}" 2>/dev/null || echo '{}')
  local status
  status=$(jq -r '.query_status // "error"' <<<"$resp" 2>/dev/null || echo error)
  if [ "$status" = "ok" ]; then
    echo "⚠️  MATCH  $ioc"
    jq -r '.data[]? | "     - \(.threat_type_desc // .threat_type) | malware: \(.malware_printable // "?") | confidence: \(.confidence_level)% | first_seen: \(.first_seen)"' <<<"$resp" 2>/dev/null || true
  elif [ "$status" = "no_result" ]; then
    echo "clean   $ioc"
  else
    echo "error   $ioc ($status)"
  fi
}

if [ -n "$FILE" ]; then
  [ -f "$FILE" ] || { echo "file not found: $FILE" >&2; exit 1; }
  while IFS= read -r line; do
    line="$(printf '%s' "$line" | tr -d '[:space:]')"
    [ -n "$line" ] && lookup "$line"
  done < "$FILE"
else
  IOC="${1:?usage: intel-lookup.sh <ioc> | -f <iocs-file>}"
  lookup "$IOC"
fi
