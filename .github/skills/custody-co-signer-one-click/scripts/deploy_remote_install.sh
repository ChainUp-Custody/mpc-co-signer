#!/usr/bin/env bash
set -euo pipefail

# One-click remote deployment wrapper for ChainUp mpc-co-signer install.sh.
# Required env vars:
#   SSH_CMD, APP_ID, CHAINUP_PUBLIC_KEY
# Optional env vars:
#   INSTALL_TYPE(1|2), COSIGNER_PASSWORD, WITHDRAW_CALLBACK_URL,
#   WEB3_CALLBACK_URL, CUSTOM_VERIFY_PUBLIC_KEY, REMOTE_WORKDIR,
#   SHOW_RSA_AFTER_INSTALL(1|0), COSIGNER_PORT,
#   COSIGNER_VERSION,
#   DOWNLOAD_MAX_SECONDS, DOWNLOAD_RETRY, BINARY_CHECK_TIMEOUT

require_env() {
  local key="$1"
  if [[ -z "${!key:-}" ]]; then
    echo "[ERROR] Missing required env: ${key}" >&2
    exit 1
  fi
}

b64() {
  printf '%s' "$1" | base64 | tr -d '\n'
}

require_env "SSH_CMD"
require_env "APP_ID"
require_env "CHAINUP_PUBLIC_KEY"

generate_password() {
  # Use openssl to avoid SIGPIPE from tr+head with pipefail enabled.
  if command -v openssl >/dev/null 2>&1; then
    # 24-char base62 password (higher entropy than 16-char)
    openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | cut -c1-24
  else
    LC_ALL=C dd if=/dev/urandom bs=64 count=1 2>/dev/null | tr -dc 'A-Za-z0-9' | cut -c1-24
  fi
}

INSTALL_TYPE="${INSTALL_TYPE:-}"
COSIGNER_PASSWORD="${COSIGNER_PASSWORD:-$(generate_password)}"
WITHDRAW_CALLBACK_URL="${WITHDRAW_CALLBACK_URL:-}"
WEB3_CALLBACK_URL="${WEB3_CALLBACK_URL:-}"
CUSTOM_VERIFY_PUBLIC_KEY="${CUSTOM_VERIFY_PUBLIC_KEY:-}"
REMOTE_WORKDIR="${REMOTE_WORKDIR:-/data/co-signer}"
SHOW_RSA_AFTER_INSTALL="${SHOW_RSA_AFTER_INSTALL:-1}"
COSIGNER_PORT="${COSIGNER_PORT:-28888}"
COSIGNER_VERSION="${COSIGNER_VERSION:-}"
DOWNLOAD_MAX_SECONDS="${DOWNLOAD_MAX_SECONDS:-180}"
DOWNLOAD_RETRY="${DOWNLOAD_RETRY:-2}"
BINARY_CHECK_TIMEOUT="${BINARY_CHECK_TIMEOUT:-8}"

if [[ -n "${INSTALL_TYPE}" && "${INSTALL_TYPE}" != "1" && "${INSTALL_TYPE}" != "2" ]]; then
  echo "[ERROR] INSTALL_TYPE must be 1 (standard) or 2 (SGX)." >&2
  exit 1
fi

if ! [[ "${COSIGNER_PORT}" =~ ^[0-9]+$ ]]; then
  echo "[ERROR] COSIGNER_PORT must be numeric." >&2
  exit 1
fi

APP_ID_B64="$(b64 "${APP_ID}")"
PASSWORD_B64="$(b64 "${COSIGNER_PASSWORD}")"
CHAINUP_KEY_B64="$(b64 "${CHAINUP_PUBLIC_KEY}")"
CUSTOM_KEY_B64="$(b64 "${CUSTOM_VERIFY_PUBLIC_KEY}")"
WITHDRAW_CB_B64="$(b64 "${WITHDRAW_CALLBACK_URL}")"
WEB3_CB_B64="$(b64 "${WEB3_CALLBACK_URL}")"
REMOTE_WORKDIR_B64="$(b64 "${REMOTE_WORKDIR}")"
COSIGNER_PORT_B64="$(b64 "${COSIGNER_PORT}")"
COSIGNER_VERSION_B64="$(b64 "${COSIGNER_VERSION}")"
DOWNLOAD_MAX_SECONDS_B64="$(b64 "${DOWNLOAD_MAX_SECONDS}")"
DOWNLOAD_RETRY_B64="$(b64 "${DOWNLOAD_RETRY}")"
BINARY_CHECK_TIMEOUT_B64="$(b64 "${BINARY_CHECK_TIMEOUT}")"

echo "[INFO] Starting remote deployment via SSH..."

eval "${SSH_CMD} 'bash -s'" <<EOF
set -euo pipefail

decode() {
  printf '%s' "\$1" | base64 -d
}

