#!/usr/bin/env bash
set -euo pipefail

# Custody Co-Signer One-Click Deployment - Integrated Flow
#
# This script orchestrates the complete deployment:
#   1. Accept COINXMAN-SSO cookie (provided by agent via --cookie)
#   2. Use authenticated Console API requests to fetch or create deployment config
#   3. Deploy co-signer with safe password handling
#   4. Generate encrypted secret bundle
#
# Usage:
#   ./deploy_custody_cosigner.sh \
#     --ssh-cmd "ssh -l root -p 22 <SERVER_IP>" \
#     --cookie "<COINXMAN_SSO_VALUE>" \
#     [--workstation-id <WORKSTATION_ID>] \
#     [--remote-workdir /data/co-signer]
#
# The cookie is obtained by the agent using VS Code browser tools (Playwright)
# before calling this script. This script does NOT do browser automation.
#
# Environment:
#   SSH_CMD                  SSH command to target server (required)
#   WORKSTATION_ID          Workstation ID in Console (optional, will be prompted)
#   COSIGNER_VERSION        Co-signer version (optional, auto-detected)
#   INSTALL_TYPE            1=standard, 2=SGX (optional, auto-detected)
#   REMOTE_WORKDIR          Remote deployment directory (default: /data/co-signer)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_SCRIPT="${SCRIPT_DIR}/deploy_remote_install.sh"
BUNDLE_SCRIPT="${SCRIPT_DIR}/generate_secret_bundle.sh"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
  echo -e "${BLUE}[INFO]${NC} $*" >&2
}

log_success() {
  echo -e "${GREEN}[OK]${NC} $*" >&2
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $*" >&2
}

require_command_or_die() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    log_error "Missing required command: $cmd"
    exit 1
  fi
}

require_file_or_die() {
  local f="$1"
  if [[ ! -f "$f" ]]; then
    log_error "Missing required file: $f"
    exit 1
  fi
}

preflight_checks_or_die() {
  log_info "Running preflight checks..."
  require_command_or_die bash
  require_command_or_die curl
  require_command_or_die python3
  require_command_or_die openssl
  require_file_or_die "$DEPLOY_SCRIPT"
  require_file_or_die "$BUNDLE_SCRIPT"
  require_file_or_die "${SCRIPT_DIR}/console_api_ops.py"
  require_file_or_die "${SCRIPT_DIR}/cosigner_remote_ops.py"

  if ! eval "${SSH_CMD} 'echo SSH_OK'" >/dev/null 2>&1; then
    log_error "SSH connectivity check failed. Verify --ssh-cmd target and network."
    exit 1
  fi
  log_success "Preflight checks passed."
}

generate_password() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | cut -c1-24
  else
    LC_ALL=C dd if=/dev/urandom bs=64 count=1 2>/dev/null | tr -dc 'A-Za-z0-9' | cut -c1-24
  fi
}

generate_placeholder_app_id() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 16
  else
    python3 - <<'PY'
import secrets
print(secrets.token_hex(16))
PY
  fi
}

generate_placeholder_rsa() {
  local tmp_dir private_key public_key
  tmp_dir=$(mktemp -d)
  private_key="${tmp_dir}/placeholder_rsa.pem"
  public_key="${tmp_dir}/placeholder_rsa.pub"
  openssl genrsa -out "$private_key" 2048 >/dev/null 2>&1
  openssl rsa -in "$private_key" -pubout -out "$public_key" >/dev/null 2>&1
  sed -e '/BEGIN PUBLIC KEY/d' -e '/END PUBLIC KEY/d' -e ':a;N;$!ba;s/[[:space:]]//g' "$public_key"
  rm -rf "$tmp_dir"
}

