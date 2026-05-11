# MPC Co-Signer Usage Guide

This document describes the command-line tools and daily usage of the `co-signer` program.

## Command Line Tools

The `co-signer` program has built-in utilities for key management, network diagnostics, and configuration checking.

### Basic Usage

```bash
./co-signer [OPTIONS]
```

### Core Commands

| Option    | Description                                                   |
| --------- | ------------------------------------------------------------- |
| `-server` | Start Co-Signer server mode (usually called via `startup.sh`) |
| `-v`      | Display version information                                   |
| `-h`      | Display help information                                      |

### Key Management Tools

These tools are used to generate, import, and view RSA keys and mnemonics.

#### 1. Generate Co-Signer RSA Key Pair

Generate a new RSA private key.

```bash
./co-signer -rsa-gen
```

#### 2. View RSA Public Key

Display the currently configured RSA public key information.

```bash
./co-signer -show-rsa
```

#### 3. Import Co-Signer RSA Private Key

If you already have an RSA private key in PEM format, you can use this command to import it.

```bash
./co-signer -rsa-pri-import <key_string>
```

#### 4. Import ChainUp Public Key

Import the public key provided by ChainUp to verify messages from the Custody system.

```bash
./co-signer -custody-pub-import <key_string>
```

#### 5. Import Business Public Key

Import the public key used to verify withdrawal signatures.

```bash
./co-signer -verify-sign-pub-import <key_string>
```

### Password Management Tools

#### Change Password

Change the Co-Signer startup password. This re-encrypts all encrypted fields in `keystore.json` with the new password.

```bash
./co-signer -change-password
```

Process:

1. Enter the current password (verifies it can decrypt the existing keystore)
2. Enter the new password
3. Confirm the new password
4. Automatically backs up old `keystore.json` as `keystore.json.bak`
5. Re-encrypts all key data with the new password

> **Note**: After changing the password, use the new password when starting via `startup.sh`.

### Network and Diagnostic Tools

#### 1. Check Configuration

Verify if the configuration items in `config.yaml` and `keystore.json` are complete and correct.

```bash
./co-signer -check-conf
```

#### 2. Network Connectivity Check

Check if the local IP is in the Custody whitelist and verify connectivity with the Custody service.

```bash
./co-signer -check-ip
```

## Common Operation Procedures

### Change Password

Use the built-in command-line tool to change the password:

```bash
./co-signer -change-password
```

After completion, the old `keystore.json` is automatically backed up as `keystore.json.bak`. Use the new password when starting the service next time.

### Update Program

#### Standard Mode

1. Stop the service: `./stop.sh`
2. Back up existing files:
   ```bash
   cp co-signer co-signer.bak
   ```
3. Replace the `co-signer` binary (use the `mpc-co-signer-static-linux` version).
4. Verify configuration:
   ```bash
   ./co-signer -check-conf
   ```
5. Start the service: `./startup.sh`

#### SGX Mode

1. Stop the service: `./stop.sh`
2. Back up existing files:
   ```bash
   cp co-signer co-signer.bak
   ```
3. Download the new binary (use the `mpc-co-signer-linux` non-static version).
4. Re-sign and bundle the SGX Enclave:
   ```bash
   ./sgx-build.sh
   # Enter the binary file name when prompted, e.g.: co-signer
   # Output will be a timestamped file, e.g.: co-signer.20260508143025
   ```
5. Rename the generated file to `co-signer`:
   ```bash
   mv co-signer.20260508143025 co-signer
   ```
6. Verify configuration:
   ```bash
   ./co-signer -check-conf
   ```
7. Start the service: `./startup.sh`

> **Note**: `sgx-build.sh` generates a timestamped binary (e.g., `co-signer.20260508143025`). Use `mv` to rename it to `co-signer` so it matches the file name in `startup.sh`.
