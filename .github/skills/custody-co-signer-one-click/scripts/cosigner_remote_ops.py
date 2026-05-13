#!/usr/bin/env python3
"""
Remote co-signer operations via SSH. Password is ALWAYS passed through stdin,
never in command-line arguments.

Usage:
    python cosigner_remote_ops.py --ssh-cmd "ssh -l root -p 22 1.2.3.4" \\
        --action start --password SECRET --workdir /data/co-signer/mpc-co-signer

Actions:
    start               Stop existing process, start co-signer -server
    stop                Stop co-signer process
    show-rsa            Show RSA public keys from keystore
    import-custody-pub  Import ChainUp custody public key (requires --pub-key)
    import-verify-pub   Import custom verify sign public key (requires --pub-key)
    reset-password      Reset co-signer password (requires --new-password)
    bundle-ego          Sign and bundle co-signer with ego for SGX deployment (requires --install-type=2)
    health              Check port, process, outbound connectivity

All actions that need the co-signer password receive it via stdin pipe.
"""
import argparse
import shlex
import subprocess
import sys


def read_password_from_stdin() -> str:
    value = sys.stdin.readline()
    if value is None:
        return ""
    return value.rstrip("\n")


def ssh_cmd_list(ssh_cmd: str) -> list:
    return shlex.split(ssh_cmd)


def run_ssh(ssh_cmd: str, remote_script: str, stdin_data: str = "",
            timeout: int = 30) -> subprocess.CompletedProcess:
    cmd = ssh_cmd_list(ssh_cmd) + [remote_script]
    return subprocess.run(
        cmd,
        input=stdin_data if stdin_data else None,
        capture_output=True, text=True, timeout=timeout,
    )


def action_start(args):
    remote_cmd = r"""bash -c '
cd {workdir}
pkill -x co-signer 2>/dev/null || true
sleep 1
IFS= read -r PW
export _COSIGNER_PW="$PW"
unset PW
nohup bash -c '"'"'printf "%s\n" "$_COSIGNER_PW" | exec "$0" -server'"'"' ./co-signer >> ./nohup.out 2>&1 &
BGPID=$!
unset _COSIGNER_PW
sleep 5
if ss -tlnp | grep -q {port}; then
    echo "PORT_OK pid=$BGPID"
else
    echo "PORT_FAIL"
    tail -15 ./nohup.out 2>/dev/null || echo "no nohup.out"
fi
'""".format(workdir=args.workdir, port=args.port)

    proc = run_ssh(args.ssh_cmd, remote_cmd, stdin_data=args.password + "\n",
                   timeout=60)
    print(proc.stdout)
    if proc.stderr:
        print("STDERR:", proc.stderr, file=sys.stderr)
    return 0 if "PORT_OK" in proc.stdout else 1


def action_stop(args):
    remote_cmd = """bash -c '
cd {workdir}
if pkill -x co-signer; then
    echo "STOPPED"
else
    echo "NOT_RUNNING"
fi
sleep 1
if pgrep -x co-signer >/dev/null 2>&1; then
    pkill -9 -x co-signer || true
    echo "FORCE_KILLED"
fi
'""".format(workdir=args.workdir)

    proc = run_ssh(args.ssh_cmd, remote_cmd)
    print(proc.stdout)
    return proc.returncode


def action_show_rsa(args):
    remote_cmd = r"""bash -c '
cd {workdir}
IFS= read -r PW
printf "%s\n" "$PW" | ./co-signer -show-rsa 2>&1
'""".format(workdir=args.workdir)

    proc = run_ssh(args.ssh_cmd, remote_cmd, stdin_data=args.password + "\n")
    print(proc.stdout)
    return 0


def action_import_key(args, flag: str):
    if not args.pub_key:
        print("ERROR: --pub-key is required for this action", file=sys.stderr)
        return 1

    remote_cmd = r"""bash -c '
cd {workdir}
IFS= read -r PW
printf "%s\n%s\n" "$PW" "$PW" | ./co-signer {flag} "{pub_key}" 2>&1
'""".format(workdir=args.workdir, flag=flag, pub_key=args.pub_key)

    proc = run_ssh(args.ssh_cmd, remote_cmd, stdin_data=args.password + "\n")
    print(proc.stdout)
    if proc.stderr:
        print("STDERR:", proc.stderr, file=sys.stderr)
    if "success" in proc.stdout.lower():
        return 0
    return 1


