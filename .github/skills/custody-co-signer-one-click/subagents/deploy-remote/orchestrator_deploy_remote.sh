#!/usr/bin/env bash
set -euo pipefail

# Subagent 4: Remote Deployment (Wrapper Script)
# Executes deployment via remote SSH

SSH_CMD=""
APP_ID=""
CHAINUP_PUBLIC_KEY=""
INSTALL_TYPE=""
COSIGNER_VERSION=""
REMOTE_WORKDIR="/data/co-signer"
PASSWORD=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ssh-cmd) SSH_CMD="$2"; shift 2 ;;
    --app-id) APP_ID="$2"; shift 2 ;;
    --chainup-public-key) CHAINUP_PUBLIC_KEY="$2"; shift 2 ;;
    --install-type) INSTALL_TYPE="$2"; shift 2 ;;
    --cosigner-version) COSIGNER_VERSION="$2"; shift 2 ;;
    --remote-workdir) REMOTE_WORKDIR="$2"; shift 2 ;;
    --password) PASSWORD="$2"; shift 2 ;;
    *) echo "[ERROR] Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$SSH_CMD" ]] || [[ -z "$APP_ID" ]]; then
  echo "[ERROR] SSH_CMD and APP_ID required" >&2
  exit 1
fi

# Generate strong password if not provided
if [[ -n "$PASSWORD" ]]; then
  COSIGNER_PASSWORD="$PASSWORD"
else
  COSIGNER_PASSWORD=$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | cut -c1-24)
fi

# Call main deployment script
export SSH_CMD
export APP_ID
export CHAINUP_PUBLIC_KEY
export INSTALL_TYPE
export COSIGNER_VERSION
export REMOTE_WORKDIR
export COSIGNER_PASSWORD

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_SCRIPT="${SCRIPT_DIR}/../../../scripts/deploy_remote_install.sh"

DEPLOY_OUTPUT=$(bash "$DEPLOY_SCRIPT" 2>&1)

SHOW_RSA_OUTPUT_B64=$(printf '%s\n' "$DEPLOY_OUTPUT" | awk -F= '/^SHOW_RSA_OUTPUT_B64=/{print $2; exit}')
COSIGNER_RSA_PUBLIC=""
if [[ -n "$SHOW_RSA_OUTPUT_B64" ]]; then
  SHOW_RSA_OUTPUT=$(printf '%s' "$SHOW_RSA_OUTPUT_B64" | base64 -d 2>/dev/null || true)
  COSIGNER_RSA_PUBLIC=$(printf '%s\n' "$SHOW_RSA_OUTPUT" | awk '
    /Co-Signer RSA Public Key:/ {capture=1; next}
    capture && NF {gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print; exit}
  ')
fi

# Return results
echo "COSIGNER_PASSWORD=$COSIGNER_PASSWORD"
echo "COSIGNER_RSA_PUBLIC=$COSIGNER_RSA_PUBLIC"
echo "SHOW_RSA_OUTPUT_B64=$SHOW_RSA_OUTPUT_B64"
echo "DEPLOY_STATUS=completed"