extract_json_field() {
  local json_input="$1"
  local field_name="$2"
  JSON_INPUT="$json_input" python3 - "$field_name" <<'PY'
import json
import os
import sys

field = sys.argv[1]
raw = os.environ.get("JSON_INPUT", "{}")
try:
    data = json.loads(raw)
except Exception:
    print("")
    raise SystemExit(0)

candidates = [data]
for key in ("data", "result", "obj"):
    value = data.get(key)
    if isinstance(value, dict):
        candidates.append(value)

for candidate in candidates:
    value = candidate.get(field)
    if value not in (None, ""):
        print(value)
        break
else:
    print("")
PY
}

fetch_api_detail() {
  local api_url response
  api_url="https://custody.chainup.com/api/mpc/api/detail?wallet_id=${WORKSTATION_ID}"
  response=$(curl -s -H "Cookie: COINXMAN-SSO=${COINXMAN_SSO}" \
    -H "build-cu: web" \
    -H "language: en_US" \
    -H "platform: Keysecure" \
    -H "timezone: Asia/Shanghai" \
    "$api_url" 2>/dev/null || echo "{}")

  DETAIL_RESPONSE="$response"
  DETAIL_CODE=$(extract_json_field "$response" "code")
  APP_ID=$(extract_json_field "$response" "app_id")
  SYSTEM_RSA=$(extract_json_field "$response" "system_rsa")
  BELIEVE_IPS=$(extract_json_field "$response" "believe_ips")
  DETAIL_CO_SIGNER_RSA=$(extract_json_field "$response" "co_signer_rsa")
  DETAIL_CO_SIGNER_URL=$(extract_json_field "$response" "co_signer_url")
}

select_workstation_id_after_cookie() {
  if [[ -n "${WORKSTATION_ID:-}" ]]; then
    return 0
  fi

  local subagent_script="${SCRIPT_DIR}/../subagents/select-workstation/orchestrator_select_workstation.sh"
  if [[ ! -f "$subagent_script" ]]; then
    log_warn "select-workstation subagent not found, fallback to manual input"
    read -p "Enter Workstation ID (wallet_id from Console): " WORKSTATION_ID
    [[ -n "$WORKSTATION_ID" ]] || { log_error "Workstation ID cannot be empty"; exit 1; }
    return 0
  fi

  local subagent_output
  subagent_output=$(bash "$subagent_script" --cookie "COINXMAN-SSO=${COINXMAN_SSO}" 2>/dev/tty) || {
    log_warn "Workstation selection failed, fallback to manual input"
    read -p "Enter Workstation ID (wallet_id from Console): " WORKSTATION_ID
    [[ -n "$WORKSTATION_ID" ]] || { log_error "Workstation ID cannot be empty"; exit 1; }
    return 0
  }

  WORKSTATION_ID=$(printf '%s\n' "$subagent_output" | grep '^WORKSTATION_ID=' | cut -d= -f2)
  if [[ -z "$WORKSTATION_ID" ]]; then
    log_error "Workstation selection returned no ID"
    exit 1
  fi
}

extract_cosigner_rsa_from_show_output() {
  local show_output="$1"
  printf '%s\n' "$show_output" | awk '
    /Co-Signer RSA Public Key:/ {capture=1; next}
    capture && NF {gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print; exit}
  '
}

merge_believe_ips() {
  local existing_ips="${1:-}"
  local append_ips="${2:-}"
  EXISTING_IPS="$existing_ips" APPEND_IPS="$append_ips" python3 - <<'PY'
import os

existing = os.environ.get("EXISTING_IPS", "")
append = os.environ.get("APPEND_IPS", "")

def split_ips(value: str):
    value = value.replace(";", ",")
    parts = []
    for raw in value.split(","):
        ip = raw.strip()
        if ip:
            parts.append(ip)
    return parts

result = []
seen = set()
for ip in split_ips(existing) + split_ips(append):
    if ip not in seen:
        seen.add(ip)
        result.append(ip)

print(",".join(result))
PY
}

