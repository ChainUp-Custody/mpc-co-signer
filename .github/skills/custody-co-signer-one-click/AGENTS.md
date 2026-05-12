# Custody Co-Signer Deployment - Agent Architecture

## Overview

This skill has been refactored into a **modular multi-agent system** to manage context size and improve maintainability.

```
┌─────────────────────────────────────────────────────────┐
│         Master Orchestrator Agent                       │
│    (coordinates and delegates to subagents)             │
└──────────────┬──────────────────────────────────────────┘
               │
       ┌───────┼───────────────────┬──────────┬──────────┬──────────┐
       │       │                   │          │          │          │
   [1] │   [2] │               [3] │      [4] │      [5] │      [6] │
       ▼       ▼                   ▼          ▼          ▼          ▼
   ┌────────────────┐  ┌──────────────────┐  ┌────────────────┐  ┌──────────────┐
   │ Fetch Config     │  │ Detect Env     │  │Deploy Remote │
   │ (auto/manual)  │  │ (API check/create)│  │ (OS, SGX, v)   │  │(install.sh)  │
   └────────────────┘  └──────────────────┘  └────────────────┘  └──────────────┘

       ┌──────────────┐              ┌──────────────────┐
       │ Gen Bundle   │              │ Verify Deploy    │
       │ (encrypt)    │              │ (checks, status) │
       └──────────────┘              └──────────────────┘
```

## Agents

### Main Orchestrator

- **Name**: `custody-co-signer-orchestrator`
- **Role**: Coordinates overall deployment workflow
- **Context**: Orchestrates 6 subagents
- **Responsibility**:
  - Accept user input
  - Call subagents in sequence
  - Aggregate results
  - Report final status

### Subagent 1: Cookie Acquisition

- **Scope**: OAuth/Authentication only
- **Context Size**: Very small (~1-2K)
- **Responsibility**:
  - Automatic QR code login OR interactive paste
  - Extract COINXMAN-SSO cookie
  - Validate cookie format
- **Invocation**:
  ```
  (no inputs needed)
  ```
- **Output**:
  ```json
  { "cookie": "COINXMAN_SSO=...", "method": "automatic|interactive" }
  ```

### Subagent 2: Console Configuration Fetch

- **Name**: `custody-co-signer-fetch-config`
- **Scope**: Console API interaction only
- **Context Size**: Small (~2-3K)
- **Responsibility**:
  - Query GET /api/mpc/api/detail
  - Create API via POST if needed
  - Handle trade_no approval flow
  - Extract app_id and system_rsa
- **Invocation**:
  ```
  Call subagent: "custody-co-signer-fetch-config"
  With: COOKIE, WORKSTATION_ID
  ```
- **Output**:
  ```json
  { "app_id": "...", "system_rsa": "...", "created": true|false }
  ```
- **File**: `subagents/fetch-config/SKILL.md`

### Subagent 3: Environment Detection

- **Name**: `custody-co-signer-detect-env`
- **Scope**: Remote server probing only
- **Context Size**: Small (~2-3K)
- **Responsibility**:
  - Detect OS type and version
  - Check SGX capability
  - Select co-signer version
  - Validate binary compatibility
- **Invocation**:
  ```
  Call subagent: "custody-co-signer-detect-env"
  With: SSH_CMD
  ```
- **Output**:
  ```json
  {
    "os_id": "ubuntu",
    "os_version": "20.04",
    "install_type": 1,
    "recommended_version": "latest"
  }
  ```
- **File**: `subagents/detect-env/SKILL.md`

### Subagent 4: Remote Deployment

- **Name**: `custody-co-signer-deploy-remote`
- **Scope**: SSH deployment execution only
- **Context Size**: Medium (~4-5K)
- **Responsibility**:
  - Clone repo
  - Download binary
  - Run install.sh
  - Generate startup.sh and stop.sh
  - Capture co-signer RSA keys
  - Verify process running
- **Invocation**:
  ```
  Call subagent: "custody-co-signer-deploy-remote"
  With: SSH_CMD, APP_ID, CHAINUP_PUBLIC_KEY, INSTALL_TYPE,
        COSIGNER_PASSWORD, COSIGNER_VERSION, etc.
  ```
- **Output**:
  ```json
  {
    "status": "success",
    "process_running": true,
    "port_listening": true,
    "co_signer_rsa_public": "-----BEGIN PUBLIC KEY...",
    "startup_script_path": "..."
  }
  ```
- **File**: `subagents/deploy-remote/SKILL.md`

### Subagent 5: Secret Bundle Generation

- **Name**: `custody-co-signer-gen-bundle`
- **Scope**: Encryption and artifact generation only
- **Context Size**: Small (~3-4K)
- **Responsibility**:
  - Generate RSA keypair (custom_verify)
  - Create payload JSON
  - Encrypt with AES-256
  - Encrypt AES key with RSA
  - Output artifact bundle
- **Invocation**:
  ```
  Call subagent: "custody-co-signer-gen-bundle"
  With: COSIGNER_PASSWORD, APP_ID, COSIGNER_RSA_PUBLIC, etc.
  ```
- **Output**:
  ```json
  {
    "encrypted_payload": "/path/...",
    "encrypted_key": "/path/...",
    "private_key": "/path/...",
    "decrypt_command": "..."
  }
  ```
- **File**: `subagents/gen-bundle/SKILL.md`

### Subagent 6: Deployment Verification

- **Name**: `custody-co-signer-verify`
- **Scope**: Post-deployment checks only
- **Context Size**: Small (~2-3K)
- **Responsibility**:
  - Check process status
  - Verify port listening
  - Validate config files
  - Verify keystore
  - Review logs
  - Report readiness status
