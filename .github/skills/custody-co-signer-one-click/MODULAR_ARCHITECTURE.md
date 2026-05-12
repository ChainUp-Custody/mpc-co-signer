# Custody Co-Signer Deployment - Modular Agent Architecture

## Overview

This skill has been **refactored from a monolithic architecture into a modular multi-agent system** to optimize context usage and improve maintainability.

```
┌─────────────────────────────────────────┐
│    User Request                         │
└────────────────┬────────────────────────┘
                 │
         ┌───────▼────────┐
         │  Orchestrator   │
         │  Main Agent     │
         └───────┬────────┘
                 │
    ┌────┬─────┬─┬─┬──┬────┐
    │    │     │ │ │  │    │
   [1] [2]  [3][4][5][6]
    │    │     │ │ │  │
    ▼    ▼     ▼ ▼ ▼  ▼
  Sub1  Sub2  Sub3 Sub4 Sub5 Sub6
 Cookie Config  Env Deploy Bundle Verify
```

---

## Quick Start

### Option 1: Use Master Orchestrator (Recommended)

Run the orchestrator script to automate all steps:

```bash
cd .github/skills/custody-co-signer-one-click

chmod +x orchestrate_deployment.sh
./orchestrate_deployment.sh \
  --ssh-cmd "ssh -l root -p 22 <SERVER_IP>" \
  --workstation-id <WORKSTATION_ID>
```

The orchestrator will:

1. ✅ Acquire cookie (auto QR code or interactive)
2. ✅ Fetch Console configuration
3. ✅ Detect remote environment (OS, SGX, version)
4. ✅ Execute deployment
5. ✅ Generate encrypted secret bundle
6. ✅ Verify success and readiness

### Option 2: Call Subagents Independently

You can also invoke individual subagents for specific tasks:

```bash
# Just get the cookie
# Output: COINXMAN_SSO=...

# Just verify a deployment
./subagents/verify/orchestrator_verify.sh --ssh-cmd "ssh..."
# Output: STATUS=ready, PROCESS_RUNNING=true, ...
```

---

## Architecture Overview

### Main Components

| Component               | Context | Responsibility                           |
| ----------------------- | ------- | ---------------------------------------- |
| **Orchestrator**        | 2-3K    | Coordinates workflow, calls subagents    |
| **Subagent 1** (Cookie) | 1-2K    | Browser QR login or interactive fallback |
| **Subagent 2** (Config) | 2-3K    | Query/create Console API configuration   |
| **Subagent 3** (Env)    | 2-3K    | Detect OS, SGX, co-signer version        |
| **Subagent 4** (Deploy) | 4-5K    | Execute remote SSH deployment            |
| **Subagent 5** (Bundle) | 3-4K    | Generate RSA+AES encrypted bundle        |
| **Subagent 6** (Verify) | 2-3K    | Check process, port, files, readiness    |

**Total Distributed Context**: ~16-23K  
**Per-Agent Context**: 1-5K (small and focused)

### Benefits

✅ **Small Context Per Agent** - Each agent only knows its part  
✅ **Parallel Potential** - Some steps could run in parallel  
✅ **Easy Maintenance** - Update one agent without affecting others  
✅ **Reusable** - Subagents can be called independently  
✅ **Better Error Handling** - Failure in one agent isolated  
✅ **Easier Testing** - Test each agent separately

---

## Subagent Details

Acquires COINXMAN-SSO cookie from `custody.chainup.com/login`

```bash
# Output: COINXMAN_SSO=234bf38c142048d66d60dbfe3c578136
```

**Inputs**: None  
**Outputs**: Cookie value

---

### 2️⃣ Fetch Config - `custody-co-signer-fetch-config`

**File**: `subagents/fetch-config/SKILL.md`

Queries Console API for deployment configuration

```bash
./subagents/fetch-config/orchestrator_fetch_config.sh \
  --cookie "COINXMAN_SSO=..." \
  --workstation-id <WORKSTATION_ID>
# Output: APP_ID=..., SYSTEM_RSA=...
```

**Inputs**: Cookie, Workstation ID  
**Outputs**: APP_ID, system_rsa, creation status

---

### 3️⃣ Detect Env - `custody-co-signer-detect-env`

**File**: `subagents/detect-env/SKILL.md`

Probes SSH target to detect OS, SGX, and co-signer version