normalize_rsa() {
  local raw="$1"
  RAW_RSA="$raw" python3 - <<'PY'
import os
import re

s = os.environ.get("RAW_RSA", "")
s = re.sub(r"\s+", "", s)
s = s.replace("-----BEGINPUBLICKEY-----", "")
s = s.replace("-----ENDPUBLICKEY-----", "")
print(s)
PY
}

ip_in_list() {
  local ip_list="$1"
  local target_ip="$2"
  IP_LIST="$ip_list" TARGET_IP="$target_ip" python3 - <<'PY'
import os

raw = os.environ.get("IP_LIST", "")
target = os.environ.get("TARGET_IP", "")
ips = [p.strip() for p in raw.replace(";", ",").split(",") if p.strip()]
print("1" if target and target in ips else "0")
PY
}

normalize_cosigner_url() {
  local raw_url="$1"
  if [[ -z "$raw_url" ]]; then
    echo ""
    return 0
  fi
  if [[ "$raw_url" =~ ^https?:// ]]; then
    echo "$raw_url"
  else
    echo "http://${raw_url}"
  fi
}

cleanup_deployment_processes() {
  log_info "Cleaning up deployment processes on remote server..."
  local cosigner_ops="${SCRIPT_DIR}/cosigner_remote_ops.py"
  if [[ -f "$cosigner_ops" ]]; then
    python3 "$cosigner_ops" \
      --ssh-cmd "$SSH_CMD" \
      --action stop \
      --workdir "${REMOTE_WORKDIR}/mpc-co-signer" 2>&1 || true
  else
    eval "${SSH_CMD} 'pkill -x co-signer 2>/dev/null || true; sleep 1; pkill -9 -x co-signer 2>/dev/null || true'" || true
  fi
  log_info "Deployment processes cleaned up. Customer must run ./startup.sh to start the service."
}

extract_host_from_url() {
  local url="$1"
  URL_VALUE="$url" python3 - <<'PY'
import os
from urllib.parse import urlparse

url = os.environ.get("URL_VALUE", "")
if not url:
    print("")
    raise SystemExit(0)
parsed = urlparse(url)
print(parsed.hostname or "")
PY
}

verify_console_config_synced_or_die() {
  local expected_rsa="$1"
  local expected_url="$2"
  local required_ip="$3"
  local require_appid_system_rsa="${4:-0}"
  local expected_norm actual_norm ip_ok

  fetch_api_detail
  if [[ "${DETAIL_CODE:-}" != "0" ]]; then
    log_error "Console detail query failed (code=${DETAIL_CODE:-unknown})."
    log_error "Detail response: ${DETAIL_RESPONSE}"
    exit 1
  fi

  expected_norm=$(normalize_rsa "$expected_rsa")
  actual_norm=$(normalize_rsa "${DETAIL_CO_SIGNER_RSA:-}")

  if [[ -z "$expected_norm" || -z "$actual_norm" || "$expected_norm" != "$actual_norm" ]]; then
    log_error "Console co_signer_rsa is not in sync with server co-signer RSA."
    log_error "Expected(prefix): ${expected_norm:0:24}"
    log_error "Actual(prefix):   ${actual_norm:0:24}"
    exit 1
  fi

  if [[ "${DETAIL_CO_SIGNER_URL:-}" != "$expected_url" ]]; then
    log_error "Console co_signer_url mismatch. expected=${expected_url}, actual=${DETAIL_CO_SIGNER_URL:-}"
    exit 1
  fi

  ip_ok=$(ip_in_list "${BELIEVE_IPS:-}" "$required_ip")
  if [[ "$ip_ok" != "1" ]]; then
    log_error "Console believe_ips does not contain server IP ${required_ip}. actual=${BELIEVE_IPS:-}"
    exit 1
  fi

  if [[ "$require_appid_system_rsa" == "1" ]]; then
    if [[ -z "${APP_ID:-}" || -z "${SYSTEM_RSA:-}" ]]; then
      log_error "Console app_id/system_rsa not ready after save/approval."
      exit 1
    fi
  fi
}

is_console_config_in_sync() {
  local expected_rsa="$1"
  local expected_url="$2"
  local required_ip="$3"
  local expected_norm actual_norm ip_ok

  expected_norm=$(normalize_rsa "$expected_rsa")
  actual_norm=$(normalize_rsa "${DETAIL_CO_SIGNER_RSA:-}")
  ip_ok=$(ip_in_list "${BELIEVE_IPS:-}" "$required_ip")

  if [[ -n "$expected_norm" && -n "$actual_norm" && "$expected_norm" == "$actual_norm" && "${DETAIL_CO_SIGNER_URL:-}" == "$expected_url" && "$ip_ok" == "1" ]]; then
    return 0
  fi
  return 1
}

create_console_api() {
  local create_response create_url believe_ips_value developer_rsa google_code_value
  local app_id_value co_signer_url_value
  local -a post_args
  create_url="https://custody.chainup.com/api/mpc/api/save"
  believe_ips_value="${4:-${BELIEVE_IPS:-${BELIEVE_IPS_OVERRIDE:-54.254.7.206}}}"
  developer_rsa="$1"
  app_id_value="${2:-}"
  co_signer_url_value="${3:-}"

  if [[ -z "${GOOGLE_CODE:-}" ]]; then
    read -p "Enter google_code for Console API creation: " GOOGLE_CODE
  fi
  google_code_value="${GOOGLE_CODE:-}"
  if [[ -z "$google_code_value" ]]; then
    log_error "google_code is required to create Console API"
    exit 1
  fi

  post_args=(
    --data-urlencode "wallet_id=${WORKSTATION_ID}"
    --data-urlencode "believe_ips=${believe_ips_value}"
    --data-urlencode "co_signer_rsa=${developer_rsa}"
    --data-urlencode "developer_rsa=${developer_rsa}"
    --data-urlencode "google_code=${google_code_value}"
  )
  if [[ -n "$app_id_value" ]]; then
    post_args+=(--data-urlencode "app_id=${app_id_value}")
  fi
  if [[ -n "$co_signer_url_value" ]]; then
    post_args+=(--data-urlencode "co_signer_url=${co_signer_url_value}")
  fi

  create_response=$(curl -s -X POST "$create_url" \
    -H "Cookie: COINXMAN-SSO=${COINXMAN_SSO}" \
    -H "build-cu: web" \
    -H "language: en_US" \
    -H "platform: Keysecure" \
    -H "timezone: Asia/Shanghai" \
    "${post_args[@]}" 2>/dev/null || echo "{}")

  CREATE_RESPONSE="$create_response"
  SAVE_CODE=$(extract_json_field "$create_response" "code")
  SAVE_MSG=$(extract_json_field "$create_response" "msg")
  TRADE_NO=$(extract_json_field "$create_response" "trade_no")
}

submit_console_save_with_rules_or_die() {
  local developer_rsa="$1"
  local app_id_value="$2"
  local co_signer_url_value="$3"
  local believe_ips_value="$4"
  local normalized_url required_ip require_appid_system_rsa

  require_appid_system_rsa="${5:-0}"
  normalized_url=$(normalize_cosigner_url "$co_signer_url_value")
  required_ip=$(extract_host_from_url "$normalized_url")

  while true; do
    create_console_api "$developer_rsa" "$app_id_value" "$normalized_url" "$believe_ips_value"

    case "${SAVE_CODE:-}" in
      "0")
        if [[ -n "${TRADE_NO:-}" ]]; then
          log_warn "Console save accepted with trade_no=${TRADE_NO}. Approval is required in Custody APP."
          read -p "Approve in Custody APP, then press Enter to continue verification..." _
        fi
        verify_console_config_synced_or_die "$developer_rsa" "$normalized_url" "$required_ip" "$require_appid_system_rsa"
        break
        ;;
      "110188")
        log_warn "Pending approval order exists (code=110188). Do NOT resubmit."
        if [[ -n "${TRADE_NO:-}" ]]; then
          log_warn "Existing trade_no=${TRADE_NO}."
        fi
        read -p "Complete approval in Custody APP, then press Enter to continue verification..." _
        verify_console_config_synced_or_die "$developer_rsa" "$normalized_url" "$required_ip" "$require_appid_system_rsa"
        break
        ;;
      "110007")
        log_warn "Google code expired/invalid (code=110007). Please enter a new code."
        GOOGLE_CODE=""
        ;;
      "110909")
        log_error "Cookie expired/login timeout (code=110909). Re-acquire COINXMAN-SSO and rerun."
        exit 1
        ;;
      "")
        log_error "Console save returned empty code. Raw response: ${CREATE_RESPONSE}"
        exit 1
        ;;
      *)
        log_error "Console save failed (code=${SAVE_CODE}, msg=${SAVE_MSG})."
        log_error "Raw response: ${CREATE_RESPONSE}"
        exit 1
        ;;
    esac
  done
}

