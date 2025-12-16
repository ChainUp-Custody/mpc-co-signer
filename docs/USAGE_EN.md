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

Changing the password directly is currently not supported. If you need to change the password, you need to re-run `install.sh` or manually regenerate `keystore.json`.

### Update Program

1. Stop the service: `./stop.sh`
2. Replace the `co-signer` binary file.
3. Start the service: `./startup.sh`