```bash
./subagents/detect-env/orchestrator_detect_env.sh \
  --ssh-cmd "ssh -l root -p 22 <SERVER_IP>"
# Output: OS_ID=ubuntu, INSTALL_TYPE=1, COSIGNER_VERSION=latest
```

**Inputs**: SSH command  
**Outputs**: OS info, INSTALL_TYPE, recommended version

---

### 4️⃣ Deploy Remote - `custody-co-signer-deploy-remote`

**File**: `subagents/deploy-remote/SKILL.md`

Executes remote deployment (clone, install, generate scripts)

```bash
./subagents/deploy-remote/orchestrator_deploy_remote.sh \
  --ssh-cmd "ssh..." \
  --app-id "..." \
  --chainup-public-key "..." \
  --install-type 1 \
  --cosigner-version latest
# Output: COSIGNER_PASSWORD=..., COSIGNER_RSA_PUBLIC=...
```

**Inputs**: SSH cmd, App ID, Chainup key, Install type, Version  
**Outputs**: Password, RSA public key, deployment status

---

### 5️⃣ Gen Bundle - `custody-co-signer-gen-bundle`

**File**: `subagents/gen-bundle/SKILL.md`

Generates encrypted RSA+AES secret bundle

```bash
./subagents/gen-bundle/orchestrator_gen_bundle.sh \
  --password "..." \
  --app-id "..." \
  --cosigner-rsa "..."
# Output: BUNDLE_DIR=/path/to/.artifacts/...
```

**Inputs**: Password, App ID, Cosigner RSA  
**Outputs**: Bundle directory, file paths, decrypt command

---

### 6️⃣ Verify - `custody-co-signer-verify`

**File**: `subagents/verify/SKILL.md`

Verifies deployment success (process, port, files, readiness)

```bash
./subagents/verify/orchestrator_verify.sh \
  --ssh-cmd "ssh..." \
  --remote-workdir "/data/co-signer" \
  --port 28888
# Output: STATUS=ready, PROCESS_RUNNING=true, PORT_LISTENING=true
```

**Inputs**: SSH cmd, workdir, port  
**Outputs**: Overall status, individual check results

---

## File Structure

```
custody-co-signer-one-click/
│
├── README.md                          # This file
├── ORCHESTRATOR.md                    # Orchestrator design doc
├── AGENTS.md                          # Agent definitions
├── SKILL.md                           # Original full documentation
│
├── orchestrate_deployment.sh          # Main orchestrator script
│
├── scripts/                           # Original shared scripts
│   ├── deploy_remote_install.sh
│   ├── generate_secret_bundle.sh
│   └── deploy_custody_cosigner.sh
│
└── subagents/                         # Modular subagent system
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

## Usage Patterns

### Pattern A: Full Automated Deployment

```bash
./orchestrate_deployment.sh \
  --ssh-cmd "ssh -l root -p 22 SERVER" \
  --workstation-id <WORKSTATION_ID>
```

**Result**: End-to-end deployment, all 6 steps automated

---

### Pattern B: Individual Subagent Calls

```bash

```

**Verify Only**:

```bash
./subagents/verify/orchestrator_verify.sh --ssh-cmd "ssh..."
```

---

### Pattern C: Manual Workflow

```bash
# Step 1: Get credentials

# Step 2: Get config
CONFIG=$(./subagents/fetch-config/orchestrator_fetch_config.sh \
  --cookie "$COOKIE" --workstation-id <WORKSTATION_ID>)

# ... continue with other steps manually
```

---

## Context Comparison

### Old Monolithic Approach

```
Single Agent: 18-25K context
  - Cookie acquisition code
  - Console API code
  - Environment detection code
  - Deployment execution code
  - Bundle generation code
  - Verification code
  - All orchestration logic
  → Agent overwhelmed, context bloated
```

### New Modular Approach

```
Orchestrator: 2-3K context (coordination only)
  ├→ Subagent 1: 1-2K (cookie only)
  ├→ Subagent 2: 2-3K (API config only)
  ├→ Subagent 3: 2-3K (env detect only)
  ├→ Subagent 4: 4-5K (deployment only)
  ├→ Subagent 5: 3-4K (bundle only)
  └→ Subagent 6: 2-3K (verification only)

  Total: 16-23K (same content, distributed)
  Each agent: 1-5K (focused and clear)
