#!/usr/bin/env bash
set -euo pipefail

# Subagent: MPC Workstation Selection
#
# Fetches the MPC wallet list from Console API and lets the user interactively
# select a workstation. Outputs WORKSTATION_ID=<wallet_id> in key=value format.
#
# Usage:
#   bash orchestrator_select_workstation.sh \
#     --cookie COINXMAN-SSO=<value> \
#     [--console-domain https://custody.chainup.com]
#
# Output (stdout, key=value):
#   WORKSTATION_ID=<wallet_id>
#   WORKSTATION_NAME=<wallet_name>
#   WORKSTATION_EXPIRE=<expire_time>

COOKIE=""
CONSOLE_DOMAIN="https://custody.chainup.com"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cookie)          COOKIE="$2";         shift 2 ;;
    --console-domain)  CONSOLE_DOMAIN="$2"; shift 2 ;;
    *) echo "[ERROR] Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$COOKIE" ]]; then
  echo "[ERROR] --cookie is required" >&2
  exit 1
fi

# Strip optional "COINXMAN-SSO=" prefix so raw value also works
COINXMAN_SSO="${COOKIE#COINXMAN-SSO=}"

# ── Fetch wallet list ────────────────────────────────────────────────────────
RESPONSE=$(curl -s \
  -H "Cookie: COINXMAN-SSO=${COINXMAN_SSO}" \
  -H "build-cu: web" \
  -H "language: en_US" \
  -H "platform: Chainup" \
  -H "timezone: Asia/Shanghai" \
  "${CONSOLE_DOMAIN}/api/mpc/wallets/asset?type=0" 2>/dev/null || echo "{}")

if ! printf '%s' "$RESPONSE" | grep -q 'wallet_list\|top_wallet'; then
  echo "[ERROR] Failed to fetch MPC wallet list (login timeout or network error)" >&2
  echo "[ERROR] Response: $(printf '%s' "$RESPONSE" | head -c 200)" >&2
  exit 1
fi

# ── Parse and display candidates ─────────────────────────────────────────────
CANDIDATES=$(WALLET_JSON="$RESPONSE" python3 - <<'PY'
import json, os, sys

raw = os.environ.get("WALLET_JSON", "{}")
try:
    data = json.loads(raw)
except Exception as e:
    print(f"[ERROR] JSON parse failed: {e}", file=sys.stderr)
    sys.exit(1)

payload = data.get("data") if isinstance(data.get("data"), dict) else data
wallet_list = payload.get("wallet_list") or []
top_wallet  = payload.get("top_wallet")  or []

def parse_id(item):
    v = item.get("wallet_id")
    return str(v) if v is not None else ""

def parse_name(item):
    return item.get("wallet_name") or item.get("original_name") or "<Unnamed>"

def is_expired(item):
    # whether_expire: true = expired (confirmed from live API 2026-04-30)
    return bool(item.get("whether_expire", False))

def expire_display(item):
    return item.get("expire_time") or ""

rows = []
seen = set()
# top_wallet first (pinned wallets), then wallet_list
for source, arr in (("top", top_wallet), ("list", wallet_list)):
    for item in arr:
        if not isinstance(item, dict):
            continue
        wid = parse_id(item)
        if not wid or wid in seen:
            continue
        seen.add(wid)
        rows.append({
            "id":          wid,
            "name":        parse_name(item),
            "expired":     is_expired(item),
            "source":      source,
            "expire_time": expire_display(item),
        })

unexpired = [r for r in rows if not r["expired"]]
active = unexpired if unexpired else rows

if not active:
    print("[ERROR] No wallets found in response", file=sys.stderr)
    sys.exit(1)

for idx, row in enumerate(active, 1):
    print(f"{idx}|{row['id']}|{row['name']}|{row['source']}|{row['expire_time']}")
PY
)

if [[ -z "$CANDIDATES" ]]; then
  echo "[ERROR] Wallet list is empty or unparsable" >&2
  exit 1
fi

# ── Interactive selection ─────────────────────────────────────────────────────
echo "" >&2
echo "Available non-expired MPC workstations:" >&2
echo "$CANDIDATES" | while IFS='|' read -r idx wid name source expire; do
  printf '  [%s] %-32s  id=%-8s  source=%-5s  expire=%s\n' \
    "$idx" "$name" "$wid" "$source" "$expire" >&2
done
echo "" >&2

read -p "Select workstation by index: " SELECTED_INDEX <&2 || {
  echo "[ERROR] Interactive input unavailable (non-TTY). Pass --workstation-id directly." >&2
  exit 1
}

SELECTED_LINE=$(printf '%s\n' "$CANDIDATES" | awk -F'|' -v i="$SELECTED_INDEX" '$1==i{print; exit}')
if [[ -z "$SELECTED_LINE" ]]; then
  echo "[ERROR] Invalid selection: $SELECTED_INDEX" >&2
  exit 1
fi

SEL_ID=$(printf '%s\n'     "$SELECTED_LINE" | awk -F'|' '{print $2}')
SEL_NAME=$(printf '%s\n'   "$SELECTED_LINE" | awk -F'|' '{print $3}')
SEL_EXPIRE=$(printf '%s\n' "$SELECTED_LINE" | awk -F'|' '{print $5}')

# ── Output ───────────────────────────────────────────────────────────────────
echo "WORKSTATION_ID=${SEL_ID}"
echo "WORKSTATION_NAME=${SEL_NAME}"
echo "WORKSTATION_EXPIRE=${SEL_EXPIRE}"