update_remote_app_id_or_die() {
  local real_app_id="$1"
  APP_ID_VALUE="$real_app_id" \
  REMOTE_WORKDIR_VALUE="$REMOTE_WORKDIR" \
  SSH_CMD_VALUE="$SSH_CMD" \
  python3 - <<'PY'
import os
import subprocess
import sys

app_id = os.environ["APP_ID_VALUE"]
remote_workdir = os.environ["REMOTE_WORKDIR_VALUE"]
ssh_cmd = os.environ["SSH_CMD_VALUE"]

remote_script = f"""set -euo pipefail
cd {remote_workdir}/mpc-co-signer
python3 - <<'INNER'
from pathlib import Path
path = Path('conf/config.yaml')
text = path.read_text()
updated = []
replaced = False
for line in text.splitlines():
    if line.lstrip().startswith('app_id:'):
        prefix = line.split('app_id:')[0]
        updated.append(f"{{prefix}}app_id: \"{app_id}\"")
        replaced = True
    else:
        updated.append(line)
if not replaced:
    raise SystemExit('app_id line not found in conf/config.yaml')
path.write_text('\\n'.join(updated) + '\\n')
INNER
"""

command = f"{ssh_cmd} 'bash -s' <<'EOF'\n{remote_script}\nEOF"
result = subprocess.run(command, shell=True, text=True, capture_output=True)
sys.stdout.write(result.stdout)
sys.stderr.write(result.stderr)
sys.exit(result.returncode)
PY
}

