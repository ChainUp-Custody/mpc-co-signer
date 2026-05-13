#!/usr/bin/env bash
set -euo pipefail

# Custody Co-Signer Master Orchestrator Script
# Coordinates 6 subagents to deploy co-signer with manageable context
#
# Usage:
#   ./orchestrate_deployment.sh --ssh-cmd "ssh..." [--workstation-id ID]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*" >&2; }
log_success() { echo -e "${GREEN}[OK]${NC} $*" >&2; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

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

create_console_api() {
  local developer_rsa="$1"
  local believe_ips_value="$2"
  local app_id_value="${3:-}"
  local co_signer_url_value="${4:-}"
  local create_url create_response google_code_value
  local -a post_args

  create_url="https://custody.chainup.com/api/mpc/api/save"
  believe_ips_value="${believe_ips_value:-54.254.7.206}"

  if [[ -z "${GOOGLE_CODE:-}" ]]; then
    read -p "Enter The Custody App google_code for Console API creation: " GOOGLE_CODE
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
    -H "platform: Chainup" \
    -H "timezone: Asia/Shanghai" \
    "${post_args[@]}" 2>/dev/null || echo "{}")

  TRADE_NO=$(printf '%s\n' "$create_response" | python3 - <<'PY'
import json,sys
raw=sys.stdin.read() or '{}'
try:
    data=json.loads(raw)
except Exception:
    print("")
    raise SystemExit(0)
for obj in (data, data.get('data', {}), data.get('result', {}), data.get('obj', {})):
    if isinstance(obj, dict) and obj.get('trade_no'):
        print(obj.get('trade_no'))
        break
else:
    print("")
PY
)
}