APP_ID="\$(decode '${APP_ID_B64}')"
PASSWORD="\$(decode '${PASSWORD_B64}')"
CHAINUP_PUBLIC_KEY="\$(decode '${CHAINUP_KEY_B64}')"
CUSTOM_VERIFY_PUBLIC_KEY="\$(decode '${CUSTOM_KEY_B64}')"
WITHDRAW_CALLBACK_URL="\$(decode '${WITHDRAW_CB_B64}')"
WEB3_CALLBACK_URL="\$(decode '${WEB3_CB_B64}')"
REMOTE_WORKDIR="\$(decode '${REMOTE_WORKDIR_B64}')"
COSIGNER_PORT="\$(decode '${COSIGNER_PORT_B64}')"
COSIGNER_VERSION="\$(decode '${COSIGNER_VERSION_B64}')"
DOWNLOAD_MAX_SECONDS="\$(decode '${DOWNLOAD_MAX_SECONDS_B64}')"
DOWNLOAD_RETRY="\$(decode '${DOWNLOAD_RETRY_B64}')"
BINARY_CHECK_TIMEOUT="\$(decode '${BINARY_CHECK_TIMEOUT_B64}')"
INSTALL_TYPE="${INSTALL_TYPE}"
SHOW_RSA_AFTER_INSTALL="${SHOW_RSA_AFTER_INSTALL}"

detect_install_type() {
  if [[ -e /dev/sgx_enclave || -e /dev/sgx/enclave || -e /dev/sgx_provision || -e /dev/sgx/provision ]]; then
    echo 2
    return
  fi

  if command -v dmesg >/dev/null 2>&1 && dmesg 2>/dev/null | grep -qi 'sgx'; then
    echo 2
    return
  fi

  echo 1
}

select_cosigner_version() {
  if [[ -n "\${COSIGNER_VERSION}" && "\${COSIGNER_VERSION}" != "latest" ]]; then
    printf '%s' "\${COSIGNER_VERSION}"
    return
  fi

  curl -fsSL https://api.github.com/repos/ChainUp-Custody/mpc-co-signer/releases/latest \
    | grep -m1 '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/'
}

normalize_version_tag() {
  local raw="\${1:-}"
  if [[ -z "\${raw}" ]]; then
    return
  fi
  if [[ "\${raw}" =~ ^v ]]; then
    printf '%s' "\${raw}"
  else
    printf 'v%s' "\${raw}"
  fi
}

extract_binary_version_tag() {
  local version_out tag
  version_out="\$(timeout "\${BINARY_CHECK_TIMEOUT}" ./co-signer -v 2>&1 || true)"
  tag="\$(printf '%s\n' "\${version_out}" | grep -Eo 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
  if [[ -z "\${tag}" ]]; then
    tag="\$(printf '%s\n' "\${version_out}" | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
    if [[ -n "\${tag}" ]]; then
      tag="v\${tag}"
    fi
  fi
  printf '%s' "\${tag}"
}

download_cosigner_binary() {
  local selected_version selected_tag download_url existing_tag

  selected_version="\$(select_cosigner_version)"
  selected_tag="\$(normalize_version_tag "\${selected_version}")"

  if [[ -z "\${selected_tag}" ]]; then
    echo "[ERROR] Failed to determine co-signer version." >&2
    exit 1
  fi

  if [[ -x ./co-signer ]]; then
    existing_tag="\$(extract_binary_version_tag)"
    if [[ -n "\${existing_tag}" ]]; then
      if [[ "\${existing_tag}" == "\${selected_tag}" ]]; then
        echo "[INFO] Reusing existing co-signer binary (version \${existing_tag})."
        return
      fi
      echo "[WARN] Existing co-signer version \${existing_tag} != target \${selected_tag}; redownloading."
    else
      echo "[WARN] Existing co-signer binary not executable or version unknown; redownloading."
    fi
  fi

  if [[ "\${INSTALL_TYPE}" = "2" ]]; then
    download_url="https://github.com/ChainUp-Custody/mpc-co-signer/releases/download/\${selected_tag}/co-signer-linux-\${selected_tag}"
  else
    download_url="https://github.com/ChainUp-Custody/mpc-co-signer/releases/download/\${selected_tag}/co-signer-linux-\${selected_tag}-static"
  fi

  echo "[INFO] Selected co-signer version: \${selected_tag}"
  echo "[INFO] Download timeout=\${DOWNLOAD_MAX_SECONDS}s retry=\${DOWNLOAD_RETRY}"
  rm -f ./co-signer
  if command -v wget >/dev/null 2>&1; then
    timeout "\${DOWNLOAD_MAX_SECONDS}" wget -c --tries="\${DOWNLOAD_RETRY}" --timeout=20 --read-timeout=20 -O ./co-signer "\${download_url}"
  else
    timeout "\${DOWNLOAD_MAX_SECONDS}" curl --http1.1 -fL --retry "\${DOWNLOAD_RETRY}" --retry-delay 2 --connect-timeout 12 --max-time "\${DOWNLOAD_MAX_SECONDS}" -C - -o ./co-signer "\${download_url}"
  fi
  chmod +x ./co-signer

  local post_tag
  post_tag="\$(extract_binary_version_tag)"
  if [[ -z "\${post_tag}" ]]; then
    echo "[ERROR] Downloaded co-signer binary is not runnable on target host (no version output)." >&2
    exit 1
  fi
  echo "[INFO] Binary verified: \${post_tag}"
}

