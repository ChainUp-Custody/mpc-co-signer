---
name: custody-co-signer-verify
description: "Verify co-signer deployment success (process, port, config, keystore, readiness)."
user-invocable: true
---

# Subagent 6: Deployment Verification

## What This Does

Performs comprehensive post-deployment validation to ensure co-signer is properly configured and running.

## Use When

- Deployment has completed
- You need to verify everything is working
- You need readiness status before Console submission

## Inputs

```json
{
  "ssh_cmd": "ssh -l root -p 22 <SERVER_IP>",
  "remote_workdir": "/data/co-signer",
  "cosigner_port": 28888
}
```

## Outputs

```json
{
  "status": "ready|partial|failed",
  "checks": {
    "process_running": {
      "status": "ok|fail",
      "details": "PID 12345, running as root"
    },
    "port_listening": {
      "status": "ok|fail",
      "details": "Listening on 0.0.0.0:28888"
    },
    "config_file": {
      "status": "ok|fail",
      "details": "config.yaml valid, app_id present"
    },
    "keystore_file": {
      "status": "ok|fail",
      "details": "keystore.json exists with RSA keys"
    },
    "logs_clean": {
      "status": "ok|fail",
      "details": "No fatal errors in nohup.out"
    },
    "ready_status": {
      "status": "ok|fail",
      "details": "co-signer ready status: true|false"
    }
  },
  "recommendations": ["..."],
  "logs_tail": "..."
}
```

## Verification Checks

### 1. Process Status

- Command: `ps aux | grep "[c]o-signer -server"`
- Expected: Process running
- Action if fail: Check nohup.out logs

### 2. Port Listening

- Command: `ss -lntp | grep 28888`
- Expected: Listening on `0.0.0.0:28888`
- Action if fail: May take time to bind, retry

### 3. Config File

- Path: `conf/config.yaml`
- Checks:
  - File exists and readable
  - Contains valid YAML
  - Has app_id configured
  - Has tcp port configured

### 4. Keystore File

- Path: `conf/keystore.json`
- Checks:
  - File exists
  - Contains RSA keys (rsa_pub, enc_rsa_pri)
  - Contains custody public key (enc_custody_pub)

### 5. Log Status

- Path: `nohup.out`
- Checks:
  - No fatal errors or crashes
  - No "FATAL", "PANIC" keywords
  - Shows service startup messages
  - Last 20 lines for review

### 6. Ready Status

- Command: Query internal co-signer API (if available)
- Checks:
  - Service reports `ready: true`
  - Or wait for Console approval

## Readiness Stages

- ✅ **Stage 1 - Deployed**: Process running, config created
- ✅ **Stage 2 - Listening**: Port 28888 responding
- ⏳ **Stage 3 - Ready**: Awaiting Console API approval
- ✅ **Stage 4 - Active**: API active in Console, ready for transactions

## Recommendations

Based on verification results:

- Process not running → restart via `./startup.sh`
- Port not listening → wait 5 seconds and retry
- Config incomplete → manual configuration needed
- Logs show errors → troubleshoot based on error type
- Ready status false → awaiting Console approval

## SSH Operations

- `ps aux` - Process status
- `ss -lntp` - Port listening
- `cat conf/config.yaml` - Config validation
- `cat conf/keystore.json` - Keystore validation
- `tail nohup.out` - Log review

## Error Handling

- SSH connection failed → retry
- Process crashed → tail logs and show error
- Port not listening → retry (may need time)
- Config files missing → critical error
- Logs show errors → detailed error reporting

## Timeout

- Process check: 5 seconds
- Port check: 10 seconds (with retries)
- Total verification: 30 seconds max
