# Custody Co-Signer One-Click Deploy - Specification

Status: updated to align with current `SKILL.md`, `AGENTS.md`, `ORCHESTRATOR.md`, `QUICK_REFERENCE.md`, and scripts under `scripts/`.

## 1. Scope and Source of Truth

This specification defines the canonical behavior for the co-signer one-click deployment skill in:

- `.github/skills/custody-co-signer-one-click/`

Normative priority for conflicts:

1. `SKILL.md`
2. Script behavior in `scripts/*.sh` and `scripts/*.py`
3. `AGENTS.md` and `ORCHESTRATOR.md`
4. `QUICK_REFERENCE.md`

If examples in old docs differ from `SKILL.md`, this spec follows `SKILL.md`.

## 2. High-Level Goal

Deploy ChainUp Custody MPC co-signer to a remote server over SSH with:

- automatic remote installation and key generation
- Console API create/update flow
- approval-aware response handling
- secure password handling (no password in command-line strings)
- final security checklist and plaintext initial password display

## 3. Runtime Architecture

The project supports two orchestration styles:

1. Master orchestrator script: `orchestrate_deployment.sh`
2. Integrated script flow: `scripts/deploy_custody_cosigner.sh`

Core shared scripts:

- `scripts/deploy_remote_install.sh`: phase-1 remote deployment, config/bootstrap, RSA generation
- `scripts/get_custody_cookie.py`: headless QR login and `COINXMAN-SSO` extraction
- `scripts/console_api_ops.py`: Console API get/save/list operations
- `scripts/cosigner_remote_ops.py`: password-sensitive remote actions via stdin pipe
- `scripts/generate_secret_bundle.sh`: encrypted artifact generation

Subagents and helper orchestrators under `subagents/` are valid modular execution units.

## 4. Required Inputs and Auto-Acquired Inputs

### 4.1 Required upfront inputs

- Language choice: `zh` or `en` (phase 0)
- `SSH_CMD` only

### 4.2 Must NOT be asked upfront

- `COINXMAN-SSO` cookie
- workstation id (`WORKSTATION_ID` / wallet id)
- `GOOGLE_CODE`

### 4.3 Auto-acquired inputs

- cookie from `get_custody_cookie.py` (primary), manual paste fallback
- workstation list from `GET /api/mpc/wallets/asset?type=0` and interactive selection
- `APP_ID`, `system_rsa` from `GET /api/mpc/api/detail`
- `INSTALL_TYPE` from SGX detection (`1` standard, `2` SGX)

## 5. Canonical Phase Model

### Phase 0: Language selection

- First interaction must be language selection.
- All subsequent prompts and summary should use selected language.

### Phase 1: Remote deploy with mock config

Goal: install co-signer and obtain co-signer RSA public key.

Required behavior:

- Deploy via `scripts/deploy_remote_install.sh`
- Use mock `APP_ID` and mock custody RSA for bootstrap
- Generate secure 24-char alphanumeric password
- Generate custom verify RSA keypair
- Capture co-signer RSA public key from `-show-rsa` output
- Even if `./co-signer` already exists on remote host, compare its reported version to the selected target tag (default latest); only exact match may be reused, otherwise force re-download
- RSA generation success detection must support both legacy and new outputs (e.g. `generate rsa success` or output containing `Co-Signer RSA Public Key` / `BEGIN PUBLIC KEY`)
- Do not start cookie acquisition before phase 1 finishes

### Phase 2: Console API create/update

Goal: obtain real `APP_ID` and real custody `system_rsa` from Console.

Required sequence:

1. Acquire cookie (script first, manual fallback only on failure)
2. Resolve/select workstation id
3. Call `GET /api/mpc/api/detail?wallet_id=<id>`
4. Branch:
   - Create branch if `app_id` is empty
   - Update branch if `app_id` exists
5. For create/update save operation, ask `GOOGLE_CODE` only at submit time
6. After save request, require app approval confirmation before proceeding
7. Re-query detail and verify expected values

### Phase 3: Update runtime with real values

- Update remote `conf/config.yaml` with real `app_id`
- Import real custody RSA via `-custody-pub-import`
- Verify outbound and inbound connectivity
- Start service and run health checks

### Phase 4: Delivery and security banner

- Show plaintext initial password to user
- Show install directory
- Show mandatory security checklist
- Security checklist must include: immediately after password reset, update `withdraw_callback_url` to the real callback URL

## 6. Console API Contract

### 6.1 Endpoints

- `GET /api/mpc/wallets/asset?type=0`
- `GET /api/mpc/api/detail?wallet_id=<id>`
- `POST /api/mpc/api/save`
- `GET /api/mpc/api/cosigner/ping?wallet_id=<id>`