if [[ -z "\${INSTALL_TYPE}" ]]; then
  INSTALL_TYPE="\$(detect_install_type)"
fi

mkdir -p "\${REMOTE_WORKDIR}"
cd "\${REMOTE_WORKDIR}"

mkdir -p mpc-co-signer
cd mpc-co-signer
download_cosigner_binary

# === Direct configuration (bypass install.sh which has broken exit-code handling) ===
mkdir -p conf

# Generate config.yaml
cat > ./conf/config.yaml <<CFGEOF
## Main Configuration Information
main:
    tcp: "0.0.0.0:\${COSIGNER_PORT}"
    keystore_file: "conf/keystore.json"

## Custody System
custody_service:
    app_id: "\${APP_ID}"
    domain: "https://openapi.chainup.com/"
    language: "en_US"

## Client System
custom_service:
    withdraw_callback_url: "\${WITHDRAW_CALLBACK_URL}"
    web3_callback_url: "\${WEB3_CALLBACK_URL}"
CFGEOF

# Reset keystore to ensure clean RSA generation
echo '{}' > ./conf/keystore.json

# Generate RSA keypair (co-signer exits non-zero even on success; check output text)
RSA_OUT=\$(echo "\${PASSWORD}" | ./co-signer -rsa-gen 2>&1) || true
if ! echo "\${RSA_OUT}" | grep -Eqi "generate rsa success|co-signer rsa public key|BEGIN PUBLIC KEY"; then
  echo "[ERROR] RSA generation failed: \${RSA_OUT}" >&2
  exit 1
fi
echo "[OK] RSA keypair generated."

# Import ChainUp custody public key
if [[ -n "\${CHAINUP_PUBLIC_KEY}" ]]; then
  IMP_OUT=\$(echo "\${PASSWORD}" | ./co-signer -custody-pub-import "\${CHAINUP_PUBLIC_KEY}" 2>&1) || true
  if echo "\${IMP_OUT}" | grep -qi "fail\|error\|panic"; then
    echo "[ERROR] Import ChainUp public key failed: \${IMP_OUT}" >&2
    exit 1
  fi
  echo "[OK] ChainUp public key imported."
fi

# Import custom verify public key (optional)
if [[ -n "\${CUSTOM_VERIFY_PUBLIC_KEY}" ]]; then
  VER_OUT=\$(echo "\${PASSWORD}" | ./co-signer -verify-sign-pub-import "\${CUSTOM_VERIFY_PUBLIC_KEY}" 2>&1) || true
  if echo "\${VER_OUT}" | grep -qi "fail\|error\|panic"; then
    echo "[ERROR] Import custom verify key failed: \${VER_OUT}" >&2
    exit 1
  fi
  echo "[OK] Custom verify public key imported."
fi

# Write a startup script with fixed template (mandatory)
cat > ./startup.sh <<'STARTUP_EOF'
#!/bin/bash -e

project_path=\$(
    cd \$(dirname \$0)
    pwd
)

STR_PASSWORD=""
echo -n "Please enter your password:"
stty -echo
read STR_PASSWORD
stty echo


if [ ! -n "\$STR_PASSWORD" ]; then
    echo "Password cannot be null"
    exit 1
fi

echo ""
echo "Startup Program..."
echo ""

# start
echo \${STR_PASSWORD} | nohup \${project_path}/co-signer -server >>nohup.out 2>&1 & 
STARTUP_EOF
chmod u+x ./startup.sh

# Generate a stop script
cat > ./stop.sh <<'STOP_EOF'
#!/usr/bin/env bash
set -euo pipefail

echo "[INFO] Stopping co-signer service..."
if pkill -x co-signer; then
  echo "[OK] co-signer process terminated"
else
  echo "[WARN] co-signer process not found or already stopped"
fi

# Wait briefly for graceful shutdown
sleep 1

# Force kill if still running
if pgrep -x co-signer >/dev/null 2>&1; then
  echo "[INFO] Force killing remaining co-signer processes..."
  pkill -9 -x co-signer || true
  sleep 1
fi

echo "[INFO] Service stopped."
if [[ -f ./nohup.out ]]; then
  echo "[INFO] Last logs:"
  tail -n 20 ./nohup.out