import_custody_pub_or_die() {
  local real_system_rsa="$1"
  local cosigner_password="$2"

  if ! printf '%s\n' "$cosigner_password" | python3 "${SCRIPT_DIR}/cosigner_remote_ops.py" \
    --ssh-cmd "$SSH_CMD" \
    --action import-custody-pub \
    --password-stdin \
    --workdir "${REMOTE_WORKDIR}/mpc-co-signer" \
    --pub-key "$real_system_rsa" >/dev/null; then
    log_error "Failed to import real custody public key to co-signer keystore."
    exit 1
  fi
}

verify_phase3_network_or_die() {
  local cosigner_password="$1"
  local wallet_id="$2"
  local inbound_resp

  log_info "Phase 3 gate: starting co-signer for connectivity checks..."
  if ! printf '%s\n' "$cosigner_password" | python3 "${SCRIPT_DIR}/cosigner_remote_ops.py" \
    --ssh-cmd "$SSH_CMD" \
    --action start \
    --password-stdin \
    --workdir "${REMOTE_WORKDIR}/mpc-co-signer" \
    --port "${ACTUAL_COSIGNER_PORT}" >/dev/null; then
    log_error "Failed to start co-signer for Phase 3 network verification."
    exit 1
  fi

  log_info "Phase 3 gate: verifying outbound connectivity (co-signer -> openapi)..."
  if ! eval "${SSH_CMD} 'curl -s --connect-timeout 10 https://openapi.chainup.com/api/ping'" | grep -Eq '"code"|"msg"'; then
    log_error "Outbound connectivity check failed."
    exit 1
  fi

  log_info "Phase 3 gate: verifying inbound ping (Custody -> co-signer)..."
  inbound_resp=$(curl -s -H "Cookie: COINXMAN-SSO=${COINXMAN_SSO}" \
    -H "build-cu: web" \
    -H "language: en_US" \
    -H "platform: Keysecure" \
    -H "timezone: Asia/Shanghai" \
    "https://custody.chainup.com/api/mpc/api/cosigner/ping?wallet_id=${wallet_id}" 2>/dev/null || true)
  if ! printf '%s' "$inbound_resp" | grep -q '"code"[[:space:]]*:[[:space:]]*"0"'; then
    log_error "Inbound ping verification failed. Response: ${inbound_resp}"
    log_error "Required firewall inbound: 54.254.7.206 -> ${ACTUAL_COSIGNER_PORT}, outbound: 54.251.87.91:443"
    exit 1
  fi
}

