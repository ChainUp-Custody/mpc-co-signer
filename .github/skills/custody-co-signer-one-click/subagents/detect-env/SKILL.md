---
name: custody-co-signer-detect-env
description: "Detect remote server OS, SGX capability, and co-signer binary compatibility."
user-invocable: true
---

# Subagent 3: Remote Environment Detection

## What This Does

Probes SSH target to determine system capabilities and select appropriate co-signer version.

## Use When

- You need to identify OS type and version on target server
- You need to determine if SGX is available (INSTALL_TYPE)
- You need to validate binary compatibility

## Inputs

```json
{
  "ssh_cmd": "ssh -l root -p 22 <SERVER_IP>",
  "binary_check_timeout": 8
}
```

## Outputs

```json
{
  "status": "success",
  "os_id": "ubuntu",
  "os_version": "20.04",
  "install_type": 1,
  "sgx_available": false,
  "recommended_cosigner_version": "latest",
  "binary_executable": true,
  "notes": "..."
}
```

## Process

1. **Detect OS**
   - Read `/etc/os-release`
   - Extract `ID` and `VERSION_ID`
   - Determine OS family (Ubuntu, Debian, CentOS, etc.)

2. **Check SGX Capability**
   - Look for `/dev/sgx_enclave`, `/dev/sgx/enclave` files
   - Check dmesg for "sgx" keywords
   - If found → `INSTALL_TYPE=2`, else → `INSTALL_TYPE=1`

3. **Select Co-Signer Version**
   - Ubuntu 20+ → Latest version (from releases)

4. **Validate Binary Compatibility**
   - Download test binary version
   - Run `./co-signer -v` with timeout
   - If executable → `binary_executable=true`
   - If `./co-signer` already exists, parse its version and compare with selected target tag (default latest)
   - Reuse only when versions match exactly; otherwise mark for re-download

5. **Return Detection Results**
   - Recommended version
   - INSTALL_TYPE
   - Compatibility status

## SSH Operations

- `cat /etc/os-release` - Get OS info
- `ls -l /dev/sgx*` - Check SGX devices
- `dmesg | grep sgx` - Check boot logs
- `curl | grep tag_name` - Query latest release

## Error Handling

- SSH connection failed → retry with backoff
- OS detection failed → assume Ubuntu 20.04 (safest)
- Binary incompatible → suggest latest
- Permission denied → request sudo access

## Timeout

- Each SSH command: 10 seconds max
- Binary test: configurable (default 8 sec)
- Total detection: 30 seconds max
