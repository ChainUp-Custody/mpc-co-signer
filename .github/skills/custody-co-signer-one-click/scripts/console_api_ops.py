#!/usr/bin/env python3
"""
ChainUp Custody Console API operations.
Uses only stdlib (urllib) — no requests dependency needed.

Usage:
    python console_api_ops.py --cookie SSO_VALUE --action detail --wallet-id 12602
    python console_api_ops.py --cookie SSO_VALUE --action save --wallet-id 12602 \\
        --app-id APP_ID --believe-ips 1.2.3.4 --co-signer-url http://1.2.3.4:28888 \\
        --co-signer-rsa RSA_KEY --google-code 123456
    python console_api_ops.py --cookie SSO_VALUE --action list-wallets
    python console_api_ops.py --cookie SSO_VALUE --action list-workstations --wallet-id 12602

Actions:
    detail              Get workstation API config detail
    save                Save/update workstation API config (requires google-code)
    list-wallets        List all MPC wallets
    list-workstations   List workstations under a wallet
"""
import argparse
import json
import sys
import urllib.parse
import urllib.request

BASE_URL = "https://custody.chainup.com"


def api_headers(cookie: str) -> dict:
    return {
        "Cookie": f"COINXMAN-SSO={cookie}",
        "build-cu": "web",
        "language": "en_US",
        "platform": "Keysecure",
        "timezone": "Asia/Shanghai",
    }


def api_get(cookie: str, path: str, params: dict = None) -> dict:
    url = f"{BASE_URL}{path}"
    if params:
        url += "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers=api_headers(cookie))
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read())


def api_post(cookie: str, path: str, data: dict) -> dict:
    url = f"{BASE_URL}{path}"
    headers = api_headers(cookie)
    headers["Content-Type"] = "application/x-www-form-urlencoded"
    encoded = urllib.parse.urlencode(data).encode()
    req = urllib.request.Request(url, data=encoded, headers=headers, method="POST")
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read())


def action_detail(args):
    result = api_get(args.cookie, "/api/mpc/api/detail", {"wallet_id": args.wallet_id})
    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 0 if result.get("code") == "0" else 1


def action_save(args):
    if not args.google_code:
        print("ERROR: --google-code is required for save action", file=sys.stderr)
        return 1

    data = {
        "app_id": args.app_id,
        "wallet_id": args.wallet_id,
        "believe_ips": args.believe_ips,
        "co_signer_url": args.co_signer_url,
        "co_signer_rsa": args.co_signer_rsa,
        "developer_rsa": args.co_signer_rsa,
        "google_code": args.google_code,
    }
    result = api_post(args.cookie, "/api/mpc/api/save", data)
    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 0 if result.get("code") == "0" else 1


def action_list_wallets(args):
    result = api_get(args.cookie, "/api/mpc/wallets/asset", {"type": "0"})
    if result.get("code") != "0":
        print(json.dumps(result, indent=2, ensure_ascii=False))
        return 1

    d = result.get("data", {})
    pinned = d.get("top_wallet", [])
    regular = d.get("wallet_list", [])

    seen = set()
    all_wallets = []
    for w in pinned:
        wid = w.get("wallet_id")
        if wid not in seen:
            seen.add(wid)
            all_wallets.append((w, True))
    for w in regular:
        wid = w.get("wallet_id")
        if wid not in seen:
            seen.add(wid)
            all_wallets.append((w, False))

    print(f"Total: {len(all_wallets)} wallet(s)\n")
    for i, (w, pinned_flag) in enumerate(all_wallets):
        wid = w.get("wallet_id", "")
        name = w.get("wallet_name", "")
        expired = w.get("whether_expire", False)
        bal = w.get("usd_balance", "0")
        wtype = "API" if w.get("wallet_type") == 2 else "MPC"
        status = "EXPIRED" if expired else "ACTIVE"
        pin = " [PINNED]" if pinned_flag else ""
        subs = w.get("sub_wallet_list", [])
        print(f"  [{i+1:2d}] ID={wid:<6}  {name:<30}  ${bal:<12}  {wtype}  {status}{pin}")
        for sw in subs:
            swid = sw.get("sub_wallet_id", "")
            swname = sw.get("sub_wallet_name", "")
            swnum = sw.get("sub_wallet_num", "")
            print(f"        └── sub_id={swid}  num={swnum}  {swname}")
    return 0


def action_list_workstations(args):
    # Use detail endpoint for single workstation; list is derived from wallet subs
    result = api_get(args.cookie, "/api/mpc/api/detail", {"wallet_id": args.wallet_id})
    if result.get("code") != "0":
        print(json.dumps(result, indent=2, ensure_ascii=False))
        return 1

    d = result.get("data", {})
    print(f"Workstation ID: {args.wallet_id}")
    print(f"  app_id:         {d.get('app_id', '')}")
    print(f"  co_signer_url:  {d.get('co_signer_url', '')}")
    print(f"  believe_ips:    {d.get('believe_ips', '')}")
    print(f"  co_signer_key:  {d.get('co_signer_key', '')}")
    print(f"  authority:      {d.get('authority', '')}")
    print(f"  status:         {d.get('status', '')}")
    rsa = d.get("co_signer_rsa", "")
    print(f"  co_signer_rsa:  {rsa[:50]}...{rsa[-20:]}" if len(rsa) > 70 else f"  co_signer_rsa:  {rsa}")
    sys_rsa = d.get("system_rsa", "")
    print(f"  system_rsa:     {sys_rsa[:50]}...{sys_rsa[-20:]}" if len(sys_rsa) > 70 else f"  system_rsa:     {sys_rsa}")
    return 0


def main():
    parser = argparse.ArgumentParser(description="ChainUp Custody Console API operations")
    parser.add_argument("--cookie", required=True, help="COINXMAN-SSO cookie value")
    parser.add_argument("--action", required=True,
                        choices=["detail", "save", "list-wallets", "list-workstations"])
    parser.add_argument("--wallet-id", default="", help="Wallet/Workstation ID")
    parser.add_argument("--app-id", default="", help="APP ID for save")
    parser.add_argument("--believe-ips", default="", help="Trusted IPs for save")
    parser.add_argument("--co-signer-url", default="", help="Co-signer URL for save")
    parser.add_argument("--co-signer-rsa", default="", help="Co-signer RSA public key for save")
    parser.add_argument("--google-code", default="", help="Google 2FA code for save")

    args = parser.parse_args()

    if args.action in ("detail", "save", "list-workstations") and not args.wallet_id:
        print("ERROR: --wallet-id is required for this action", file=sys.stderr)
        sys.exit(1)

    actions = {
        "detail": action_detail,
        "save": action_save,
        "list-wallets": action_list_wallets,
        "list-workstations": action_list_workstations,
    }

    rc = actions[args.action](args)
    sys.exit(rc)


if __name__ == "__main__":
    main()