# Parse arguments
SSH_CMD="${SSH_CMD:-}"
WORKSTATION_ID="${WORKSTATION_ID:-}"
REMOTE_WORKDIR="${REMOTE_WORKDIR:-/data/co-signer}"
COINXMAN_SSO="${COINXMAN_SSO:-}"
COSIGNER_VERSION="${COSIGNER_VERSION:-}"
INSTALL_TYPE="${INSTALL_TYPE:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ssh-cmd)
      SSH_CMD="$2"
      shift 2
      ;;
    --cookie)
      COINXMAN_SSO="$2"
      shift 2
      ;;
    --workstation-id)
      WORKSTATION_ID="$2"
      shift 2
      ;;
    --remote-workdir)
      REMOTE_WORKDIR="$2"
      shift 2
      ;;
    --help|-h)
      echo "Custody Co-Signer One-Click Deployment"
      echo ""
      echo "Usage: $0 --ssh-cmd 'ssh -l root ...' --cookie '<COINXMAN_SSO>' [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --ssh-cmd CMD           SSH command to target server (required)"
      echo "  --cookie VALUE          COINXMAN-SSO cookie value (required)"
      echo "  --workstation-id ID     Workstation ID in Console (optional)"
      echo "  --remote-workdir PATH   Remote deployment directory (default: /data/co-signer)"
      echo "  --help                  Show this help message"
      exit 0
      ;;
    *)
      log_error "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Validate required inputs
if [[ -z "$SSH_CMD" ]]; then
  log_error "SSH_CMD is required (use --ssh-cmd)"
  exit 1
fi

if [[ -z "$COINXMAN_SSO" ]]; then
  log_error "Cookie is required (use --cookie '<COINXMAN_SSO_VALUE>')"
  exit 1
fi

preflight_checks_or_die

# Step 1: Cookie validation
log_info "Step 1/4: Validating authentication cookie..."
log_info "Cookie obtained (first 16 chars): ${COINXMAN_SSO:0:16}..."
log_info "All remaining Console operations use API requests only."

# Step 2: Get Workstation ID if not provided
log_info "Step 2/4: Resolving workstation selection..."
select_workstation_id_after_cookie

log_info "Workstation ID: $WORKSTATION_ID"

# Step 3: Fetch Console API configuration
log_info "Step 3/4: Fetching deployment configuration from Console..."

fetch_api_detail

BOOTSTRAP_MODE=false
BOOTSTRAP_APP_ID=""
BOOTSTRAP_SYSTEM_RSA=""
if [[ -z "$APP_ID" ]]; then
  BOOTSTRAP_MODE=true
  BOOTSTRAP_APP_ID=$(generate_placeholder_app_id)
  if [[ -n "$SYSTEM_RSA" ]]; then
    BOOTSTRAP_SYSTEM_RSA="$SYSTEM_RSA"
  else
    BOOTSTRAP_SYSTEM_RSA=$(generate_placeholder_rsa)
  fi
  log_warn "Console API not initialized yet; using placeholder app_id and custody RSA to bootstrap co-signer RSA generation"
