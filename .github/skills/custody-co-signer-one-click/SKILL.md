---
name: custody-co-signer-one-click
description: "Fully automatic ChainUp Custody MPC co-signer deployment over SSH. Agent acquires Console cookie via get_custody_cookie.py script (QR code shown in chat for user to scan) with manual-input fallback. Only SSH_CMD is required from the user. Agent derives app_id, custody RSA public key, install type, generates custom verify RSA keys, deploys co-signer, and shows the initial password in plaintext at the end."
argument-hint: "Provide: SSH_CMD only. Cookie and workstation are auto-acquired."
user-invocable: true
---

# Custody Co-Signer One-Click Deploy

## TOP PRIORITY - Mandatory Final Security Checklist (Never Omit)

This section is a hard gate and has the highest priority in this skill.

At deployment completion, the agent MUST always display the following 6-item checklist to the user.
No item may be skipped, merged away, or implied.

Required 5 steps (must be shown explicitly, in order):

1. Immediately change the initial co-signer password on server.
2. Update `withdraw_callback_url` in `conf/config.yaml` to the real production callback URL.
3. Restart co-signer after password/config update (`./stop.sh` then `./startup.sh`).
4. Complete signing private-key share/refresh in Custody App.
5. Remove AI agent SSH access from `~/.ssh/authorized_keys`.

Mandatory wording rule:

- The final completion message must include a dedicated security section that lists all 5 steps.
- If deployment is partially complete, the same 5 steps must still be shown, and remaining blockers must be called out separately.
- The agent must not claim "completed" without showing this 5-step checklist.

## Mandatory Execution Gate

Any agent using this skill must follow these hard rules before taking action:

1. Use only the official scripts in this skill folder for the matching phase:

- Phase 1 deploy: [scripts/deploy_remote_install.sh](./scripts/deploy_remote_install.sh)
- Phase 2 Console API: [scripts/console_api_ops.py](./scripts/console_api_ops.py)
- Phase 3 remote operations: [scripts/cosigner_remote_ops.py](./scripts/cosigner_remote_ops.py)
- Phase 4 bundle: [scripts/generate_secret_bundle.sh](./scripts/generate_secret_bundle.sh)

2. Do not replace an official script with ad-hoc curl, ssh, inline Python, browser automation, or terminal one-liners when the script exists.
3. Before the first substantive action in a phase, restate which official script will be used and what output will be consumed from it.
4. If a tool call drifts off the official-script path, stop that path immediately and restart the phase with the correct script.
5. Never ask the user to remember internal implementation details or compensate for a missing script choice.

These rules are part of the skill contract, not suggestions.

## � ⚠️ Security Notice

**Important**: All examples in this documentation use safe placeholders like `<SERVER_IP>` and `<WORKSTATION_ID>`.

**Never hardcode real server addresses, workstation IDs, or other customer-specific values in code repositories.**

📖 See [SECURITY_NOTICE.md](./SECURITY_NOTICE.md) for detailed security guidelines.

---

## Modular Multi-Agent Architecture

The deployment uses **specialized subagents**, each with small, focused context:

- **Fetch Config** - Query Console API for app_id and RSA key
- **Select Workstation** - List and select from available workstations
- **Detect Env** - Probe SSH target for OS, SGX, version selection
- **Deploy Remote** - Execute SSH installation
- **Gen Bundle** - Generate encrypted secret bundle
- **Verify** - Verify deployment success and readiness

Cookie acquisition is handled by the **agent itself** using `scripts/get_custody_cookie.py` (not a subagent).

For full architecture details, see [AGENTS.md](./AGENTS.md)

---

## What This Skill Does

This skill performs a fully automated ChainUp Custody MPC co-signer deployment. It derives deployment inputs from the custody PC Console and the remote server environment, lets the official installer generate the co-signer transport RSA pair, generates the custom verify RSA key pair and co-signer password, runs the official install flow, and returns an encrypted secret bundle to the user.

## Use When

- You need to deploy or redeploy co-signer quickly on a fresh server.
- You already have the remote SSH command.
- You want the agent to automatically acquire the Console cookie via script (no manual copy-paste).
- You want the agent to automatically list and select workstations from the Console API.
- You want the skill, not the user, to derive `APP_ID`, `CHAINUP_PUBLIC_KEY`, and `INSTALL_TYPE`.
- You want the skill to generate `CUSTOM_VERIFY_PUBLIC_KEY`, the matching private key, and an encrypted output bundle.

## Required Inputs

- **Language / 语言**: Chinese (中文) or English. Asked as the very first interaction. All subsequent agent messages, prompts, and the final security checklist will use the selected language.
- `SSH_CMD`: Full SSH command to the target server. **This is the only other input required from the user upfront.**
- Cookie is **NOT** an upfront input. It must be acquired only when entering **Phase 2**.