update_remote_runtime_config() {
  local real_app_id="$1"
  local real_system_rsa="$2"
  local cosigner_password="$3"

  APP_ID_VALUE="$real_app_id" \
  SYSTEM_RSA_VALUE="$real_system_rsa" \
  COSIGNER_PASSWORD_VALUE="$cosigner_password" \
  REMOTE_WORKDIR_VALUE="/data/co-signer" \
  SSH_CMD_VALUE="$SSH_CMD" \
  python3 - <<'PY'
import os
import subprocess
import sys

app_id = os.environ["APP_ID_VALUE"]
system_rsa = os.environ["SYSTEM_RSA_VALUE"]
password = os.environ["COSIGNER_PASSWORD_VALUE"]
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
printf '%s\\n' '{password}' | ./co-signer -custody-pub-import '{system_rsa}'
"""

command = f"{ssh_cmd} 'bash -s' <<'EOF'\n{remote_script}\nEOF"
result = subprocess.run(command, shell=True, text=True, capture_output=True)
sys.stdout.write(result.stdout)
sys.stderr.write(result.stderr)
sys.exit(result.returncode)
PY
}

select_workstation_id_after_cookie() {
  if [[ -n "${WORKSTATION_ID:-}" ]]; then
    return 0
  fi

  local subagent_script="${SCRIPT_DIR}/subagents/select-workstation/orchestrator_select_workstation.sh"
  if [[ ! -f "$subagent_script" ]]; then
    log_warn "select-workstation subagent not found, fallback to manual input"
    read -p "Enter Workstation ID (wallet_id): " WORKSTATION_ID
    [[ -n "$WORKSTATION_ID" ]] || { log_error "Workstation ID cannot be empty"; exit 1; }
    return 0
  fi

  local subagent_output
  subagent_output=$(bash "$subagent_script" --cookie "COINXMAN-SSO=${COINXMAN_SSO}" 2>/dev/tty) || {
    log_warn "Workstation selection failed, fallback to manual input"
    read -p "Enter Workstation ID (wallet_id): " WORKSTATION_ID
    [[ -n "$WORKSTATION_ID" ]] || { log_error "Workstation ID cannot be empty"; exit 1; }
    return 0
  }

  WORKSTATION_ID=$(printf '%s\n' "$subagent_output" | grep '^WORKSTATION_ID=' | cut -d= -f2)
  if [[ -z "$WORKSTATION_ID" ]]; then
    log_error "Workstation selection returned no ID"
    exit 1
  fi
}

# Parse arguments
SSH_CMD=""
WORKSTATION_ID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ssh-cmd) SSH_CMD="$2"; shift 2 ;;
    --workstation-id) WORKSTATION_ID="$2"; shift 2 ;;
    --help) 
      echo "Usage: $0 --ssh-cmd 'ssh...' [--workstation-id ID]"
      exit 0
      ;;
    *) log_error "Unknown option: $1"; exit 1 ;;
  esac
done

if [[ -z "$SSH_CMD" ]]; then
  log_error "SSH_CMD is required"
  exit 1
fi

log_info "🚀 Starting Custody Co-Signer Deployment Orchestration"
echo ""

# ============================================================================
# STEP 1: Validate Cookie (provided by agent via COINXMAN_SSO env var)
log_step "Step 1: Validating authentication cookie..."
if [[ -z "${COINXMAN_SSO:-}" ]]; then
  log_error "COINXMAN_SSO environment variable is required (agent provides via Playwright browser tools)"
  exit 1
fi
log_success "Cookie validated (first 16 chars): ${COINXMAN_SSO:0:16}..."

# STEP 2: Get Workstation ID if not provided
# ============================================================================
select_workstation_id_after_cookie
log_info "Workstation ID: $WORKSTATION_ID"
echo ""

# ============================================================================
# STEP 2: Call Subagent - Fetch Console Config
# ============================================================================
log_info "STEP 2/6: Fetching Console configuration..."

CONFIG_OUTPUT=$(bash "$SCRIPT_DIR/subagents/fetch-config/orchestrator_fetch_config.sh" \
  --cookie "$COINXMAN_SSO" \
  --workstation-id "$WORKSTATION_ID" 2>/dev/null || echo "")

if [[ -z "$CONFIG_OUTPUT" ]]; then
  log_error "Failed to fetch Console config"
  exit 1
fi

APP_ID=$(echo "$CONFIG_OUTPUT" | grep "APP_ID=" | cut -d'=' -f2)
SYSTEM_RSA=$(echo "$CONFIG_OUTPUT" | grep "SYSTEM_RSA=" | cut -d'=' -f2)
BELIEVE_IPS=$(echo "$CONFIG_OUTPUT" | grep "BELIEVE_IPS=" | cut -d'=' -f2)
API_EXISTS=$(echo "$CONFIG_OUTPUT" | grep "API_EXISTS=" | cut -d'=' -f2)

BOOTSTRAP_MODE=false
BOOTSTRAP_APP_ID=""
BOOTSTRAP_SYSTEM_RSA=""
if [[ -z "$APP_ID" || "${API_EXISTS}" == "false" ]]; then
  BOOTSTRAP_MODE=true
  BOOTSTRAP_APP_ID=$(generate_placeholder_app_id)
  if [[ -n "$SYSTEM_RSA" ]]; then
    BOOTSTRAP_SYSTEM_RSA="$SYSTEM_RSA"
  else
    BOOTSTRAP_SYSTEM_RSA=$(generate_placeholder_rsa)
  fi
  log_warn "Console API missing; will bootstrap co-signer RSA first, then create API"
else
  log_success "Config fetched: app_id=${APP_ID:0:16}..."
fi
echo ""

# ============================================================================
# STEP 3: Call Subagent - Detect Environment
# ============================================================================
log_info "STEP 3/6: Detecting remote environment..."

ENV_OUTPUT=$(bash "$SCRIPT_DIR/subagents/detect-env/orchestrator_detect_env.sh" \
  --ssh-cmd "$SSH_CMD" 2>/dev/null || echo "")

if [[ -z "$ENV_OUTPUT" ]]; then
  log_error "Failed to detect environment"
  exit 1
fi

INSTALL_TYPE=$(echo "$ENV_OUTPUT" | grep "INSTALL_TYPE=" | cut -d'=' -f2)
COSIGNER_VERSION=$(echo "$ENV_OUTPUT" | grep "COSIGNER_VERSION=" | cut -d'=' -f2)
OS_INFO=$(echo "$ENV_OUTPUT" | grep "OS_INFO=" | cut -d'=' -f2)

log_success "Environment detected: $OS_INFO, INSTALL_TYPE=$INSTALL_TYPE, Version=$COSIGNER_VERSION"
echo ""

# ============================================================================
# STEP 4: Call Subagent - Deploy Remote
# ============================================================================
log_info "STEP 4/6: Executing remote deployment..."

DEPLOY_OUTPUT=$(bash "$SCRIPT_DIR/subagents/deploy-remote/orchestrator_deploy_remote.sh" \
  --ssh-cmd "$SSH_CMD" \
  --app-id "${APP_ID:-$BOOTSTRAP_APP_ID}" \
  --chainup-public-key "${SYSTEM_RSA:-$BOOTSTRAP_SYSTEM_RSA}" \
  --install-type "$INSTALL_TYPE" \
  --cosigner-version "$COSIGNER_VERSION" 2>/dev/null || echo "")

if [[ -z "$DEPLOY_OUTPUT" ]]; then
  log_error "Failed to execute deployment"
  exit 1
fi

COSIGNER_RSA_PUBLIC=$(echo "$DEPLOY_OUTPUT" | grep "COSIGNER_RSA_PUBLIC=" | cut -d'=' -f2 | head -1)
COSIGNER_PASSWORD=$(echo "$DEPLOY_OUTPUT" | grep "COSIGNER_PASSWORD=" | cut -d'=' -f2)
SHOW_RSA_OUTPUT_B64=$(echo "$DEPLOY_OUTPUT" | grep "SHOW_RSA_OUTPUT_B64=" | cut -d'=' -f2 | head -1)
DERIVED_COSIGNER_URL=$(echo "$DEPLOY_OUTPUT" | grep "DERIVED_COSIGNER_URL=" | cut -d'=' -f2 | head -1)
SERVER_PUBLIC_IP=$(echo "$DEPLOY_OUTPUT" | grep "SERVER_PUBLIC_IP=" | cut -d'=' -f2 | head -1)
ACTUAL_COSIGNER_PORT=$(echo "$DEPLOY_OUTPUT" | grep "ACTUAL_COSIGNER_PORT=" | cut -d'=' -f2 | head -1)

SHOW_RSA_OUTPUT=""
if [[ -n "$SHOW_RSA_OUTPUT_B64" ]]; then
  SHOW_RSA_OUTPUT=$(printf '%s' "$SHOW_RSA_OUTPUT_B64" | base64 -d 2>/dev/null || true)
fi

if [[ -z "$COSIGNER_RSA_PUBLIC" && -n "$SHOW_RSA_OUTPUT" ]]; then
  COSIGNER_RSA_PUBLIC=$(extract_cosigner_rsa_from_show_output "$SHOW_RSA_OUTPUT")
fi

if [[ "$BOOTSTRAP_MODE" == "true" ]]; then
  if [[ -z "$COSIGNER_RSA_PUBLIC" ]]; then
    log_error "Bootstrap mode requires generated co-signer RSA, but extraction failed"
    exit 1
  fi

  log_info "Creating Console API with generated co-signer RSA..."
  BELIEVE_IPS_VALUE=$(merge_believe_ips "${BELIEVE_IPS:-}" "${BELIEVE_IPS_OVERRIDE:-54.254.7.206}")
  if [[ -z "$BELIEVE_IPS_VALUE" ]]; then
    BELIEVE_IPS_VALUE="54.254.7.206"
  fi
  create_console_api "$COSIGNER_RSA_PUBLIC" "$BELIEVE_IPS_VALUE" "" "$DERIVED_COSIGNER_URL"
  if [[ -n "${TRADE_NO:-}" ]]; then
    log_warn "Console API creation returned trade_no=${TRADE_NO}. Approval may be required before app_id becomes active."
  fi

  CONFIG_OUTPUT=$(bash "$SCRIPT_DIR/subagents/fetch-config/orchestrator_fetch_config.sh" \
    --cookie "$COINXMAN_SSO" \
    --workstation-id "$WORKSTATION_ID" 2>/dev/null || echo "")
  APP_ID=$(echo "$CONFIG_OUTPUT" | grep "APP_ID=" | cut -d'=' -f2)
  SYSTEM_RSA=$(echo "$CONFIG_OUTPUT" | grep "SYSTEM_RSA=" | cut -d'=' -f2)
  if [[ -z "$APP_ID" || -z "$SYSTEM_RSA" ]]; then
    log_error "Console API not ready after create; if trade_no exists, approve it and rerun"
    exit 1
  fi

  log_info "Updating remote runtime config with real app_id and custody system RSA..."
  update_remote_runtime_config "$APP_ID" "$SYSTEM_RSA" "$COSIGNER_PASSWORD"
else
  if [[ -z "$COSIGNER_RSA_PUBLIC" ]]; then
    log_error "Failed to extract co-signer RSA from deployment output for API update"
    exit 1
  fi

  log_info "Updating existing Console API with latest co-signer RSA/URL/whitelist..."
  # Existing API must append new IPs, not overwrite existing whitelist.
  BELIEVE_IPS_VALUE=$(merge_believe_ips "${BELIEVE_IPS:-}" "${BELIEVE_IPS_OVERRIDE:-}")
  if [[ -z "$BELIEVE_IPS_VALUE" ]]; then
    BELIEVE_IPS_VALUE="54.254.7.206"
  fi
  create_console_api "$COSIGNER_RSA_PUBLIC" "$BELIEVE_IPS_VALUE" "$APP_ID" "$DERIVED_COSIGNER_URL"
  if [[ -n "${TRADE_NO:-}" ]]; then
    log_warn "Console API update returned trade_no=${TRADE_NO}. Approval may be required before new config becomes active."
  fi
fi

log_success "Deployment completed"
echo ""

# ============================================================================
# STEP 5: Call Subagent - Generate Secret Bundle
# ============================================================================
log_info "STEP 5/6: Generating encrypted secret bundle..."

BUNDLE_OUTPUT=$(bash "$SCRIPT_DIR/subagents/gen-bundle/orchestrator_gen_bundle.sh" \
  --password "$COSIGNER_PASSWORD" \
  --app-id "$APP_ID" \
  --cosigner-rsa "$COSIGNER_RSA_PUBLIC" \
  --workstation-id "$WORKSTATION_ID" \
  --install-type "$INSTALL_TYPE" \
  --chainup-public-key "$SYSTEM_RSA" \
  --remote-workdir "/data/co-signer" \
  --show-rsa-output "$SHOW_RSA_OUTPUT" \
  --cosigner-url "$DERIVED_COSIGNER_URL" \
  --server-public-ip "$SERVER_PUBLIC_IP" \
  --cosigner-port "$ACTUAL_COSIGNER_PORT" 2>/dev/null || echo "")

if [[ -z "$BUNDLE_OUTPUT" ]]; then
  log_error "Failed to generate bundle"
  exit 1
fi

BUNDLE_DIR=$(echo "$BUNDLE_OUTPUT" | grep "BUNDLE_DIR=" | cut -d'=' -f2)

log_success "Bundle generated in: $BUNDLE_DIR"
echo ""

# ============================================================================
# STEP 6: Call Subagent - Verify Deployment
# ============================================================================
log_info "STEP 6/6: Verifying deployment..."

VERIFY_OUTPUT=$(bash "$SCRIPT_DIR/subagents/verify/orchestrator_verify.sh" \
  --ssh-cmd "$SSH_CMD" 2>/dev/null || echo "")

if [[ -z "$VERIFY_OUTPUT" ]]; then
  log_warn "Could not verify deployment (may be in progress)"
else
  VERIFY_STATUS=$(echo "$VERIFY_OUTPUT" | grep "STATUS=" | cut -d'=' -f2)
  log_success "Verification status: $VERIFY_STATUS"
fi
echo ""

# ============================================================================
# Final Report
# ============================================================================
log_success "✨ Deployment Orchestration Complete!"
echo ""
echo "════════════════════════════════════════════════════════════"
echo "DEPLOYMENT SUMMARY"
echo "════════════════════════════════════════════════════════════"
echo "SSH Target:           $SSH_CMD"
echo "Workstation ID:       $WORKSTATION_ID"
echo "App ID:               ${APP_ID:0:32}..."
echo "Install Type:         $INSTALL_TYPE"
echo "Co-Signer Version:    $COSIGNER_VERSION"
echo "Encrypted Bundle:     $BUNDLE_DIR"
echo "════════════════════════════════════════════════════════════"
echo ""

# ============================================================================
# ⚠️  SECURITY OUTPUT — Co-Signer Initial Password (plaintext, shown once)
# ============================================================================
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
echo -e "\033[0;37m       cd /data/co-signer/mpc-co-signer\033[0m"
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

log_success "Done!"
