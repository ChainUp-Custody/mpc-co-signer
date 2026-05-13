# Custody Co-Signer One-Click Skill (User-Facing Guide)

This README focuses on:

- What the user must provide or operate during deployment
- What the user must do after deployment completes

## What The User Must Provide

Required:

- `SSH_CMD`: full SSH command to the target server (for example: `ssh -l root -p 22 <SERVER_IP>`)

Optional (only if you want non-default behavior):

- `WITHDRAW_CALLBACK_URL`
- `WEB3_CALLBACK_URL`
- `REMOTE_WORKDIR` (default: `/data/co-signer`)

Not required upfront:

- Cookie (`COINXMAN-SSO`)
- Workstation ID
- Google code

## What The User Must Operate During Deployment

The agent automates most actions, but user interaction is still required at specific checkpoints.

1. Choose language

- User selects Chinese or English as the first step.

2. QR login for Custody Console cookie (Phase 2)

- Agent runs `scripts/get_custody_cookie.py` and shows QR image in chat.
- User scans QR in Custody App and completes login.
- Fallback only if script fails: user manually pastes `COINXMAN-SSO` cookie.

3. Select workstation

- Agent fetches workstation list from Console API.
- User chooses the target workstation.

4. Enter Google verification code only at save time

- User provides Custody App `google_code` only when agent is about to call `POST /api/mpc/api/save`.
- Do not provide it early (short validity window).

5. Approve request in Custody App

- After API create/update request is submitted, user must approve in Custody App.
- Agent waits for user confirmation before continuing.

## What The User Must Do After Deployment (Mandatory)

After deployment completes, the user must perform the following ownership-side actions:

1. Change the initial co-signer password immediately

- On server: `cd <install_dir> && ./co-signer -reset-password`

2. Update production callback URL

- Edit `<install_dir>/conf/config.yaml`
- Set `custom_service.withdraw_callback_url` to the real production callback URL.

3. Restart co-signer with the new password

- Run: `./stop.sh` then `./startup.sh`
- Enter the new password interactively when prompted.

4. Remove AI agent SSH access

- Remove the temporary agent public key from `~/.ssh/authorized_keys`.

5. Confirm firewall/network requirements

- Inbound: allow Custody source `54.254.7.206` to co-signer port (default `28888`).
- Outbound: allow co-signer server to reach `54.251.87.91:443`.

6. Complete private-key share/refresh in Custody App

- Open Custody App co-signer management flow and finish key-share/key-refresh requirements.

## Security Notes For Users

- Initial password is sensitive. Rotate it immediately and store it securely.
- Do not keep long-term automation access for deployment identities.
- Keep your custom verify private key and decrypted secrets only in secure secret-management systems.

## Script Entry References

- `scripts/deploy_remote_install.sh` (Phase 1)
- `scripts/get_custody_cookie.py` (Phase 2 cookie)
- `scripts/console_api_ops.py` (Phase 2 Console API)
- `scripts/cosigner_remote_ops.py` (Phase 3 remote ops)
- `scripts/generate_secret_bundle.sh` (Phase 4 secret bundle)

## Triggering Deployment

Use the following command in chat to trigger one-click deployment:

```
@copilot /skill custody-co-signer-one-click Deploy co-signer
```

Or simply describe:

```
I want to deploy ChainUp Custody Co-Signer on server ssh -l root -p 22 <YOUR_SERVER_IP>
```

The agent will automatically guide you through all deployment steps.