## Auto-Acquired (Do NOT ask user upfront)

- **Cookie**: Extracted automatically via script from `custody.chainup.com` **only when Phase 2 begins**. Never ask the user for this upfront.
- **WORKSTATION_ID**: Fetched automatically via `GET /api/mpc/wallets/asset?type=0` and presented as an interactive list for selection.
- **GOOGLE_CODE**: Ask the user **only at the moment** `POST /api/mpc/api/save` is about to be called (it has a 30-second validity window, so asking early is useless).

## Optional Inputs

- `WITHDRAW_CALLBACK_URL`
- `WEB3_CALLBACK_URL`
- `REMOTE_WORKDIR` (default: `/data/co-signer`)
- `COSIGNER_VERSION` (default: auto-detect by OS)

## Cookie Acquisition (Phase 2 Only)

The agent obtains the `COINXMAN-SSO` cookie using **two strategies** (try in order):

Timing rule:

- Do not run cookie acquisition during Phase 0 or Phase 1.
- Start cookie acquisition only after Phase 1 is finished and the flow enters Phase 2.

### Strategy 1: Script-Based Cookie Acquisition (Primary)

The agent uses `./scripts/get_custody_cookie.py` as the only automated cookie acquisition path.

**Procedure:**

1. Run `python .github/skills/custody-co-signer-one-click/scripts/get_custody_cookie.py --timeout <seconds> --qr-path <path>`
2. The script opens login and saves QR screenshot to `--qr-path`
3. Agent displays the QR image in chat via `view_image`
4. User scans QR with Custody App and completes login
5. Script extracts HttpOnly `COINXMAN-SSO` via CDP `Network.getCookies`
6. Cookie obtained → pass to deployment script via `--cookie` parameter

**Key constraints:**

- Automated cookie acquisition must use `get_custody_cookie.py`
- Cookie name is exactly `COINXMAN-SSO`

---

## ⛔ Iron Rules (铁律)

The following rules are **absolute** and must **never** be violated regardless of context:

1. **Cookie 自动获取必须通过脚本 `get_custody_cookie.py`**。脚本负责加载登录页、生成二维码截图，并在登录后通过 CDP `Network.getCookies` 提取 `COINXMAN-SSO`。
2. **QR 码必须展示到聊天窗口**：脚本输出二维码图片路径后，Agent 必须用 `view_image` 展示给用户扫码。
3. **脚本方式失败时才回退到手动输入**：仅当 `get_custody_cookie.py` 失败时，才使用 Strategy 2（让用户手动粘贴 cookie）。
4. **Cookie 名称是 `COINXMAN-SSO`（连字符）**，不是 `COINXMAN_SSO`（下划线）。
5. **Custom Verify RSA 私钥必须在部署完成时展示给用户**，与密码一同输出。
6. **密码绝不能出现在命令行参数中**：在 SSH 命令、终端命令、`ps` 输出中均不得出现明文密码。Agent 执行需要密码的远程操作（如 `-server`、`-custody-pub-import`、`-verify-sign-pub-import`、`-show-rsa`）时，必须使用 Python `subprocess` 通过 `stdin` 管道传递密码，而非将密码嵌入 SSH 命令字符串。示例：
   ```python
   # CORRECT: password via stdin
   subprocess.run(SSH_CMD + [remote_script], input=password + "\n", ...)
   # WRONG: password in command string
   ssh ... 'printf "%s\n" "THE_PASSWORD" | ./co-signer -server'
   ```

---

### Strategy 2: User Manual Input (Fallback)

If `get_custody_cookie.py` is unavailable or fails:

1. Agent asks the user to open `https://custody.chainup.com/login` in their own browser
2. User logs in (scan QR code)
3. User opens DevTools → Application → Cookies → `https://custody.chainup.com`
4. User copies the `COINXMAN-SSO` value and pastes it into the chat
5. Agent uses the provided value

**After cookie is obtained** (either strategy), all remaining Console operations use **authenticated API requests only** — no further browser automation.

## Security Model (v2.1)

✅ **Password NOT Stored on Server**

- No `/root/.co-signer/password` file created
- Password only exists in encrypted secret bundle
- Customer receives encrypted password in RSA+AES bundle
- Customer decrypts locally to get plaintext password

✅ **Password Delivery**

- Generated: 24-character alphanumeric (strong entropy)
- Encrypted: AES-256-CBC (with PBKDF2 key derivation)
- Wrapped: RSA-2048-OAEP to customer's public key
- Returned: Encrypted files in artifact bundle

✅ **Startup Method (TTY Interactive)**

- No password in argv, environment, or files
- Server expects TTY for interactive hidden prompt
- Customer manually enters password at each startup: `./startup.sh`
- Password never logged or echoed

✅ **Password Delivery to Customer**