else
  if [[ -z "$SYSTEM_RSA" ]]; then
    log_error "Failed to retrieve system_rsa from Console. Check cookie and workstation ID."
    exit 1
  fi
  log_success "Configuration loaded: APP_ID=${APP_ID:0:16}..."
fi

# Step 4: Execute deployment
log_info "Step 4/4: Deploying co-signer to remote server..."

COSIGNER_PASSWORD=$(generate_password)
export SSH_CMD
export COSIGNER_PASSWORD
if [[ "$BOOTSTRAP_MODE" == "true" ]]; then
  export APP_ID="$BOOTSTRAP_APP_ID"
  export CHAINUP_PUBLIC_KEY="$BOOTSTRAP_SYSTEM_RSA"
else
  export APP_ID
  export CHAINUP_PUBLIC_KEY="$SYSTEM_RSA"
fi
export REMOTE_WORKDIR
if [[ -n "$COSIGNER_VERSION" ]]; then
  export COSIGNER_VERSION
fi
if [[ -n "$INSTALL_TYPE" ]]; then
  export INSTALL_TYPE
fi

DEPLOY_OUTPUT=$(bash "$DEPLOY_SCRIPT" 2>&1) || {
  log_error "Deployment failed. Check logs above for details."
  printf '%s\n' "$DEPLOY_OUTPUT"
  exit 1
}

printf '%s\n' "$DEPLOY_OUTPUT"

SHOW_RSA_OUTPUT_B64=$(printf '%s\n' "$DEPLOY_OUTPUT" | awk -F= '/^SHOW_RSA_OUTPUT_B64=/{print $2; exit}')
if [[ -z "$SHOW_RSA_OUTPUT_B64" ]]; then
  log_error "Failed to capture co-signer RSA output from deployment"
  exit 1
fi

SHOW_RSA_OUTPUT=$(printf '%s' "$SHOW_RSA_OUTPUT_B64" | base64 -d)
COSIGNER_RSA=$(extract_cosigner_rsa_from_show_output "$SHOW_RSA_OUTPUT")
if [[ -z "$COSIGNER_RSA" ]]; then
  log_error "Failed to parse Co-Signer RSA Public Key from show-rsa output"
  exit 1
fi

DERIVED_COSIGNER_URL=$(printf '%s\n' "$DEPLOY_OUTPUT" | awk -F= '/^DERIVED_COSIGNER_URL=/{print $2; exit}')
DERIVED_COSIGNER_URL=$(normalize_cosigner_url "$DERIVED_COSIGNER_URL")
if [[ -z "$DERIVED_COSIGNER_URL" ]]; then
  log_error "Missing DERIVED_COSIGNER_URL in deployment output."
  exit 1
fi
ACTUAL_COSIGNER_PORT=$(printf '%s\n' "$DEPLOY_OUTPUT" | awk -F= '/^ACTUAL_COSIGNER_PORT=/{print $2; exit}')
if [[ -z "${ACTUAL_COSIGNER_PORT:-}" || ! "${ACTUAL_COSIGNER_PORT}" =~ ^[0-9]+$ ]]; then
  ACTUAL_COSIGNER_PORT="28888"
fi
DERIVED_SERVER_IP=$(extract_host_from_url "$DERIVED_COSIGNER_URL")
if [[ -z "$DERIVED_SERVER_IP" ]]; then
  log_error "Cannot derive server IP from DERIVED_COSIGNER_URL=${DERIVED_COSIGNER_URL}"
  exit 1
fi
if [[ "$BOOTSTRAP_MODE" == "true" ]]; then
  BELIEVE_IPS_VALUE=$(merge_believe_ips "${BELIEVE_IPS:-}" "${BELIEVE_IPS_OVERRIDE:-54.254.7.206}")