def action_reset_password(args):
    """Reset co-signer password. Requires current password (--password) and new password (--new-password)."""
    if not args.new_password:
        print("ERROR: --new-password is required for reset-password action", file=sys.stderr)
        return 1

    remote_cmd = r"""bash -c '
cd {workdir}
IFS= read -r OLD_PW
IFS= read -r NEW_PW
printf "%s\n%s\n%s\n" "$OLD_PW" "$NEW_PW" "$NEW_PW" | ./co-signer -reset-password 2>&1
'""".format(workdir=args.workdir)

    proc = run_ssh(args.ssh_cmd, remote_cmd,
                   stdin_data=args.password + "\n" + args.new_password + "\n",
                   timeout=30)
    print(proc.stdout)
    if proc.stderr:
        print("STDERR:", proc.stderr, file=sys.stderr)
    if "success" in proc.stdout.lower():
        return 0
    return 1


def action_health(args):
    remote_cmd = """bash -c '
echo "=== PROCESS ==="
ps aux | grep co-signer | grep -v grep || echo "NO_PROCESS"
echo "=== PORT ==="
ss -tlnp | grep {port} && echo "PORT_OK" || echo "PORT_FAIL"
echo "=== OUTBOUND ==="
curl -s --connect-timeout 5 https://openapi.chainup.com/api/ping || echo "OUTBOUND_FAIL"
echo ""
'""".format(port=args.port)

    proc = run_ssh(args.ssh_cmd, remote_cmd, timeout=15)
    print(proc.stdout)
    return 0 if "PORT_OK" in proc.stdout else 1


def action_bundle_ego(args):
    """Sign and bundle co-signer with ego for SGX deployment."""
    if not args.install_type or args.install_type != "2":
        print("ERROR: bundle-ego requires --install-type=2 (SGX)", file=sys.stderr)
        return 1

    remote_cmd = r"""bash -c '
set -euo pipefail

cd {workdir}
echo "[INFO] === SGX EGO Bundle Process ==="

# Step 1: Check and install ego if needed
echo "[INFO] Checking for ego..."
if ! command -v ego >/dev/null 2>&1; then
    echo "[WARN] ego not found. Attempting to install..."
    
    # Install dependencies
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -qq >/dev/null 2>&1 || true
        apt-get install -y build-essential libssl-dev wget >/dev/null 2>&1
    elif command -v yum >/dev/null 2>&1; then
        yum groupinstall -y "Development Tools" >/dev/null 2>&1 || true
        yum install -y openssl-devel wget >/dev/null 2>&1 || true
    fi
    
    # Download and install ego
    EGO_LATEST_TAG=$(curl -s https://api.github.com/repos/edgelesssys/ego/releases/latest | grep '"tag_name":' | sed -E '"'"'s/.*"([^"]+)".*/\1/'"'"')
    if [[ -z "$EGO_LATEST_TAG" ]]; then
        echo "[ERROR] Failed to fetch latest ego version" >&2
        exit 1
    fi
    
    EGO_VERSION=${{EGO_LATEST_TAG#v}}
    EGO_DEB="ego_${{EGO_VERSION}}_amd64_ubuntu-22.04.deb"
    EGO_URL="https://github.com/edgelesssys/ego/releases/download/${{EGO_LATEST_TAG}}/${{EGO_DEB}}"
    
    echo "[INFO] Downloading ego from: ${{EGO_URL}}"
    if command -v wget >/dev/null 2>&1; then
        wget -q -O "/tmp/${{EGO_DEB}}" "${{EGO_URL}}"
    else
        curl -fL -o "/tmp/${{EGO_DEB}}" "${{EGO_URL}}"
    fi
    
    # Install ego deb
    if command -v apt-get >/dev/null 2>&1; then
        apt-get install -y "/tmp/${{EGO_DEB}}" >/dev/null 2>&1
    else
        echo "[WARN] Cannot auto-install ego on this system. Please install manually."
        exit 1
    fi
    
    rm -f "/tmp/${{EGO_DEB}}"
    
    if ! command -v ego >/dev/null 2>&1; then
        echo "[ERROR] Failed to install ego" >&2
        exit 1
    fi
    echo "[OK] ego installed successfully"
else
    echo "[OK] ego is already installed"
fi

# Step 2: Check if co-signer is already bundled
echo "[INFO] Checking if co-signer is already bundled..."
if ./co-signer -v 2>&1 | grep -qi "loading enclave"; then
    echo "[INFO] co-signer is already SGX bundled. Skipping bundle process."
    exit 0
fi

# Step 3: Calculate heap size
echo "[INFO] Calculating heap size..."
AVAILABLE_MEM_KB=$(grep MemAvailable /proc/meminfo | awk '"'"'{{print $2}}'"'"')
HEAP_SIZE_MB=$(printf '%.0f\n' $(echo "$AVAILABLE_MEM_KB * 0.92 / 1024" | bc))
echo "[INFO] Available Memory: $((AVAILABLE_MEM_KB/1024)) MB, Configured Heap: ${{HEAP_SIZE_MB}} MB"

# Step 4: Create private.pem for signing if it doesn''t exist
if [[ ! -f "./private.pem" ]]; then
    echo "[INFO] Generating signing key pair..."
    openssl genrsa -out ./private.pem 2048 2>/dev/null
fi

# Step 5: Create enclave.json
echo "[INFO] Creating enclave.json..."
cat > ./enclave.json <<ENCLAVEEOF
{{
    "exe": "co-signer",
    "key": "private.pem",
    "debug": false,
    "heapSize": ${{HEAP_SIZE_MB}},
    "executableHeap": false,
    "productID": 1,
    "securityVersion": 1,
    "mounts": [
        {{"readOnly": false, "type": "hostfs", "source": "/etc/ssl/certs/", "target": "/etc/ssl/certs/"}},
        {{"readOnly": false, "type": "hostfs", "source": "{workdir}", "target": "{workdir}"}}
    ],
    "env": [
        {{"name": "HOME", "fromHost": true}},
        {{"name": "PWD", "value": "{workdir}"}}
    ],
    "files": null
}}
ENCLAVEEOF

# Step 6: Sign the binary with ego
echo "[INFO] Signing co-signer binary with ego..."
if ! ego sign co-signer; then
    echo "[ERROR] ego sign failed" >&2
    exit 1
fi
echo "[OK] Binary signed"

# Step 7: Bundle the binary
echo "[INFO] Bundling with ego..."
if ! ego bundle co-signer co-signer.sgx; then
    echo "[ERROR] ego bundle failed" >&2
    exit 1
fi
echo "[OK] Bundle created"

# Step 8: Replace original with bundled version
echo "[INFO] Replacing original binary with bundled SGX version..."
mv co-signer.sgx co-signer
chmod +x co-signer

# Verify the bundled binary
if ! ./co-signer -v 2>&1 | grep -qi "loading enclave"; then
    echo "[WARN] Binary may not be properly bundled, but bundling completed"
fi

echo "[OK] SGX bundling completed successfully"
echo "BUNDLE_STATUS=SUCCESS"
'""".format(workdir=args.workdir)

    proc = run_ssh(args.ssh_cmd, remote_cmd, timeout=300)
    print(proc.stdout)
    if proc.stderr:
        print("STDERR:", proc.stderr, file=sys.stderr)
    return 0 if "BUNDLE_STATUS=SUCCESS" in proc.stdout else 1



