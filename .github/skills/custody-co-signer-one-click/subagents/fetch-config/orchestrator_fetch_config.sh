#!/usr/bin/env bash
set -euo pipefail

# Subagent 2: Console Configuration Fetch (Wrapper Script)
# Queries Console API to get app_id and system_rsa

COOKIE=""
WORKSTATION_ID=""
CONSOLE_DOMAIN="https://custody.chainup.com"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cookie) COOKIE="$2"; shift 2 ;;
    --workstation-id) WORKSTATION_ID="$2"; shift 2 ;;
    --console-domain) CONSOLE_DOMAIN="$2"; shift 2 ;;
    *) echo "[ERROR] Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$COOKIE" ]] || [[ -z "$WORKSTATION_ID" ]]; then
  echo "[ERROR] COOKIE and WORKSTATION_ID required" >&2
  exit 1
fi

# Extract cookie value
COINXMAN_SSO="${COOKIE##*=}"

# Query Console API
API_URL="${CONSOLE_DOMAIN}/api/mpc/api/detail?wallet_id=${WORKSTATION_ID}"
RESPONSE=$(curl -s -H "Cookie: COINXMAN-SSO=${COINXMAN_SSO}" \
  -H "build-cu: web" -H "language: en_US" \
  -H "platform: Chainup" -H "timezone: Asia/Shanghai" \
  "$API_URL" 2>/dev/null || echo "{}")

# Extract app_id and system_rsa
APP_ID=$(echo "$RESPONSE" | grep -o '"app_id":"[^"]*"' | cut -d'"' -f4 || echo "")
SYSTEM_RSA=$(echo "$RESPONSE" | grep -o '"system_rsa":"[^"]*"' | cut -d'"' -f4 || echo "")
BELIEVE_IPS=$(echo "$RESPONSE" | grep -o '"believe_ips":"[^"]*"' | cut -d'"' -f4 || echo "")

if [[ -z "$SYSTEM_RSA" ]]; then
  echo "[WARN] system_rsa missing in detail response" >&2
fi

# Return in key=value format
echo "APP_ID=$APP_ID"
echo "SYSTEM_RSA=$SYSTEM_RSA"
echo "BELIEVE_IPS=$BELIEVE_IPS"
if [[ -n "$APP_ID" ]]; then
  echo "API_EXISTS=true"
else
  echo "API_EXISTS=false"
fi
