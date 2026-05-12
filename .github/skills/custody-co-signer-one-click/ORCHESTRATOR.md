---
name: custody-co-signer-orchestrator
description: "Master orchestrator for ChainUp Custody MPC co-signer deployment. Coordinates multiple subagents to perform deployment tasks while keeping context manageable."
user-invocable: true
---

# Custody Co-Signer Orchestrator

## Overview

This is the **master coordinator** skill for ChainUp Custody MPC co-signer deployment.

Instead of doing everything in one skill, this orchestrator delegates work to specialized subagents, each handling a specific function:

```
User Request
    ↓
Orchestrator (Main Agent)
    ├→ [Subagent 1] Cookie Acquisition
    ├→ [Subagent 2] Console Configuration Fetch
    ├→ [Subagent 3] Remote Environment Detection
    ├→ [Subagent 4] Remote Deployment Execution
    ├→ [Subagent 5] Secret Bundle Generation
    └→ [Subagent 6] Deployment Verification
```

## Benefits

- ✅ **Smaller Context**: Each subagent has focused scope
- ✅ **Better Parallelization**: Some tasks can run in parallel
- ✅ **Reusability**: Subagents can be used independently
- ✅ **Maintainability**: Easier to update individual components
- ✅ **Error Isolation**: Failures in one agent don't affect others

## Use When

- You want to deploy co-signer with automated steps
- You want to break deployment into manageable subagent tasks
- You need to distribute context across multiple agents

## Workflow

### Step 1: Get Credentials


- Automatic QR code login or interactive fallback
- Extract COINXMAN-SSO cookie from custody.chainup.com
- End browser participation after cookie capture

### Step 2: Fetch Console Config

**Subagent**: `custody-co-signer-fetch-config`

- Call GET /api/mpc/api/detail to check if API exists
- Create API if needed via POST /api/mpc/api/save
- Extract app_id and system_rsa
- Keep all subsequent Console operations on authenticated API requests only

### Step 3: Detect Remote Environment

**Subagent**: `custody-co-signer-detect-env`

- Probe SSH target OS and version
- Detect SGX capability → determine INSTALL_TYPE
- Validate co-signer binary compatibility

### Step 4: Execute Remote Deployment

**Subagent**: `custody-co-signer-deploy-remote`

- Download co-signer binary
- Run install.sh with auto-generated parameters
- Capture co-signer RSA public key
- Generate startup.sh and stop.sh scripts

### Step 5: Generate Secret Bundle

**Subagent**: `custody-co-signer-gen-bundle`

- Generate RSA key pair (custom_verify keys)
- Create encrypted payload with initial password
- Return encrypted bundle to user

### Step 6: Verify Deployment

**Subagent**: `custody-co-signer-verify`

- Check process is running
- Verify port listening
- Validate config and keystore files
- Show readiness status

## Orchestrator Inputs

Required:

- `SSH_CMD`: SSH command to target server

Optional:

- `WORKSTATION_ID`: (if auto-fetch cookie enabled)
- `COSIGNER_VERSION`: (if not auto-detect)
- `INSTALL_TYPE`: (if not auto-detect)

## Orchestrator Outputs

```json
{
  "status": "completed|partial|failed",
  "steps": [
    {
      "name": "step_name",
      "status": "success|failed|skipped",
      "output": "..."
    }
  ],
  "deployment_summary": {
    "cosigner_url": "http://...",
    "server_ip": "...",
    "api_id": "..."
  },
  "bundle_paths": {
    "encrypted_payload": "...",
    "private_key": "..."
  }
}
```

## References

- [Main SKILL.md](./SKILL.md) - Complete technical documentation
- [Subagent 2: Config](./subagents/fetch-config/SKILL.md)
- [Subagent 3: Environment](./subagents/detect-env/SKILL.md)
- [Subagent 4: Deploy](./subagents/deploy-remote/SKILL.md)
- [Subagent 5: Bundle](./subagents/gen-bundle/SKILL.md)
- [Subagent 6: Verify](./subagents/verify/SKILL.md)
