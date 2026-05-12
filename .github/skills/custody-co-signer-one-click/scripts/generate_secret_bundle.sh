#!/usr/bin/env bash
set -euo pipefail

# Generate a custom verify RSA key pair and encrypt a payload bundle with it.
# Optional env vars:
#   BUNDLE_DIR, PAYLOAD_JSON, PAYLOAD_FILE, KEY_PREFIX,
#   APP_ID, WORKSTATION_ID, INSTALL_TYPE, COSIGNER_PASSWORD,
#   CHAINUP_PUBLIC_KEY, REMOTE_WORKDIR, SHOW_RSA_OUTPUT,
#   COSIGNER_URL, SERVER_PUBLIC_IP, COSIGNER_PORT

BUNDLE_DIR="${BUNDLE_DIR:-$PWD/.artifacts/custody-co-signer}"
PAYLOAD_JSON="${PAYLOAD_JSON:-}"
PAYLOAD_FILE="${PAYLOAD_FILE:-}"
KEY_PREFIX="${KEY_PREFIX:-custom_verify}"
APP_ID="${APP_ID:-}"
WORKSTATION_ID="${WORKSTATION_ID:-}"
INSTALL_TYPE="${INSTALL_TYPE:-}"
COSIGNER_PASSWORD="${COSIGNER_PASSWORD:-}"
CHAINUP_PUBLIC_KEY="${CHAINUP_PUBLIC_KEY:-}"
REMOTE_WORKDIR="${REMOTE_WORKDIR:-}"
SHOW_RSA_OUTPUT="${SHOW_RSA_OUTPUT:-}"
COSIGNER_URL="${COSIGNER_URL:-}"
SERVER_PUBLIC_IP="${SERVER_PUBLIC_IP:-}"
COSIGNER_PORT="${COSIGNER_PORT:-}"

mkdir -p "${BUNDLE_DIR}"

PRIVATE_KEY_PATH="${BUNDLE_DIR}/${KEY_PREFIX}_private.pem"
PUBLIC_KEY_PATH="${BUNDLE_DIR}/${KEY_PREFIX}_public.pem"
AES_KEY_PATH="${BUNDLE_DIR}/secret_payload.aes.key"
AES_ENC_PATH="${BUNDLE_DIR}/secret_payload.json.enc"
RSA_ENC_KEY_PATH="${BUNDLE_DIR}/secret_payload.aes.key.enc"

if [[ -n "${PAYLOAD_JSON}" && -n "${PAYLOAD_FILE}" ]]; then
  echo "[ERROR] Set only one of PAYLOAD_JSON or PAYLOAD_FILE." >&2
  exit 1
fi

# Build payload content in memory — never written to disk as plaintext.
# PAYLOAD_FILE is an externally-provided file path (caller's responsibility).
if [[ -n "${PAYLOAD_FILE}" ]]; then
  PAYLOAD_CONTENT=$(cat "${PAYLOAD_FILE}")
elif [[ -n "${PAYLOAD_JSON}" ]]; then
  PAYLOAD_CONTENT="${PAYLOAD_JSON}"
else
  PAYLOAD_CONTENT=$(printf '{
  "app_id": "%s",
  "workstation_id": "%s",
  "install_type": "%s",
  "co_signer_initial_password": "%s",
  "co_signer_password_note": "Use this password to start co-signer. This bundle is encrypted for security.",
  "co_signer_password_usage": "On server: ./startup.sh (will prompt for password, use value above)",
  "chainup_public_key": "%s",
  "remote_workdir": "%s",
  "show_rsa_output": "%s",
  "cosigner_url": "%s",
  "server_public_ip": "%s",
  "cosigner_port": "%s",
  "console_domain": "https://custody.chainup.com",
  "console_whitelist_source_ip": "54.254.7.206",
  "console_custody_endpoint": "54.251.87.91:443"
}' \
    "${APP_ID}" "${WORKSTATION_ID}" "${INSTALL_TYPE}" "${COSIGNER_PASSWORD}" \
    "${CHAINUP_PUBLIC_KEY}" "${REMOTE_WORKDIR}" "${SHOW_RSA_OUTPUT}" \
    "${COSIGNER_URL}" "${SERVER_PUBLIC_IP}" "${COSIGNER_PORT}")
fi

openssl genrsa -out "${PRIVATE_KEY_PATH}" 2048 >/dev/null 2>&1
openssl rsa -in "${PRIVATE_KEY_PATH}" -pubout -out "${PUBLIC_KEY_PATH}" >/dev/null 2>&1

# AES key is random bytes (no sensitive data) — temp file acceptable.
openssl rand -out "${AES_KEY_PATH}" 32
# Encrypt payload directly from memory via process substitution — no plaintext file on disk.
openssl enc -aes-256-cbc -pbkdf2 -salt \
  -in <(printf '%s\n' "${PAYLOAD_CONTENT}") \
  -out "${AES_ENC_PATH}" -pass file:"${AES_KEY_PATH}"
openssl pkeyutl -encrypt -pubin -inkey "${PUBLIC_KEY_PATH}" -in "${AES_KEY_PATH}" -out "${RSA_ENC_KEY_PATH}" \
  -pkeyopt rsa_padding_mode:oaep -pkeyopt rsa_oaep_md:sha256 >/dev/null 2>&1

rm -f "${AES_KEY_PATH}"

echo "CUSTOM_VERIFY_PUBLIC_KEY_PATH=${PUBLIC_KEY_PATH}"
echo "CUSTOM_VERIFY_PRIVATE_KEY_PATH=${PRIVATE_KEY_PATH}"
echo "ENCRYPTED_PAYLOAD_PATH=${AES_ENC_PATH}"
echo "ENCRYPTED_AES_KEY_PATH=${RSA_ENC_KEY_PATH}"
echo "CUSTOM_VERIFY_PUBLIC_KEY_B64=$(base64 <"${PUBLIC_KEY_PATH}" | tr -d '\n')"
echo "CUSTOM_VERIFY_PRIVATE_KEY_B64=$(base64 <"${PRIVATE_KEY_PATH}" | tr -d '\n')"
echo "ENCRYPTED_PAYLOAD_B64=$(base64 <"${AES_ENC_PATH}" | tr -d '\n')"
echo "ENCRYPTED_AES_KEY_B64=$(base64 <"${RSA_ENC_KEY_PATH}" | tr -d '\n')"
echo "DECRYPT_COMMAND=openssl pkeyutl -decrypt -inkey ${PRIVATE_KEY_PATH} -in ${RSA_ENC_KEY_PATH} -out ${BUNDLE_DIR}/secret_payload.aes.key -pkeyopt rsa_padding_mode:oaep -pkeyopt rsa_oaep_md:sha256 && openssl enc -d -aes-256-cbc -pbkdf2 -in ${AES_ENC_PATH} -out ${BUNDLE_DIR}/secret_payload.json.decrypted -pass file:${BUNDLE_DIR}/secret_payload.aes.key"