- Never in: argv, environment variables, log files, server files
- **DO** display plaintext password at end of deployment with a highlighted security banner
- The banner instructs the customer to: (1) change the password on server, (2) remove agent SSH access, (3) refresh private keys in the App
- Also stored in: encrypted bundle (RSA+AES) as backup reference

## Procedure

### Phase 0 to Phase 4 Control Rules

The agent must execute the phases in order and may not skip the phase boundary checks:

- Phase 1 ends only after the remote install script output has been parsed and the co-signer RSA public key has been captured.
- Phase 2 starts only after Phase 1 is complete. Cookie acquisition and Console API calls are forbidden before this boundary.
- Phase 2 uses only [scripts/console_api_ops.py](./scripts/console_api_ops.py) for detail/save/list operations.
- Phase 3 starts only after the real APPID and system_rsa are known from Phase 2.
- Phase 3 uses only [scripts/cosigner_remote_ops.py](./scripts/cosigner_remote_ops.py) for password-bearing remote operations.
- Phase 4 starts only after Phase 3 validation succeeds.

If any boundary is not satisfied, the agent must stop and resolve that specific prerequisite instead of improvising.

### Phase 0: Language Selection (语言选择)

0. As the **very first interaction**, present a language choice to the user:
   - Option 1: **中文** (Chinese)
   - Option 2: **English**
   - Use `vscode_askQuestions` with two options. Default to 中文.
   - All subsequent agent messages, prompts, error messages, progress updates, and the final security checklist MUST use the selected language.
   - Store the choice as `LANG` (`zh` or `en`) and reference it throughout the deployment.

### Phase 1: Deploy Co-Signer with Mock Config (Get Co-Signer RSA Public Key)

1. Probe the remote server through `SSH_CMD` and auto-detect `INSTALL_TYPE` plus binary compatibility.
   - Use `2` only when SGX capability is actually present; otherwise use `1`.
   - Always use the latest version regardless of OS.

- Pre-download the selected binary before installation.
- If `./co-signer` already exists, it must still pass a version check against the selected target tag (default latest). Reuse only on exact match; otherwise force re-download.

2. Generate a random 24-character alphanumeric `COSIGNER_PASSWORD` with high entropy.
   - Password is NOT stored on server — only in encrypted bundle for customer delivery.
   - Startup script requires TTY interaction: customer enters password manually each startup.
3. Generate a new RSA key pair for the custom verify flow.
   - Use the generated public key as `CUSTOM_VERIFY_PUBLIC_KEY`.
4. Run [remote deploy script](./scripts/deploy_remote_install.sh) with **mock values**:
   - `APP_ID`: a placeholder hex string (e.g. `ef47f658d436c2f081a69195077d7006`)
   - `CHAINUP_PUBLIC_KEY`: a placeholder RSA public key
   - `WITHDRAW_CALLBACK_URL`: empty
   - `WEB3_CALLBACK_URL`: empty
   - The script generates the co-signer transport RSA pair via `-rsa-gen`.
   - Capture co-signer RSA public key from `./co-signer -show-rsa` output (`SHOW_RSA_OUTPUT_B64`).
   - Deploy `startup.sh` (TTY-only) and `stop.sh` scripts.
5. Extract the **Co-Signer RSA Public Key** from deployment output — this is needed for Phase 2.

### Phase 2: Create or Update API on Custody Console (Using Co-Signer RSA Public Key)

6. Obtain the `COINXMAN-SSO` cookie via `get_custody_cookie.py` or manual input (see Cookie Acquisition section).

- Timing requirement: this is the first point in the procedure where cookie acquisition is allowed.

7. Call `GET /api/mpc/api/detail?wallet_id=<WORKSTATION_ID>` to check if an API already exists.
8. **If API does NOT exist** (`app_id` is empty) → **Create branch**:
   a. Create a new API via `POST /api/mpc/api/save` with:
   - `wallet_id`: workstation ID
   - `believe_ips`: co-signer server's public IP (merged with default `54.254.7.206`)
   - `co_signer_url`: `http://<SERVER_IP>:28888`
   - `co_signer_rsa`: the key extracted in Phase 1 step 5
   - `developer_rsa`: same as `co_signer_rsa`
   - `google_code`: ask user **at this moment only** (30s validity)
     b. Submit triggers approval workflow.
     c. **Prompt user to approve in APP**: Tell the user the API creation request has been submitted and the wallet owner must open the Custody APP to approve it. Use `vscode_askQuestions` to wait for user confirmation (options: "Approved" / "Rejected"). Do NOT proceed until the user confirms approval.
     d. After user confirms approval, call `GET /api/mpc/api/detail?wallet_id=<ID>` to verify the API was created and extract the real **APPID**.
