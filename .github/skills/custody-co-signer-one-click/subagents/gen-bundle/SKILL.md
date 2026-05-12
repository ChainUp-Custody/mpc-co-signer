---
name: custody-co-signer-gen-bundle
description: "Generate encrypted secret bundle containing initial password and deployment configuration."
user-invocable: true
---

# Subagent 5: Secret Bundle Generation

## What This Does

Creates an encrypted RSA+AES bundle containing:

- Initial co-signer password
- Deployment configuration
- Generated RSA keys (custom_verify keypair)
- Deployment summary

## Use When

- Deployment is complete
- You need to deliver secrets to customer securely
- You need encrypted artifact for audit trail

## Inputs

```json
{
  "app_id": "b017b99f...",
  "workstation_id": "<WORKSTATION_ID>",
  "install_type": 1,
  "cosigner_password": "...",
  "chainup_public_key": "MIIBIjANBgkq...",
  "co_signer_rsa_public": "-----BEGIN PUBLIC KEY-----...",
  "remote_workdir": "/data/co-signer",
  "cosigner_url": "http://<SERVER_IP>:28888",
  "server_public_ip": "<SERVER_IP>",
  "cosigner_port": 28888,
  "show_rsa_output": "..."
}
```

## Outputs

```json
{
  "status": "success",
  "bundle_dir": "/path/to/.artifacts/custody-co-signer",
  "files": {
    "encrypted_payload": "secret_payload.json.enc",
    "encrypted_aes_key": "secret_payload.aes.key.enc",
    "custom_verify_public": "custom_verify_public.pem",
    "custom_verify_private": "custom_verify_private.pem"
  },
  "decrypt_command": "..."
}
```

## Process

1. **Generate Custom Verify Keypair**
   - RSA 2048-bit key pair (custom*verify*\*)
   - Public key for RSA-encrypted content
   - Private key for customer decryption

2. **Create Payload JSON**
   - Include:
     - `co_signer_initial_password`
     - `app_id`
     - `workstation_id`
     - `co_signer_rsa_public`
     - `cosigner_url`
     - `server_public_ip`
     - `install_type`
     - Console domain and API info

3. **Encrypt Payload**
   - Generate random AES-256 key
   - Encrypt payload with AES-256-CBC
   - Encrypt AES key with RSA public key
   - Delete AES key from disk

4. **Package Output**
   - Create `.artifacts/custody-co-signer/` directory
   - Write all encrypted files
   - Write private key (for customer)
   - Write base64 versions for copy-paste
   - Output decrypt command instructions

5. **Return Bundle Paths**
   - Encrypted payload path
   - Encrypted key path
   - Private key path (customer needs this)
   - Decrypt instructions

## Encryption Details

- **Payload encryption**: AES-256-CBC with PBKDF2
- **Key encryption**: RSA 2048 with OAEP padding
- **Digest**: SHA256 for key derivation

## Files Generated

- `secret_payload.json.enc` - Encrypted deployment config
- `secret_payload.aes.key.enc` - Encrypted AES key
- `custom_verify_private.pem` - Customer's decrypt key
- `custom_verify_public.pem` - For reference

## Decryption Instructions

Provided to customer:

```bash
openssl pkeyutl -decrypt -inkey custom_verify_private.pem \
  -in secret_payload.aes.key.enc -out secret.aes.key \
  -pkeyopt rsa_padding_mode:oaep -pkeyopt rsa_oaep_md:sha256

openssl enc -d -aes-256-cbc -pbkdf2 \
  -in secret_payload.json.enc -out secret_payload.json \
  -pass file:secret.aes.key

cat secret_payload.json
```

## Security

- AES key not persisted to disk
- Private key only given to customer
- Password never in plaintext
- All keys use secure random generation