- **Invocation**:
  ```
  Call subagent: "custody-co-signer-verify"
  With: SSH_CMD, REMOTE_WORKDIR, COSIGNER_PORT
  ```
- **Output**:
  ```json
  {
    "status": "ready|partial|failed",
    "checks": { ... },
    "recommendations": [ ... ]
  }
  ```
- **File**: `subagents/verify/SKILL.md`

---

## Context Management

### Per-Agent Context Size

| Agent             | Scope          | Context | Status    |
| ----------------- | -------------- | ------- | --------- |
| **Orchestrator**  | Coordination   | 2-3K    | Minimal   |
| **Fetch Config**  | Console API    | 2-3K    | ✅ Small  |
| **Detect Env**    | Server Probing | 2-3K    | ✅ Small  |
| **Deploy Remote** | Installation   | 4-5K    | ✅ Medium |
| **Gen Bundle**    | Encryption     | 3-4K    | ✅ Small  |
| **Verify**        | Checks         | 2-3K    | ✅ Small  |

**Total if single agent**: ~18-25K (large)  
**Total distributed**: ~16-23K (same content, but each agent only sees its part)

### Context Distribution Strategy

1. **Pass only necessary data** between agents
2. **Use simple JSON structs** for inter-agent communication
3. **Aggregate results** in orchestrator
4. **Reuse scripts** where possible

---

## Invocation Patterns

### Pattern 1: Full Deployment (Orchestrator)

```
User → Orchestrator Agent
     Get: COINXMAN_SSO
  └→ Call "Fetch Config" subagent
     Get: APP_ID, SYSTEM_RSA
  └→ Call "Detect Env" subagent
     Get: INSTALL_TYPE, COSIGNER_VERSION
  └→ Call "Deploy Remote" subagent
     Get: PROCESS_RUNNING, COSIGNER_RSA_PUBLIC
  └→ Call "Gen Bundle" subagent
     Get: BUNDLE_PATHS
  └→ Call "Verify" subagent
     Get: DEPLOYMENT_STATUS
  └→ Return: FINAL_REPORT
```

### Pattern 2: Specific Task (Direct Subagent)

Users can also call subagents directly for specific tasks:

```
# Just get the cookie
       Get: COOKIE

# Just verify deployment
User → "custody-co-signer-verify" subagent
       (provide SSH_CMD)
       Get: DEPLOYMENT_STATUS
```

---

## File Structure

```
custody-co-signer-one-click/
├── ORCHESTRATOR.md                    # Master coordinator doc
├── SKILL.md                           # Original full documentation
├── AGENTS.md                          # This file
│
├── scripts/                           # Original shared scripts
│   ├── deploy_remote_install.sh
│   ├── generate_secret_bundle.sh
│   └── deploy_custody_cosigner.sh
│
└── subagents/                         # New modular structure
    │   ├── SKILL.md
    ├── fetch-config/
    │   ├── SKILL.md
    │   └── orchestrator_fetch_config.sh
    ├── detect-env/
    │   ├── SKILL.md
    │   └── orchestrator_detect_env.sh
    ├── deploy-remote/
    │   ├── SKILL.md
    │   └── orchestrator_deploy_remote.sh
    ├── gen-bundle/
    │   ├── SKILL.md
    │   └── orchestrator_gen_bundle.sh
    └── verify/
        ├── SKILL.md
        └── orchestrator_verify.sh
```

---

## Usage Guide

### Option A: Use Orchestrator (Recommended)

```
User provides: SSH_CMD, WORKSTATION_ID (optional)

Orchestrator automatically:
1. Gets cookie (auto or manual)
2. Fetches Console config
3. Detects environment
4. Executes deployment
5. Generates bundle
6. Verifies success
```

### Option B: Call Subagents Individually

```
# Step 1
Get: COOKIE

# Step 2
Call: custody-co-signer-fetch-config
Provide: COOKIE, WORKSTATION_ID
Get: APP_ID, SYSTEM_RSA

# ... continue with other subagents
```

---

## Benefits of Modular Architecture

✅ **Smaller Context**: Each agent ~2-5K, not 18-25K  
✅ **Parallel Execution**: Some steps can run in parallel  
✅ **Reusability**: Subagents can be used independently  
✅ **Maintainability**: Easier to update individual steps  
✅ **Error Isolation**: Failure in one agent doesn't affect others  
✅ **Testing**: Can test each agent independently

---

## Migration Guide

### From Monolithic to Modular

**Old way** (single large skill):

```
User → Main Skill
       (entire 18-25K context)
```

**New way** (orchestrated subagents):

```
User → Orchestrator
       ├→ Cookie Agent (1-2K)
       ├→ Config Agent (2-3K)
       ├→ Env Agent (2-3K)
       ├→ Deploy Agent (4-5K)
       ├→ Bundle Agent (3-4K)
       └→ Verify Agent (2-3K)
```

---

## References

- [Orchestrator](./ORCHESTRATOR.md)
- [Main Skill](./SKILL.md)
- [Subagent 2: Fetch Config](./subagents/fetch-config/SKILL.md)
- [Subagent 3: Detect Env](./subagents/detect-env/SKILL.md)
- [Subagent 4: Deploy Remote](./subagents/deploy-remote/SKILL.md)
- [Subagent 5: Gen Bundle](./subagents/gen-bundle/SKILL.md)
- [Subagent 6: Verify](./subagents/verify/SKILL.md)