9. **If API already exists** (`app_id` is non-empty) → **Update branch**:
   a. Retrieve current values from Console API response: `co_signer_rsa`, `believe_ips`, `co_signer_url`.
   b. Get current co-signer RSA public key from server: `./co-signer -show-rsa` on the remote host.
   c. **Compare** each field:
   - **co_signer_rsa**: Console value vs. current server `./co-signer -show-rsa` output → exact match
   - **believe_ips**: check if server's public IP is **contained** in Console's comma-separated list (containment check, NOT exact match)
   - **co_signer_url**: Console value vs. `http://<SERVER_IP>:28888` → exact match
     d. If **any field differs or IP not contained**, call `POST /api/mpc/api/save` with:
   - `app_id`: the existing app_id (required for update)
   - `wallet_id`: workstation ID
   - `co_signer_rsa` / `developer_rsa`: current server RSA
   - `believe_ips`: **append** server IP to existing list if not already present (preserve all existing IPs, comma-separated). **Never overwrite** — only append missing IPs at the end.
   - `co_signer_url`: `http://<SERVER_IP>:28888`
   - `google_code`: ask user **at this moment only**
     e. **Prompt user to approve in APP**: Tell the user the API update request has been submitted and the wallet owner must open the Custody APP to approve it. Use `vscode_askQuestions` to wait for user confirmation (options: "Approved" / "Rejected"). Do NOT proceed until the user confirms approval.
     f. After user confirms approval, call `GET /api/mpc/api/detail?wallet_id=<ID>` to verify the updated fields (especially `co_signer_rsa`) match the expected values.
     g. If **all fields match** (RSA equal, URL equal, server IP already in believe_ips), skip update — log that API config is already in sync.
10. From the API detail response, obtain the **ChainUp RSA Public Key** (`system_rsa`) — this is the real Custody RSA public key needed for Phase 3.

### Phase 3: Update Co-Signer with Real Config

11. Update `conf/config.yaml` on the co-signer server with real values:
    - `app_id`: the real APPID from Phase 2 step 9
    - `withdraw_callback_url`: the real callback URL (if provided by user)
    - `web3_callback_url`: the real web3 callback URL (if provided)
    - These are simple `sed` replacements in the config file.
12. Import the real ChainUp RSA public key via [cosigner_remote_ops.py](./scripts/cosigner_remote_ops.py):
    ```bash
    python scripts/cosigner_remote_ops.py --ssh-cmd "$SSH_CMD" --action import-custody-pub \
        --password "$PASSWORD" --pub-key "$REAL_CHAINUP_PUBLIC_KEY"
    ```
    **Iron Rule**: Password is passed via Python `subprocess.run(input=...)` stdin pipe — NEVER in SSH command string.
13. Verify network connectivity from the co-signer server:
    - **Outbound test** (co-signer → OpenAPI):
      ```bash
      curl -s https://openapi.chainup.com/api/ping
      ```
      Expected: returns a JSON response confirming connectivity.
    - **Inbound test** (Custody → co-signer):
      ```bash
      curl -s -H "Cookie: COINXMAN-SSO=$COOKIE" \
        "https://custody.chainup.com/api/mpc/api/cosigner/ping?wallet_id=$WORKSTATION_ID"
      ```
      Expected: Custody server calls the co-signer's ping endpoint. If this fails, firewall rules need adjustment.
    - If either test fails, display the required firewall rules and stop.
14. **Clean up deployment processes** via [cosigner_remote_ops.py](./scripts/cosigner_remote_ops.py):

    ```bash
    python scripts/cosigner_remote_ops.py --ssh-cmd "$SSH_CMD" --action stop \
        --workdir "$REMOTE_WORKDIR/mpc-co-signer"
    ```

    All co-signer processes started during Phase 1 (for `-rsa-gen`, `-show-rsa`, `-custody-pub-import`) **must be killed** before deployment is declared complete. The customer will start the service manually with `./startup.sh` when ready.

    ⚠️ **Mandatory**: This step must run even if no co-signer process appears to be running. It is a hard gate before the success banner.

15. Package secret output with [bundle script](./scripts/generate_secret_bundle.sh).
    - Payload is built **entirely in memory** — never written to disk as plaintext.
    - Encrypt with `CUSTOM_VERIFY_PUBLIC_KEY`, return ciphertext + keys + co-signer RSA summary.

### Phase 4: Display Password & Security Checklist

16. Display the plaintext password to the user with a highlighted security banner.
17. Display the **安装目录路径** (e.g. `/data/co-signer/mpc-co-signer`) so the customer knows where all co-signer files are located.

**Post-deployment security checklist** (display to user):