```

---

## Best Practices

### ✅ Use Orchestrator When

- You want full end-to-end deployment
- You prefer automation over manual steps
- You want guaranteed consistency

### ✅ Call Subagents When

- You only need specific functionality
- You're integrating with other systems
- You want fine-grained control
- You're testing individual components

### ✅ Context Management

- Each agent stays under 5K context
- Agent only sees what it needs
- Orchestrator aggregates results
- No duplication across agents

---

## Troubleshooting

### Cookie Acquisition Fails

```bash
# Will automatically fallback to interactive mode
# Follow on-screen instructions to manually copy cookie
```

### Environment Detection Fails

```bash
./subagents/detect-env/orchestrator_detect_env.sh --ssh-cmd "ssh -l root -p 22 <SERVER_IP>"
# Check SSH connectivity
# Verify permissions (need access to /etc/os-release)
```

### Deployment Fails

```bash
./subagents/deploy-remote/orchestrator_deploy_remote.sh --ssh-cmd "ssh -l root -p 22 <SERVER_IP>" ...
# Check logs: tail /data/co-signer/mpc-co-signer/nohup.out
# Verify SSH key authentication works
```

### Verification Fails

```bash
./subagents/verify/orchestrator_verify.sh --ssh-cmd "ssh -l root -p 22 <SERVER_IP>"
# Check if process crashed: ./stop.sh then ./startup.sh
# Check port: ss -lntp | grep 28888
```

---

## Security Considerations

✅ **Small Attack Surface Per Agent** - Fewer features per agent  
✅ **Isolated Failures** - One agent failure doesn't cascade  
✅ **Encrypted Secrets** - Bundle contains RSA+AES encryption  
✅ **No Password Files** - Passwords encrypted, not stored  
✅ **TTY Interaction** - Password never in command args

---

## Performance

### Execution Timeline

| Step           | Agent      | Time   | Notes                              |
| -------------- | ---------- | ------ | ---------------------------------- |
| 1. Cookie      | Subagent 1 | 10-30s | Depends on QR scan or manual input |
| 2. Config      | Subagent 2 | 2-5s   | API query + potential creation     |
| 3. Environment | Subagent 3 | 5-10s  | SSH probes                         |
| 4. Deploy      | Subagent 4 | 30-60s | Download, install, verify          |
| 5. Bundle      | Subagent 5 | 3-5s   | Encryption operations              |
| 6. Verify      | Subagent 6 | 5-10s  | SSH checks                         |

**Total**: 55-120 seconds (depending on network/approval)

### Potential Parallelization

Steps that _could_ run in parallel:

- Steps 3-4 could start after step 2
- Step 5 needs result of step 4
- Step 6 can run after step 4

Current implementation is sequential for simplicity.

---

## Maintenance

### Adding a New Step

1. Create subagent folder: `subagents/new-step/`
2. Write `SKILL.md` with detailed specification
3. Write `orchestrator_new_step.sh` wrapper script
4. Update `orchestrate_deployment.sh` to call new step
5. Update this README

### Updating Existing Step

1. Edit the subagent's `SKILL.md`
2. Edit the wrapper script in `subagents/*/orchestrator_*.sh`
3. Test independently first
4. Test with orchestrator

### Testing Individual Agent

```bash
# Test cookie agent

# Test config agent (mock)
./subagents/fetch-config/orchestrator_fetch_config.sh \
  --cookie "COINXMAN_SSO=test" \
  --workstation-id <WORKSTATION_ID>

# ... etc
```

---

## References

- **Architecture**: [AGENTS.md](./AGENTS.md)
- **Orchestrator Design**: [ORCHESTRATOR.md](./ORCHESTRATOR.md)
- **Main Documentation**: [SKILL.md](./SKILL.md)
- **Improvements v2.1**: [IMPROVEMENTS_v2.1.md](./IMPROVEMENTS_v2.1.md)

---

## Summary

This modular architecture provides:

✅ **Focused Agents** - Each handles one responsibility  
✅ **Manageable Context** - 1-5K per agent vs 18-25K monolithic  
✅ **Reusable Components** - Use subagents independently  
✅ **Better Maintenance** - Update without affecting others  
✅ **Automated Orchestration** - One-command full deployment  
✅ **Flexible Usage** - Call agents individually or combined

**Get Started**: `./orchestrate_deployment.sh --ssh-cmd "ssh..." --workstation-id <id>`
