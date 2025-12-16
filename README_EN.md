# MPC Co-Signer

English | [中文](README.md)

MPC Co-Signer is a co-signing service program provided by ChainUp Custody to ensure asset security. It is deployed in the client's private environment and works with the ChainUp Custody system to complete transaction co-signing.

## Features

- **Private Key Shard Management**: Client private key shards are encrypted and stored locally to ensure asset control.
- **Co-Signing**: Participates in MPC signature computation to complete transaction signing without requiring the full private key.
- **SGX Security**: Supports Intel SGX (Software Guard Extensions) deployment, providing hardware-level key protection.
- **Automated Deployment**: Provides a one-click installation script supporting both Standard and SGX modes to simplify the deployment process.
- **Security Verification**: Supports callback verification to ensure the legitimacy of transaction requests.

## Quick Start

### 1. Download and Install

```bash
# Grant execution permission to the script
chmod +x install.sh

# Run the installation script
./install.sh
```

After starting the script, you can choose the installation mode:
1. **Standard**: Suitable for standard Linux servers.
2. **SGX**: Suitable for servers supporting Intel SGX, providing higher security.

The installation script will automatically:
- Download the `co-signer` program suitable for your system (automatically signs and bundles in SGX mode).
- Guide you through key generation and configuration.
- Generate startup and stop scripts.

### 2. Start Service

```bash
./startup.sh
```

### 3. Stop Service

```bash
./stop.sh
```

## Documentation Index

- [Deployment Guide](docs/DEPLOY_EN.md): Detailed instructions on installation, configuration, and environment requirements.
- [Usage Guide](docs/USAGE_EN.md): Instructions for command-line tools and daily operations.

## Directory Structure

```
co-signer/
├── co-signer           # Main binary program
├── install.sh          # Installation script
├── startup.sh          # Startup script (generated after installation)
├── stop.sh             # Stop script (generated after installation)
├── conf/               # Configuration directory
│   ├── config.yaml     # Main configuration file
│   └── keystore.json   # Encrypted key storage
├── docs/               # Documentation directory
└── README.md           # Project description
```

## Support

If you encounter any issues, please contact ChainUp Custody technical support or refer to the [Official Documentation](https://custodydocs-en.chainup.com/).
