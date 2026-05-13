#!/usr/bin/env python3
"""
Headless Playwright: load Custody login page, show QR in chat, wait for scan, extract COINXMAN-SSO cookie.

Usage:
    python get_custody_cookie.py [--timeout 180] [--qr-path /tmp/custody_qr.png]

Output:
    On success prints: COINXMAN_SSO_COOKIE=<value>
    QR screenshot saved to --qr-path for agent to show in chat via view_image.
"""
import argparse
import sys
import time

from playwright.sync_api import sync_playwright


def main():
    parser = argparse.ArgumentParser(description="Get Custody COINXMAN-SSO cookie via QR login")
    parser.add_argument("--timeout", type=int, default=180, help="Max seconds to wait for QR scan (default: 180)")
    parser.add_argument("--qr-path", default="/tmp/custody_qr.png", help="Path to save QR screenshot")
    parser.add_argument("--qr-wait", type=int, default=5, help="Seconds to wait for QR to render (default: 5)")
    args = parser.parse_args()

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True, args=["--no-sandbox"])
        context = browser.new_context(
            viewport={"width": 1280, "height": 800},
            ignore_https_errors=True,
        )
        page = context.new_page()

        print("[INFO] Navigating to https://custody.chainup.com/login ...")
        try:
            page.goto("https://custody.chainup.com/login", wait_until="domcontentloaded", timeout=60000)
        except Exception as e:
            print(f"[ERROR] Page load failed: {e}", file=sys.stderr)
            browser.close()
            sys.exit(1)

        # Wait for QR to render
        time.sleep(args.qr_wait)

        # Save QR screenshot
        page.screenshot(path=args.qr_path)
        print(f"[INFO] QR screenshot saved to {args.qr_path}")
        print("SCREENSHOT_READY")

        # Poll until URL leaves /login OR COINXMAN-SSO cookie appears
        cdp = context.new_cdp_session(page)
        print(f"[INFO] Scan the QR code with Custody App（Operating member roles: Wallet member/administrator/owner）. Waiting up to {args.timeout}s...")
        sso_cookie = None
        for i in range(args.timeout):
            # Check URL change
            url = page.url
            if "/login" not in url:
                print(f"[INFO] Login detected via URL change! URL: {url}")
                time.sleep(2)
                break
            # Check cookie every 5 seconds
            if i > 0 and i % 5 == 0:
                try:
                    result = cdp.send("Network.getCookies", {"urls": ["https://custody.chainup.com"]})
                    for c in result.get("cookies", []):
                        if c["name"] == "COINXMAN-SSO":
                            sso_cookie = c["value"]
                            print(f"[INFO] Login detected via cookie!")
                            break
                except Exception:
                    pass
                if sso_cookie:
                    break
            time.sleep(1)
            if i > 0 and i % 10 == 0:
                print(f"[INFO] Still waiting... ({i}s)")
        else:
            print(f"[ERROR] Timeout waiting for login ({args.timeout}s)")
            browser.close()
            sys.exit(1)

        # Final cookie extraction if not already found
        if not sso_cookie:
            time.sleep(2)
            result = cdp.send("Network.getCookies", {"urls": ["https://custody.chainup.com"]})
            for c in result.get("cookies", []):
                if c["name"] == "COINXMAN-SSO":
                    sso_cookie = c["value"]
                    break

        if sso_cookie:
            print(f"COINXMAN_SSO_COOKIE={sso_cookie}")
        else:
            print("[ERROR] COINXMAN-SSO cookie not found!")
            names = [c["name"] for c in result.get("cookies", [])]
            print(f"[DEBUG] Available cookies: {names}")
            browser.close()
            sys.exit(1)

        browser.close()


if __name__ == "__main__":
    main()