fi
STOP_EOF
chmod u+x ./stop.sh

# Security: Do NOT store password in files or pass via stdin
# Startup requires customer to input password interactively
echo ""
echo "════════════════════════════════════════════════════════════"
echo "MANUAL STARTUP REQUIRED (Password not stored on server)"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "To start co-signer manually on the server, run:"
echo "  cd \${REMOTE_WORKDIR}/mpc-co-signer"
echo "  ./startup.sh"
echo ""
echo "You will be prompted to enter the password shown in the"
echo "encrypted secret bundle (encrypted_payload.json.enc)"
echo ""
echo "Note: This is for security. Password is NOT stored on server."
echo ""
sleep 2

if command -v ss >/dev/null 2>&1; then
  ss -lntp | grep ":\${COSIGNER_PORT}" || true
fi

echo "[INFO] Startup requires customer to enter password (see bundle)."
echo ""

SERVER_PUBLIC_IP=""
if command -v curl >/dev/null 2>&1; then
  SERVER_PUBLIC_IP="\$(curl -4s --max-time 5 https://api.ipify.org || true)"
fi
if [[ -z "\${SERVER_PUBLIC_IP}" ]]; then
  SERVER_PUBLIC_IP="\$(hostname -I 2>/dev/null | awk '{print \$1}')"
fi

if [[ -n "\${SERVER_PUBLIC_IP}" ]]; then
  echo "SERVER_PUBLIC_IP=\${SERVER_PUBLIC_IP}"
fi

if [[ "\${SHOW_RSA_AFTER_INSTALL}" = "1" ]]; then
  echo "[INFO] Exporting configured RSA public keys..."
  RSA_OUTPUT="\$(echo "\${PASSWORD}" | ./co-signer -show-rsa 2>&1 || true)"
  printf 'SHOW_RSA_OUTPUT_B64=%s\n' "\$(printf '%s' "\${RSA_OUTPUT}" | base64 | tr -d '\n')"
fi

echo "[INFO] Derived install type: \${INSTALL_TYPE}"
echo "REMOTE_WORKDIR=\${REMOTE_WORKDIR}"

# Read actual listening port from generated config.yaml so the inbound rule is accurate.
ACTUAL_PORT=""
if [[ -f ./conf/config.yaml ]]; then
  ACTUAL_PORT="\$(grep -E '^\s*tcp:' ./conf/config.yaml | head -1 | sed -E 's/.*:([0-9]+).*/\1/')"
fi
if [[ -z "\${ACTUAL_PORT}" ]]; then
  ACTUAL_PORT="\${COSIGNER_PORT}"
fi
echo "ACTUAL_COSIGNER_PORT=\${ACTUAL_PORT}"
EOF

echo "[INFO] Generated co-signer initial password (${#COSIGNER_PASSWORD} chars, delivered encrypted in bundle)"
echo "DEPLOY_INSTALL_TYPE=${INSTALL_TYPE:-auto}"
echo "DEPLOY_REMOTE_WORKDIR=${REMOTE_WORKDIR}"
echo "DEPLOY_COSIGNER_PORT=${COSIGNER_PORT}"

SSH_TARGET="$(printf '%s' "${SSH_CMD}" | awk '{print $NF}')"
SSH_HOST="${SSH_TARGET##*@}"
if [[ -n "${SSH_HOST}" ]]; then
  echo "DERIVED_COSIGNER_URL=${SSH_HOST}:${COSIGNER_PORT}"
fi

# Extract actual port from remote output (line: ACTUAL_COSIGNER_PORT=...)
ACTUAL_COSIGNER_PORT="$(eval "${SSH_CMD} 'bash -s'" <<'PORTEOF'
grep -E '^\s*tcp:' /data/co-signer/mpc-co-signer/conf/config.yaml 2>/dev/null | head -1 | sed -E 's/.*:([0-9]+).*/\1/'
PORTEOF
)" 2>/dev/null || true
if [[ -z "${ACTUAL_COSIGNER_PORT}" ]]; then
  ACTUAL_COSIGNER_PORT="${COSIGNER_PORT}"
fi

echo "CONSOLE_REQUIRED_WHITELIST_SOURCE_IP=54.254.7.206"
echo "CONSOLE_REQUIRED_CUSTODY_ENDPOINT=54.251.87.91:443"
echo "CONSOLE_REQUIRED_NETWORK_RULE_INBOUND=54.254.7.206->${ACTUAL_COSIGNER_PORT}"
echo "CONSOLE_REQUIRED_NETWORK_RULE_OUTBOUND=54.251.87.91:443"
echo "CONSOLE_REQUIRED_NETWORK_RULE_SOURCE=https://custodydocs-zh.chainup.com/api-references/mpc-apis/co-signer/deploy#iv-co-signer"
echo "[INFO] Remote deploy finished."
