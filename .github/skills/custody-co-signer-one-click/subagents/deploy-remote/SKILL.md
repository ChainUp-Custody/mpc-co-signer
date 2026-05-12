---
name: custody-co-signer-deploy-remote
description: "Execute remote co-signer deployment via SSH (clone repo, run install.sh, generate startup scripts)."
user-invocable: true
---

# Subagent 4: Remote Deployment Execution

## What This Does

Runs the complete installation flow on remote server via SSH, generates startup and stop scripts.

## Use When

- You have all deployment parameters ready
- You need to run install.sh and capture RSA keys
- You need startup.sh and stop.sh scripts

## Inputs

```json
{
  "ssh_cmd": "ssh -l root -p 22 <SERVER_IP>",
  "app_id": "b017b99f...",
  "chainup_public_key": "MIIBIjANBgkq...",
  "install_type": 1,
  "cosigner_version": "latest",
  "cosigner_password": "...",
  "cosigner_port": 28888,
  "remote_workdir": "/data/co-signer"
}
```

## Outputs

```json
{
  "status": "success",
  "process_running": true,
  "port_listening": true,
  "co_signer_rsa_public": "-----BEGIN PUBLIC KEY-----...",
  "config_generated": true,
  "keystore_created": true,
  "startup_script_path": "/data/co-signer/mpc-co-signer/startup.sh",
  "stop_script_path": "/data/co-signer/mpc-co-signer/stop.sh",
  "logs_tail": "..."
}
```

## Process

1. **Prepare Environment**
   - Create deployment directory
   - Clone repository
   - Fetch latest tags

2. **Download Binary**
   - Select version by OS compatibility
   - Download co-signer binary
   - Verify executable

3. **Run Install**
   - Execute install.sh with inputs:
     - INSTALL_TYPE
     - APP_ID
     - CHAINUP_PUBLIC_KEY
     - Initial password
   - Capture generated RSA keypair via `-show-rsa`

4. **Generate Scripts**
   - Create `startup.sh` (TTY interactive password prompt)
   - Create `stop.sh` (graceful/force stop)
   - Set execute permissions (755/700)

5. **Verify Deployment**
   - Check co-signer process running
   - Check port listening (28888)
   - Validate config.yaml
   - Validate keystore.json

6. **Return Status**
   - Process status
   - Port listening status
   - Generated RSA public key
   - Config files created

## SSH Operations

- `git clone` + `git pull` - Repo management
- `./install.sh` - Main installation
- `./co-signer -show-rsa` - Extract keys
- `pkill co-signer` - Process management
- `ss -lntp` - Port verification

## Error Handling

- Network timeout → retry with exponential backoff
- install.sh failed → show error output and fail
- Binary incompatible → fallback to latest
- Process not starting → tail logs and debug
- Port not listening → wait and retry

## Security

- Password passed via stdin (not argv)
- SSH host key verification can be disabled (configurable)
- Logs sanitized before return
