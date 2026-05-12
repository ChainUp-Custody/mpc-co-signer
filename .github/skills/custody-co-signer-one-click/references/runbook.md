# Custody Co-Signer Deployment Runbook

## Scope

This runbook supports fully automatic deployment of ChainUp Custody mpc-co-signer with official `install.sh`, using only `SSH_CMD`, custody PC Console `COOKIE`, and `WORKSTATION_ID` as required operator inputs.

## Environment Baseline

- OS: Ubuntu 22.04 (recommended)
- CPU: AMD64 or ARM64, 8 cores
- Memory: 64GB
- Disk: 256GB

## Automated Flow

1. Gather operator inputs:

- `SSH_CMD`
- `COOKIE`
- `WORKSTATION_ID`

2. Extract custody-side inputs from PC Console:

- `APP_ID`
- `CHAINUP_PUBLIC_KEY`

3. Detect remote install mode from server environment:

- choose `2` only if SGX devices or SGX runtime support are actually present
- otherwise choose `1`

4. Select a compatible co-signer version before running `install.sh`:

- pre-download the chosen binary to `./co-signer` so upstream `install.sh` reuses it

5. Generate local secret material:

- 16-character `COSIGNER_PASSWORD`
- RSA key pair for `CUSTOM_VERIFY_PUBLIC_KEY`

6. Run:

```bash
bash ./.github/skills/custody-co-signer-one-click/scripts/deploy_remote_install.sh
```

7. Export post-install public-key state:

- run `./co-signer -show-rsa`
- capture the generated co-signer RSA public key so it can be written back into PC Console

8. Package delivery bundle:

```bash
bash ./.github/skills/custody-co-signer-one-click/scripts/generate_secret_bundle.sh
```

## Validation Checklist

- `ps -ef | grep 'co-signer -server' | grep -v grep` returns running process.
- Port is listening (`28888` by default).
- `nohup.out` has no repeated fatal errors.
- `./co-signer -show-rsa` can show the configured public keys.
- Generated encrypted bundle includes:
  - RSA private key PEM
  - RSA public key PEM
  - AES-encrypted payload
  - RSA-encrypted AES key
  - generated co-signer RSA public-key summary

## Network Rules

According to official CN deployment docs (section IV):

- 入网: allow source `54.254.7.206` to co-signer listening port (default `28888`).
- 出网: allow destination `54.251.87.91:443`.
- Source:
  - https://custodydocs-zh.chainup.com/api-references/mpc-apis/co-signer/deploy#iv-co-signer

## Post-Deploy Initialization

- Co-signer process startup alone is not the final state.
- Complete initialization in custody console by automation, not manual entry:
  - submit co-signer RSA public key from `./co-signer -show-rsa`
  - submit co-signer URL from `DERIVED_COSIGNER_URL`
  - submit whitelist data including server IP and custody-required connectivity values
  - perform private key refresh
- Use the authenticated Console cookie to call documented API endpoints for all of these actions.
- Only fallback to user intervention when blocked by captcha/MFA/approval gate or explicit `trade_no` approval.

## Customer Remaining Work

- These items remain customer-owned after skill automation:
  - network firewall opening between custody and co-signer environments
  - startup password custody under customer key management
  - customer application RSA key integration for withdrawal request protection

### 1) Firewall Opening

- Verify security-group/firewall policy is active and persistent:
  - 入网 allow `54.254.7.206` to co-signer service port (default `28888`)
  - 出网 allow access to `54.251.87.91:443`

### 2) Startup Password Protected by RSA

- Treat generated co-signer startup password as high-sensitivity secret.
- Recommended control:
  - store only ciphertext (RSA/KMS encrypted)
  - decrypt in memory at service start
  - pipe plaintext to process stdin, then immediately clear shell variables

### 3) Customer-System RSA Integration for Withdraw

- Customer app must configure its own RSA/sign key material in SDK crypto implementation.
- In Java SDK, withdrawal with transaction-sign mode requires `signPrivateKey`; otherwise request construction fails.
- Reference implementation:
  - https://github.com/HiCoinCom/java-sdk/blob/main/src/main/java/com/github/hicoincom/api/mpc/impl/WithdrawApi.java#L40C61-L40C82

## About Cookie and Workstation ID

- If user supplies `COOKIE` and `WORKSTATION_ID`, use them only for authenticated console/API steps.
- Do not expose cookie values in logs.
- If an endpoint is undocumented, do not guess and do not switch to browser-guided completion; stop and surface the missing API requirement.

## About Custom Verify Keys and Encrypted Output

- `CUSTOM_VERIFY_PUBLIC_KEY` is the public key imported with `-verify-sign-pub-import`.
- The skill should generate the matching RSA private key at deploy time.
- The encrypted output bundle should contain secret deployment material such as:
  - generated co-signer startup password
  - derived app id used for deployment
  - remote workdir and mode summary
  - generated co-signer RSA public-key summary from `./co-signer -show-rsa`
- Prefer hybrid encryption:
  - encrypt payload with a random AES key
  - encrypt the AES key with `CUSTOM_VERIFY_PUBLIC_KEY`

## Official Sources

- Deployment doc:
  - https://custodydocs-en.chainup.com/api-references/mpc-apis/co-signer/deploy
- PC Console:
  - https://custody.chainup.com/mpc/wallet
- Official program and script:
  - https://github.com/ChainUp-Custody/mpc-co-signer