1. **立即修改密码** — SSH 到 co-signer 服务器，进入安装目录，使用 `./co-signer -reset-password` 修改初始密码为自定义强密码。
2. **修改 `withdraw_callback_url` 为真实回调地址** — 编辑安装目录下 `conf/config.yaml`，将 `custom_service.withdraw_callback_url` 改为生产可用的真实回调 URL。
3. **修改密码后立即重启 Co-Signer** — 在安装目录执行 `./stop.sh` 然后 `./startup.sh`，输入新密码启动服务。
4. **配置网络防火墙并验证连通性**
   - 防火墙规则: 入站 `54.254.7.206 → 28888`，出站 `→ 54.251.87.91:443`
5. **在 Custody APP 分享签名私钥** — 进入 Custody APP → Co-Signer 管理界面，完成签名私钥分享。参考: [Co-Signer FAQ](https://custodydocs-en.chainup.com/user-guide/mpc-wallet/api-integration/co-signer#frequently-asked-questions)
6. **删除 AI Agent 的 SSH 权限** — 从服务器 `~/.ssh/authorized_keys` 中移除 agent 使用的 SSH 公钥。

**Output template** (agent MUST display at end):

```
════════════════════════════════════════════════════════════
  Co-Signer 部署完成
════════════════════════════════════════════════════════════

安装目录: <REMOTE_WORKDIR>/mpc-co-signer
  (例: /data/co-signer/mpc-co-signer)

APPID:          <REAL_APP_ID>
Co-Signer 地址: http://<SERVER_IP>:28888
服务器:         <SERVER_IP>

初始密码: <PASSWORD>

⚠️ 安全操作清单:
1. **立即修改密码** — SSH 到 co-signer 服务器，进入安装目录，使用 `./co-signer -reset-password` 修改初始密码为自定义强密码。
2. **修改 `withdraw_callback_url` 为真实回调地址** — 编辑安装目录下 `conf/config.yaml`，将 `custom_service.withdraw_callback_url` 改为生产可用的真实回调 URL。
3. **修改密码后立即重启 Co-Signer** — 在安装目录执行 `./stop.sh` 然后 `./startup.sh`，输入新密码启动服务。
4. **配置网络防火墙并验证连通性**
   - 防火墙规则: 入站 `54.254.7.206 → 28888`，出站 `→ 54.251.87.91:443`
5. **在 Custody APP 分享签名私钥** — 进入 Custody APP → Co-Signer 管理界面，完成签名私钥分享。参考: [Co-Signer FAQ](https://custodydocs-en.chainup.com/user-guide/mpc-wallet/api-integration/co-signer#frequently-asked-questions)
6. **删除 AI Agent 的 SSH 权限** — 从服务器 `~/.ssh/authorized_keys` 中移除 agent 使用的 SSH 公钥。
════════════════════════════════════════════════════════════
```

## Scripts Reference

All scripts are in `./scripts/` — agent MUST use these instead of ad-hoc inline commands.

| Script                                                           | Purpose                                                         | Key Arguments                                                              |
| ---------------------------------------------------------------- | --------------------------------------------------------------- | -------------------------------------------------------------------------- |
| [deploy_remote_install.sh](./scripts/deploy_remote_install.sh)   | Phase 1: Remote deploy co-signer binary, config, RSA keypair    | `SSH_CMD`, `APP_ID`, `CHAINUP_PUBLIC_KEY`, `INSTALL_TYPE`, etc. (env vars) |
| [get_custody_cookie.py](./scripts/get_custody_cookie.py)         | Phase 2: Headless Playwright QR login → extract `COINXMAN-SSO`  | `--timeout`, `--qr-path`                                                   |
| [console_api_ops.py](./scripts/console_api_ops.py)               | Phase 2: Console API operations (detail/save/list)              | `--cookie`, `--action`, `--wallet-id`, etc.                                |
| [cosigner_remote_ops.py](./scripts/cosigner_remote_ops.py)       | Phase 3: Remote co-signer operations (start/stop/import/health) | `--ssh-cmd`, `--action`, `--password` (via stdin)                          |
| [generate_secret_bundle.sh](./scripts/generate_secret_bundle.sh) | Phase 4: Generate encrypted secret bundle                       | env vars for payload fields                                                |

**Critical**: `cosigner_remote_ops.py` passes password through `subprocess.run(input=...)` stdin pipe. Agent MUST use this script for any operation requiring the password — never pass password in SSH command strings.

## Console API Submission Contract

- The deployment follows a **3-phase flow**: deploy with mock → create API on Console → update co-signer with real config.
- Phase 1 uses mock `APP_ID` and `CHAINUP_PUBLIC_KEY` to deploy co-signer and obtain its RSA public key.
- Phase 2 first queries `GET /api/mpc/api/detail?wallet_id=<ID>` to check if an API already exists.
  - **API does not exist**: create via `POST /api/mpc/api/save` with co-signer RSA, IP, URL → prompt user to approve in Custody APP → extract real `APPID` and `ChainUp RSA Public Key` after approval confirmed.
  - **API already exists**: compare Console config against current server state: `co_signer_rsa` (exact match vs `./co-signer -show-rsa`), `believe_ips` (containment check — is server IP already in the comma-separated list?), `co_signer_url` (exact match). If any mismatch → update via `POST /api/mpc/api/save` with existing `app_id` → prompt user to approve in Custody APP → verify updated fields via `GET /api/mpc/api/detail`. For `believe_ips`, **append** missing IPs at the end, never overwrite existing entries. If all match → skip update.
- Phase 3 updates the co-signer config file (`sed` for `app_id`, callback URLs) and imports the real ChainUp RSA public key via `./co-signer -custody-pub-import`.
- Network connectivity verification:
  - Outbound: `curl -s https://openapi.chainup.com/api/ping` from co-signer server
  - Inbound: `curl -s "https://custody.chainup.com/api/mpc/api/cosigner/ping?wallet_id=<WORKSTATION_ID>"` with cookie auth

## Execution Contract

```bash
# Cookie is obtained by agent only when entering Phase 2,
# via get_custody_cookie.py script (Strategy 1) or manual user input (Strategy 2),
# then passed via --cookie parameter.
export SSH_CMD='ssh user@host'
export WORKSTATION_ID='your_workstation_id'
export WITHDRAW_CALLBACK_URL=''
export WEB3_CALLBACK_URL=''
export REMOTE_WORKDIR='/data/co-signer'

# The skill derives APP_ID, CHAINUP_PUBLIC_KEY, INSTALL_TYPE,
# COSIGNER_PASSWORD, and CUSTOM_VERIFY_PUBLIC_KEY automatically.
```

## Required Agent Behavior

### Input Acquisition (CRITICAL)

- **Language**: Ask the user to choose 中文 or English as the **very first question** (Phase 0). All subsequent interactions use the selected language.
- **SSH_CMD**: Ask for SSH command immediately after language selection.
- **Cookie**: Run `get_custody_cookie.py` to generate QR and extract `COINXMAN-SSO`. If script-based acquisition fails, ask user to paste cookie manually. **Never ask for cookie upfront without first trying the script.** Cookie is needed in Phase 2, NOT Phase 1.
- **Cookie timing hard rule**: Do not trigger QR login or request manual cookie input before Phase 1 deployment completes. Cookie acquisition starts only at Phase 2 entry.
- **Workstation ID**: After obtaining the cookie, navigate to the wallet list and let the user select. **Never ask for workstation ID upfront.**
- **GOOGLE_CODE**: Ask the user for this **only immediately before** the API creation confirmation dialog. Never ask earlier as codes expire in ~30 seconds.

### Deployment Flow (3-Phase)

- **Phase 1**: Deploy co-signer with mock `APP_ID` and mock `CHAINUP_PUBLIC_KEY`. The goal is to get the co-signer RSA public key. No cookie or Console access needed.
- **Phase 2**: Query Console API to check if API exists. If not, create via `POST /api/mpc/api/save`. If exists, compare `co_signer_rsa` (exact), `believe_ips` (containment — is server IP in list?), `co_signer_url` (exact) against current server state — update only if any mismatch. For `believe_ips`, append missing IPs, never overwrite. After save returns `code: "0"`, prompt user to approve in Custody APP via `vscode_askQuestions`, then verify via `GET /api/mpc/api/detail`. Extract real APPID and ChainUp RSA public key.
- **Phase 3**: SSH to co-signer server, update `conf/config.yaml` with real `app_id` (via `sed`), import real ChainUp RSA public key (via `./co-signer -custody-pub-import`). Then verify network connectivity.

### API Behavior

- Use `GET /api/mpc/api/detail?wallet_id=<ID>` to check existing API config before any create/update.
- **Create**: `POST /api/mpc/api/save` without `app_id` → triggers approval workflow (Google code + Custody APP approval).
- **Update**: `POST /api/mpc/api/save` with existing `app_id` → triggers approval workflow. Only call when at least one field mismatches: `co_signer_rsa` (exact), `co_signer_url` (exact), or `believe_ips` (server IP not contained in existing list). For `believe_ips`, always **append** missing IPs to the end of the existing comma-separated list — never overwrite.
- **Skip**: If all fields match server state, do NOT call save — log "API config already in sync".
- **Approval**: Both create and update require APP approval. After `POST /api/mpc/api/save` returns `code: "0"`, the agent MUST prompt the user to approve in the Custody APP using `vscode_askQuestions`, then verify via `GET /api/mpc/api/detail` that changes took effect.
- After approval, real APPID is visible in the API detail response.
- If approval requires other workspace members, stop and tell the user to get approval.

### API Response Handling (CRITICAL — do NOT blindly re-submit)

After `POST /api/mpc/api/save`, **always diagnose the response code** before deciding next action:

| Response Code | Meaning                                              | Correct Action                                                                                                                                                                                                |
| ------------- | ---------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `"0"`         | Success                                              | Proceed to next step                                                                                                                                                                                          |
| `"110188"`    | 有未完成的审批单 (uncompleted approval order exists) | Request **was already submitted** and entered approval queue. Do **NOT** re-submit or ask for new google_code. Wait for the wallet owner to complete approval, then call `GET /api/mpc/api/detail` to verify. |
| `"110007"`    | Google code error or reuse                           | Code expired (30s validity). Ask user for a **new** google_code and re-submit.                                                                                                                                |
| `"110909"`    | Login timeout                                        | Cookie expired. Re-acquire cookie via Playwright.                                                                                                                                                             |
| Other         | Unknown error                                        | Display raw response and stop.                                                                                                                                                                                |

**Rule**: Never assume a non-zero response means "retry with new google_code". Each error code requires a different action.

### Success Banner Gate (MANDATORY)

The deployment script/agent MUST NOT print or claim "deployment completed successfully" unless all conditions below are true in the latest verification step:

1. `GET /api/mpc/api/detail` returns `code: "0"`.
2. Console `co_signer_rsa` is exactly equal to the current server `./co-signer -show-rsa` Co-Signer RSA (after whitespace/PEM wrapper normalization).
3. Console `co_signer_url` exactly matches `http://<SERVER_IP>:<PORT>`.
4. Console `believe_ips` contains `<SERVER_IP>`.
5. For create/bootstrap path, Console `app_id` and `system_rsa` are both non-empty after approval.

If any check fails, stop with an error and remediation hint. Do not print password success banner as final success.

### Network Verification

- After Phase 3 config update, verify connectivity:
  - Outbound from co-signer server: `curl -s https://openapi.chainup.com/api/ping`
  - Inbound via Custody: `curl -s -H "Cookie: COINXMAN-SSO=$COOKIE" "https://custody.chainup.com/api/mpc/api/cosigner/ping?wallet_id=$WORKSTATION_ID"`
- If tests fail, display required firewall rules and stop.

### Deployment Behavior

- Use terminal tools only for server inspection, key generation, packaging, and deployment.
- If a required endpoint is undocumented, stop and surface the missing API requirement — do not invent browser fallbacks.

### Password Handling (CRITICAL)

- Generate password **in memory only** — never pass via argv, env vars, or files.
- Build the secret bundle payload **via process substitution** (never write plaintext to a temp file).

### Bundle Output

- Return: `CUSTOM_VERIFY_PUBLIC_KEY`, matching private key PEM, encrypted AES key, encrypted payload (base64), co-signer RSA public key, derived co-signer URL, server IP, one-line decrypt command.

## Customer Remaining Actions

After deployment, the customer must complete these ownership-side controls:

1. **立即修改密码** — 使用 `./co-signer -reset-password` 修改初始密码
2. **修改 `withdraw_callback_url` 为真实回调地址** — 编辑 `conf/config.yaml` 的 `custom_service.withdraw_callback_url`
3. **重启 Co-Signer** — `./stop.sh` → `./startup.sh`（输入新密码）
4. **配置并验证网络防火墙**:
   - 入站: co-signer 端口 (默认 `28888`) 允许 Custody 源 `54.254.7.206` 访问
   - 出站: co-signer 服务器允许访问 Custody `54.251.87.91:443`
   - source: https://custodydocs-zh.chainup.com/api-references/mpc-apis/co-signer/deploy#iv-co-signer
5. **在 Custody APP 分享签名私钥** — Co-Signer 管理界面完成私钥分享
   - 参考: https://custodydocs-en.chainup.com/user-guide/mpc-wallet/api-integration/co-signer#frequently-asked-questions
6. **删除 AI Agent 的 SSH 权限** — 从 `~/.ssh/authorized_keys` 移除 agent SSH 公钥

- **Password management (IMPORTANT)**:
  - Password is generated and encrypted, delivered to customer via the secret bundle
  - Password is NOT stored in any file on the deployment server (e.g., no /root/.co-signer/password)
  - Customer must manage and store the password securely on their side
  - Each startup requires customer to manually enter the password (TTY interactive prompt)
  - This prevents accidental exposure or theft of the startup password from server files
  - For automated restarts, customer should implement their own secure password management (e.g., HashiCorp Vault, AWS Secrets Manager)
- Customer system RSA integration expectation:
  - configure SDK crypto with customer key material used for request protection and transaction signature generation
  - ensure `signPrivateKey` is configured when withdrawal `sign` is required
  - see Java SDK reference:
    - https://github.com/HiCoinCom/java-sdk/blob/main/src/main/java/com/github/hicoincom/api/mpc/impl/WithdrawApi.java#L40C61-L40C82

## Scripts and Tools

### New Scripts (Improvements)

#### 1. **`deploy_custody_cosigner.sh`** - Integrated Orchestration (RECOMMENDED)

Combines all steps into one seamless workflow:

```bash
./deploy_custody_cosigner.sh \
  --ssh-cmd "ssh -l root -p 22 <SERVER_IP>" \
  --cookie "<COINXMAN_SSO_VALUE>" \
  --workstation-id <WORKSTATION_ID>
```

**Features:**

- Accepts pre-acquired COINXMAN-SSO cookie (via `--cookie`)
- Fetches Console configuration (app_id, system_rsa, etc.)
- Runs full deployment
- Provides post-deployment instructions

**Options:**

- `--ssh-cmd CMD` - SSH command to target server (required)
- `--cookie VALUE` - COINXMAN-SSO cookie value (required, obtained by agent via browser tools)
- `--workstation-id ID` - Workstation ID (prompted if not provided)
- `--remote-workdir PATH` - Deployment directory (default: /data/co-signer)

#### 2. **`stop.sh`** - Service Termination (Generated on Deploy)

Auto-generated on each deployment in the co-signer directory:

```bash
# On remote server:
cd /data/co-signer/mpc-co-signer
./stop.sh
```

**Actions:**

- Gracefully stops co-signer process with `pkill -x co-signer`
- Force-kills if still running after 1 second (`pkill -9`)
- Displays last 20 log lines from nohup.out

#### 3. **`startup.sh`** - Service Startup (Generated on Deploy, Fixed Template)

Auto-generated on each deployment with the **mandatory fixed template** below. Do NOT alter the template.

```bash
#!/bin/bash -e

project_path=$(
    cd $(dirname $0)
    pwd
)

STR_PASSWORD=""
echo -n "Please enter your password:"
stty -echo
read STR_PASSWORD
stty echo


if [ ! -n "$STR_PASSWORD" ]; then
    echo "Password cannot be null"
    exit 1
fi

echo ""
echo "Startup Program..."
echo ""

# start
echo ${STR_PASSWORD} | nohup ${project_path}/co-signer -server >>nohup.out 2>&1 &
```

Customer runs `./startup.sh` interactively and enters the password at the prompt.

### Existing Scripts (Core Deployment)

#### **`deploy_remote_install.sh`** - Low-level Remote Deployment

Called by orchestration scripts. Environment variables:

```bash
SSH_CMD="ssh ..."
APP_ID="..."
CHAINUP_PUBLIC_KEY="..."
INSTALL_TYPE="1"              # 1=standard, 2=SGX
COSIGNER_PASSWORD="..."       # auto-generated if omitted
COSIGNER_VERSION="latest"     # auto-detected if omitted
REMOTE_WORKDIR="/data/co-signer"
# ... more options
```

#### **`generate_secret_bundle.sh`** - Encrypted Output Packaging

Generates encrypted secrets bundle:

```bash
PAYLOAD_JSON='{"key":"value"}'
CUSTOM_VERIFY_PUBLIC_KEY="..."
BUNDLE_DIR=".artifacts"
bash generate_secret_bundle.sh
```

## Password Management Best Practices

**Security Model: Password NOT Stored on Server**

The password is generated and encrypted for delivery to the customer, but NOT persisted on the deployment server.

**Initial Deployment:**

1. ✅ 24-character strong password auto-generated
2. ✅ Password encrypted and delivered in the secret bundle (encrypted_payload.json.enc)
3. ✅ Password NOT stored on server file system
4. ✅ Password NOT exposed in startup commands or argv
5. ✅ Startup script displays TTY prompt: "Enter co-signer password:"

**Customer Password Management:**

1. Decrypt the secret bundle using your RSA private key to obtain the password:

   ```bash
   openssl pkeyutl -decrypt -inkey custom_verify_private.pem -in secret_payload.aes.key.enc -out secret.aes.key -pkeyopt rsa_padding_mode:oaep -pkeyopt rsa_oaep_md:sha256
   openssl enc -d -aes-256-cbc -pbkdf2 -in secret_payload.json.enc -out secret_payload.json -pass file:secret.aes.key
   ```

2. Extract the password from `secret_payload.json` (field: `co_signer_initial_password`)

3. Store the password securely on your side (e.g., password manager, vault, etc.)

**Startup Procedure:**

Each time you need to start co-signer:

```bash
ssh root@<server>
cd /data/co-signer/mpc-co-signer
./startup.sh
# Enter your password when prompted (hidden input)
```

**For Automated Restarts:**

If you need automated startups without manual TTY input, implement your own secure password management:

- HashiCorp Vault
- AWS Secrets Manager
- Azure Key Vault
- Encrypted config files with automated unlock

Then create a wrapper script that retrieves the password and pipes it securely to ./startup.sh.

## References

- [runbook](./references/runbook.md)
