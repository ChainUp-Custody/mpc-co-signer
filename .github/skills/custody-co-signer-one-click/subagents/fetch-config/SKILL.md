---
name: custody-co-signer-fetch-config
description: "Fetch deployment configuration from Custody Console API (check/create API, get app_id and system_rsa)."
user-invocable: true
---

# Subagent 2: Console Configuration Fetch

## What This Does

Queries Custody Console MPC API to check if API already exists and retrieves/creates deployment configuration.

## Use When

- You need to get Console API details for a workstation
- You need to create new API if it doesn't exist
- You need app_id and system_rsa for deployment

## Inputs

```json
{
  "cookie": "COINXMAN_SSO=<value>",
  "workstation_id": "<WORKSTATION_ID>",
  "console_domain": "https://custody.chainup.com"
}
```

## Outputs

```json
{
  "status": "success",
  "api_id": "b017b99f...",
  "system_rsa": "MIIBIjANBgkq...",
  "created": true|false,
  "trade_no": "...",
  "notes": "..."
}
```

## Process

1. **Query Existing API**
   - GET `{domain}/api/mpc/api/detail?wallet_id={workstation_id}`
   - Check if `app_id` is non-empty

2. **If API Exists**
   - Return `app_id` and `system_rsa`
   - No creation needed

3. **If API Not Exists**
   - POST `{domain}/api/mpc/api/save` with:
     - `wallet_id`
     - `believe_ips` (custody source IPs)
     - `co_signer_url` (placeholder)
     - `co_signer_rsa` (placeholder RSA key)
   - Receive `trade_no` or immediate `app_id`
   - Query detail endpoint again to confirm creation

4. **Return Configuration**
   - Extracted `app_id`
   - Extracted `system_rsa`
   - Creation status and trade_no if applicable
   - All downstream Console interactions continue through API requests only

## API Endpoints

- `GET /api/mpc/api/detail?wallet_id=<id>` - Query API
- `POST /api/mpc/api/save` - Create/Update API

## Error Handling

- Invalid cookie → return error with retry instruction
- API creation pending approval → return trade_no for user to approve
- API creation failed → return error details
- Timeout → retry with backoff

## Security

- Never log full cookie or RSA keys
- Use masked output for sensitive data
- Do not fall back to browser UI once a valid cookie has been obtained
