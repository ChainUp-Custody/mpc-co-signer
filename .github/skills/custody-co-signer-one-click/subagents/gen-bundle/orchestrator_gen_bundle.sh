#!/usr/bin/env bash
set -euo pipefail

# Subagent 5: Secret Bundle Generation (Wrapper Script)
# Generates encrypted RSA+AES bundle

PASSWORD=""
APP_ID=""
COSIGNER_RSA=""
BUNDLE_DIR="${PWD}/.artifacts/custody-co-signer"
WORKSTATION_ID=""
INSTALL_TYPE=""
CHAINUP_PUBLIC_KEY=""
REMOTE_WORKDIR=""
SHOW_RSA_OUTPUT=""
COSIGNER_URL=""
SERVER_PUBLIC_IP=""
COSIGNER_PORT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --password) PASSWORD="$2"; shift 2 ;;
    --app-id) APP_ID="$2"; shift 2 ;;
    --cosigner-rsa) COSIGNER_RSA="$2"; shift 2 ;;
    --bundle-dir) BUNDLE_DIR="$2"; shift 2 ;;
    --workstation-id) WORKSTATION_ID="$2"; shift 2 ;;
    --install-type) INSTALL_TYPE="$2"; shift 2 ;;
    --chainup-public-key) CHAINUP_PUBLIC_KEY="$2"; shift 2 ;;
    --remote-workdir) REMOTE_WORKDIR="$2"; shift 2 ;;
    --show-rsa-output) SHOW_RSA_OUTPUT="$2"; shift 2 ;;
    --cosigner-url) COSIGNER_URL="$2"; shift 2 ;;
    --server-public-ip) SERVER_PUBLIC_IP="$2"; shift 2 ;;
    --cosigner-port) COSIGNER_PORT="$2"; shift 2 ;;
    *) echo "[ERROR] Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$PASSWORD" ]] || [[ -z "$APP_ID" ]]; then
  echo "[ERROR] PASSWORD and APP_ID required" >&2
  exit 1
fi

# Call bundle generation script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_SCRIPT="${SCRIPT_DIR}/../../../scripts/generate_secret_bundle.sh"

export APP_ID
export COSIGNER_PASSWORD="$PASSWORD"
export BUNDLE_DIR
export WORKSTATION_ID
export INSTALL_TYPE
export CHAINUP_PUBLIC_KEY
export REMOTE_WORKDIR
if [[ -n "$SHOW_RSA_OUTPUT" ]]; then
  export SHOW_RSA_OUTPUT
elif [[ -n "$COSIGNER_RSA" ]]; then
  export SHOW_RSA_OUTPUT="$COSIGNER_RSA"
fi
export COSIGNER_URL
export SERVER_PUBLIC_IP
export COSIGNER_PORT

BUNDLE_OUTPUT=$(bash "$BUNDLE_SCRIPT" 2>&1)

# Return results
echo "BUNDLE_DIR=$BUNDLE_DIR"
echo "BUNDLE_STATUS=generated"
