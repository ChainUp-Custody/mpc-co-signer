#!/usr/bin/env bash
set -euo pipefail

# Subagent 6: Deployment Verification (Wrapper Script)
# Checks process, port, config, and readiness

SSH_CMD=""
REMOTE_WORKDIR="/data/co-signer"
COSIGNER_PORT="28888"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ssh-cmd) SSH_CMD="$2"; shift 2 ;;
    --remote-workdir) REMOTE_WORKDIR="$2"; shift 2 ;;
    --port) COSIGNER_PORT="$2"; shift 2 ;;
    *) echo "[ERROR] Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$SSH_CMD" ]]; then
  echo "[ERROR] SSH_CMD required" >&2
  exit 1
fi

# Check process
PROCESS_CHECK=$(eval "$SSH_CMD" 'ps aux | grep "[c]o-signer -server"' || echo "")
if [[ -n "$PROCESS_CHECK" ]]; then
  PROCESS_RUNNING=true
else
  PROCESS_RUNNING=false
fi

# Check port
PORT_CHECK=$(eval "$SSH_CMD" "ss -lntp | grep ${COSIGNER_PORT}" || echo "")
if [[ -n "$PORT_CHECK" ]]; then
  PORT_LISTENING=true
else
  PORT_LISTENING=false
fi

# Check config
CONFIG_CHECK=$(eval "$SSH_CMD" "test -f ${REMOTE_WORKDIR}/mpc-co-signer/conf/config.yaml && echo ok" || echo "")
if [[ "$CONFIG_CHECK" == "ok" ]]; then
  CONFIG_VALID=true
else
  CONFIG_VALID=false
fi

# Determine overall status
if $PROCESS_RUNNING && $PORT_LISTENING && $CONFIG_VALID; then
  STATUS="ready"
elif $CONFIG_VALID; then
  STATUS="partial"
else
  STATUS="failed"
fi

# Return results
echo "STATUS=$STATUS"
echo "PROCESS_RUNNING=$PROCESS_RUNNING"
echo "PORT_LISTENING=$PORT_LISTENING"
echo "CONFIG_VALID=$CONFIG_VALID"
