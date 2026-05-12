#!/usr/bin/env bash
set -euo pipefail

# Subagent 3: Environment Detection (Wrapper Script)
# Probes SSH target to detect OS, SGX, and suitable co-signer version

SSH_CMD=""
BINARY_CHECK_TIMEOUT="8"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ssh-cmd) SSH_CMD="$2"; shift 2 ;;
    --timeout) BINARY_CHECK_TIMEOUT="$2"; shift 2 ;;
    *) echo "[ERROR] Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$SSH_CMD" ]]; then
  echo "[ERROR] SSH_CMD required" >&2
  exit 1
fi

# Detect OS
OS_RELEASE=$(eval "$SSH_CMD" 'cat /etc/os-release 2>/dev/null' || echo "")
OS_ID=$(echo "$OS_RELEASE" | grep '^ID=' | cut -d'=' -f2 | tr -d '"' || echo "unknown")
OS_VERSION=$(echo "$OS_RELEASE" | grep '^VERSION_ID=' | cut -d'=' -f2 | tr -d '"' || echo "unknown")

# Detect SGX
SGX_CHECK=$(eval "$SSH_CMD" 'ls /dev/sgx* 2>/dev/null' || echo "")
if [[ -n "$SGX_CHECK" ]]; then
  INSTALL_TYPE=2
  SGX_AVAILABLE=true
else
  INSTALL_TYPE=1
  SGX_AVAILABLE=false
fi

# Select co-signer version
if [[ "$OS_ID" == "ubuntu" ]] && [[ "$OS_VERSION" == "22.04" ]]; then
  COSIGNER_VERSION="latest"
else
  COSIGNER_VERSION="latest"
fi

# Return results
echo "OS_ID=$OS_ID"
echo "OS_VERSION=$OS_VERSION"
echo "OS_INFO=${OS_ID}-${OS_VERSION}"
echo "INSTALL_TYPE=$INSTALL_TYPE"
echo "SGX_AVAILABLE=$SGX_AVAILABLE"
echo "COSIGNER_VERSION=$COSIGNER_VERSION"