else
  # Existing API must append new IPs, not overwrite existing whitelist.
  BELIEVE_IPS_VALUE=$(merge_believe_ips "${BELIEVE_IPS:-}" "${BELIEVE_IPS_OVERRIDE:-}")
fi
if [[ -z "$BELIEVE_IPS_VALUE" ]]; then
  BELIEVE_IPS_VALUE="54.254.7.206"
fi

if [[ "$BOOTSTRAP_MODE" == "true" ]]; then
  log_info "Creating Console API with generated co-signer RSA..."
  submit_console_save_with_rules_or_die "$COSIGNER_RSA" "" "$DERIVED_COSIGNER_URL" "$BELIEVE_IPS_VALUE" "1"

  log_info "Updating remote config.yaml and custody public key with real APP_ID/system_rsa..."
  update_remote_app_id_or_die "$APP_ID"
  import_custody_pub_or_die "$SYSTEM_RSA" "$COSIGNER_PASSWORD"
else
  if is_console_config_in_sync "$COSIGNER_RSA" "$DERIVED_COSIGNER_URL" "$DERIVED_SERVER_IP"; then
    log_success "API config already in sync; skipping save/update."
  else
    log_info "Updating existing Console API with latest co-signer RSA/URL/whitelist..."
    submit_console_save_with_rules_or_die "$COSIGNER_RSA" "$APP_ID" "$DERIVED_COSIGNER_URL" "$BELIEVE_IPS_VALUE" "0"
  fi
fi

verify_phase3_network_or_die "$COSIGNER_PASSWORD" "$WORKSTATION_ID"

# Phase cleanup: stop all co-signer processes started during deployment
cleanup_deployment_processes

log_success "Deployment completed successfully!"
echo ""

# ============================================================================
# ⚠️  SECURITY OUTPUT — Co-Signer Initial Password (plaintext, shown once)
# ============================================================================
echo ""
echo -e "\033[1;33m╔══════════════════════════════════════════════════════════════════╗\033[0m"
echo -e "\033[1;33m║        ⚠️  CO-SIGNER INITIAL PASSWORD — SAVE THIS NOW           ║\033[0m"
echo -e "\033[1;33m╠══════════════════════════════════════════════════════════════════╣\033[0m"
echo -e "\033[1;37m║  Password: \033[1;32m${COSIGNER_PASSWORD}\033[1;37m\033[0m"
echo -e "\033[1;33m╚══════════════════════════════════════════════════════════════════╝\033[0m"
echo ""
echo -e "\033[1;31m[SECURITY — REQUIRED ACTIONS]\033[0m"
echo -e "\033[1;31m  ⚠️  此密码仅在本次部署时展示，不会写入任何文件或命令行参数。\033[0m"
echo -e "\033[1;31m  ⚠️  This password is shown ONCE and never stored to disk or argv.\033[0m"
echo ""
echo -e "\033[0;33m  1. 登录服务器，确认密码可用后立即修改：\033[0m"
echo -e "\033[0;37m       cd ${REMOTE_WORKDIR}/mpc-co-signer\033[0m"
echo -e "\033[0;37m       ./co-signer -password-update\033[0m"
echo ""
echo -e "\033[0;33m  2. 修改完成后，删除 agent 的 SSH 登录权限：\033[0m"
echo -e "\033[0;37m       vi ~/.ssh/authorized_keys   # 删除 agent 公钥行\033[0m"
echo ""
echo -e "\033[0;33m  3. 去 ChainUp Custody App 刷新私钥到 co-signer：\033[0m"
echo -e "\033[0;37m       App → MPC 工作站 → 选择工作站 → 刷新私钥\033[0m"
echo ""
if [[ -n "${TRADE_NO:-}" ]]; then
  echo -e "\033[0;36m  4. Console API 返回了 trade_no=${TRADE_NO}，需在审批流中完成审批后方可生效。\033[0m"
  echo ""
fi
echo -e "\033[1;31m══════════════════════════════════════════════════════════════════\033[0m"