### 6.2 Required headers

All Console API requests must include:

```text
Cookie: COINXMAN-SSO=<value>
build-cu: web
language: en_US
platform: Keysecure
timezone: Asia/Shanghai
```

### 6.3 Save request parameters

Required fields:

- `wallet_id`
- `believe_ips`
- `co_signer_rsa`
- `developer_rsa` (same as `co_signer_rsa`)
- `google_code`

Conditional fields:

- `app_id` for update branch
- `co_signer_url`

### 6.4 Update branch comparison rules

Before calling save in update branch, compare:

- `co_signer_rsa`: exact match
- `co_signer_url`: exact match
- `believe_ips`: containment check for server ip

If any mismatch:

- call save with update payload
- append missing server ip to existing `believe_ips`
- never overwrite existing IP list

If all match:

- skip save
- log API already in sync

### 6.5 Save response handling (mandatory)

- `code == "0"`: request accepted, continue with approval and verification
- `code == "110188"`: pending approval exists, do not resubmit, wait for approval then verify via detail
- `code == "110007"`: invalid/expired google code, ask new code and resubmit
- `code == "110909"`: login timeout, reacquire cookie
- other codes: surface raw response and stop

## 7. Cookie Acquisition Contract

Primary method:

- run `scripts/get_custody_cookie.py --timeout <sec> --qr-path <path>`
- show QR image in chat
- user scans in Custody app
- script extracts HttpOnly `COINXMAN-SSO` via CDP `Network.getCookies`

Constraints:

- cookie name must be `COINXMAN-SSO` (hyphen)
- login wait should use `domcontentloaded` path in script
- do not start cookie flow before phase 1 completes

Fallback:

- ask user to paste cookie manually only if script path fails

## 8. Security and Password Handling

Hard requirements:

- password must never be embedded in SSH command strings
- password-sensitive remote actions must pass password via stdin pipe
- remote startup should not expose password in argv/env/file

Script-level implementation guidance:

- use `scripts/cosigner_remote_ops.py` for start/import/show-rsa/reset flows when password is required
- `-custody-pub-import` may require two password inputs for overwrite confirmation
- always verify password usability before import when applicable

Password delivery:

- plaintext shown once in final output
- encrypted bundle generated as backup reference

## 9. Network Verification and Firewall Rules

Outbound check from co-signer server:

- `curl -s https://openapi.chainup.com/api/ping`

Inbound check through Console:

- `GET /api/mpc/api/cosigner/ping?wallet_id=<id>` with auth cookie

Required network rules:

- inbound: `54.254.7.206 -> 28888`
- outbound: `-> 54.251.87.91:443`

If connectivity checks fail, deployment must stop and present network actions.

## 10. Entry Points

### 10.1 Recommended operational flow

Agent-driven phased execution that follows section 5 (phase 0 to phase 4).

### 10.2 Script entry points

Integrated script:

```bash
bash scripts/deploy_custody_cosigner.sh \
  --ssh-cmd "ssh -l root -p 22 <SERVER_IP>" \
  --cookie "<COINXMAN_SSO_VALUE>" \
  [--workstation-id <WORKSTATION_ID>] \
  [--remote-workdir /data/co-signer]
```

Master orchestrator:

```bash
COINXMAN_SSO="<cookie>" bash orchestrate_deployment.sh \
  --ssh-cmd "ssh -l root -p 22 <SERVER_IP>" \
  [--workstation-id <WORKSTATION_ID>]
```

Note: the strict skill process still requires cookie timing discipline (after phase 1).

## 11. Outputs and Completion Criteria

Deployment is complete only when all are true:

- remote files and config are generated under `<REMOTE_WORKDIR>/mpc-co-signer`
- co-signer RSA public key is captured
- Console API is created/updated and verified
- real `APP_ID` and `system_rsa` are applied to remote runtime
- connectivity and health checks pass
- plaintext initial password is displayed
- install directory and security checklist are displayed

Additional hard gate:

- success banner/log text (for example, "Deployment completed successfully") MUST NOT be emitted before section 6.5 response handling and all verification checks are satisfied.
- if save response requires approval (`trade_no` or `110188`), output must remain in "pending approval" state until post-approval detail verification passes.

## 12. Known Drift and Compatibility Notes

- Some legacy docs mention browser-tool cookie extraction; current primary automated path is `scripts/get_custody_cookie.py`.
- Some legacy command snippets are examples only; production flow must follow phase contract and response-code handling in this spec.
- Header/platform values must follow section 6.2 for Console API calls.