def main():
    parser = argparse.ArgumentParser(description="Remote co-signer operations (password via stdin)")
    parser.add_argument("--ssh-cmd", required=True, help="SSH command string, e.g. 'ssh -l root -p 22 1.2.3.4'")
    parser.add_argument("--action", required=True,
                        choices=["start", "stop", "show-rsa", "import-custody-pub",
                                 "import-verify-pub", "reset-password", "bundle-ego", "health"])
    parser.add_argument("--password", default="", help="Co-signer password (passed via stdin, not argv on remote)")
    parser.add_argument("--password-stdin", action="store_true",
                        help="Read password from stdin instead of --password")
    parser.add_argument("--new-password", default="", help="New password for reset-password action")
    parser.add_argument("--workdir", default="/data/co-signer/mpc-co-signer",
                        help="Remote co-signer working directory")
    parser.add_argument("--port", default="28888", help="Co-signer listening port")
    parser.add_argument("--pub-key", default="", help="RSA public key for import actions")
    parser.add_argument("--install-type", default="", help="Installation type (1=standard, 2=SGX) for bundle-ego action")

    args = parser.parse_args()

    if args.password_stdin:
        args.password = read_password_from_stdin()

    if args.action in ("start", "show-rsa", "import-custody-pub", "import-verify-pub", "reset-password"):
        if not args.password:
            print("ERROR: --password is required for this action", file=sys.stderr)
            sys.exit(1)

    actions = {
        "start": action_start,
        "stop": action_stop,
        "show-rsa": action_show_rsa,
        "import-custody-pub": lambda a: action_import_key(a, "-custody-pub-import"),
        "import-verify-pub": lambda a: action_import_key(a, "-verify-sign-pub-import"),
        "reset-password": action_reset_password,
        "bundle-ego": action_bundle_ego,
        "health": action_health,
    }

    rc = actions[args.action](args)
    sys.exit(rc)


if __name__ == "__main__":
    main()
