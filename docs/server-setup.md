# IronClaw Server Setup for ClawTalk

Instructions for configuring your IronClaw service so ClawTalk can connect over HTTPS.

## 1. Required IronClaw Endpoints

ClawTalk's maintained primary path expects these endpoints:

- `POST /api/chat/thread/new`
- `POST /api/chat/send`
- `GET /api/chat/history?thread_id=...`
- `GET /v1/models`
- `POST /tools/invoke`
- `GET /health` (recommended for connectivity checks)

Authenticated requests should accept:

- `Authorization: Bearer <token>`
- `thread_id` in the send/history flow when continuing a conversation

## 2. Verify IronClaw Locally

```bash
THREAD_ID=$(curl -s -X POST http://127.0.0.1:18789/api/chat/thread/new \
  -H "Authorization: Bearer YOUR_IRONCLAW_TOKEN" | jq -r '.id')

curl -X POST http://127.0.0.1:18789/api/chat/send \
  -H "Authorization: Bearer YOUR_IRONCLAW_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"thread_id\":\"$THREAD_ID\",\"content\":\"Hello, are you there?\",\"timezone\":\"UTC\"}"

curl "http://127.0.0.1:18789/api/chat/history?thread_id=$THREAD_ID" \
  -H "Authorization: Bearer YOUR_IRONCLAW_TOKEN"
```

You should receive an IronClaw thread history payload containing the latest turn. If you get a connection refused or 404, IronClaw is not running or that endpoint is unavailable.

```bash
curl http://127.0.0.1:18789/v1/models \
  -H "Authorization: Bearer YOUR_IRONCLAW_TOKEN"
```

```bash
curl http://127.0.0.1:18789/health
```

## 3. Configure Your Bearer Token

Use the bearer token configured for your IronClaw deployment. For example:

```bash
export IRONCLAW_BEARER_TOKEN="your-secure-token-here"
```

Use a strong random string. Enter this same token in the iOS app.

## 4. Expose IronClaw Securely

Your IronClaw service may listen on localhost by default. You need a secure way to reach it from your phone.

### Option A: Tailscale

Install Tailscale on both the server and the iPhone, sign into the same tailnet, and expose IronClaw over HTTPS.

```bash
tailscale cert <hostname>.your-tailnet.ts.net
```

Or proxy the local IronClaw port directly:

```bash
tailscale serve https / http://127.0.0.1:18789
```

Verify from another device on the tailnet:

```bash
THREAD_ID=$(curl -s -X POST https://<hostname>.your-tailnet.ts.net/api/chat/thread/new \
  -H "Authorization: Bearer YOUR_IRONCLAW_TOKEN" | jq -r '.id')

curl -X POST https://<hostname>.your-tailnet.ts.net/api/chat/send \
  -H "Authorization: Bearer YOUR_IRONCLAW_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"thread_id\":\"$THREAD_ID\",\"content\":\"Hello!\",\"timezone\":\"UTC\"}"
```

### Option B: Cloudflare Tunnel

Expose IronClaw via an HTTPS hostname without opening inbound ports.

```bash
cloudflared tunnel login
cloudflared tunnel create ironclaw
```

Example `~/.cloudflared/config.yml`:

```yaml
tunnel: <TUNNEL_ID>
credentials-file: /home/<your-user>/.cloudflared/<TUNNEL_ID>.json

ingress:
  - hostname: ironclaw.yourdomain.com
    service: http://127.0.0.1:18789
    originRequest:
      noTLSVerify: false
  - service: http_status:404
```

Then route DNS and start the tunnel:

```bash
cloudflared tunnel route dns ironclaw ironclaw.yourdomain.com
cloudflared tunnel run ironclaw
```

Verify remotely:

```bash
THREAD_ID=$(curl -s -X POST https://ironclaw.yourdomain.com/api/chat/thread/new \
  -H "Authorization: Bearer YOUR_IRONCLAW_TOKEN" | jq -r '.id')

curl -X POST https://ironclaw.yourdomain.com/api/chat/send \
  -H "Authorization: Bearer YOUR_IRONCLAW_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "thread_id": "'$THREAD_ID'",
    "content": "Hello from outside!",
    "timezone": "UTC"
  }'
```

## 5. Configure ClawTalk

In the app settings:

1. Open **Settings**
2. Under **IronClaw Connection** enter:
   - **URL**: your Tailscale or tunnel URL
   - **Token**: your IronClaw bearer token
   - **API Mode**: **Open Responses**
3. Return to chat and send a test message

## 6. Security Checklist

- [ ] Bearer token is a strong random string
- [ ] TLS is handled by Tailscale or Cloudflare Tunnel
- [ ] IronClaw only listens on localhost when fronted by a tunnel
- [ ] No unnecessary firewall or router ports are open
- [ ] The app uses HTTPS for remote connections
- [ ] API keys are stored in iOS Keychain, not UserDefaults

## 7. Troubleshooting

**Connection refused**
- IronClaw is not running, or the port is different from the URL you configured.

**404 from `/api/chat/thread/new` or `/api/chat/send`**
- IronClaw is not exposing the thread API at that base URL.

**404 from `/v1/models`**
- IronClaw is not exposing model discovery at that base URL.

**401 Unauthorized**
- The bearer token in ClawTalk does not match the server token.

**Session continuity seems lost**
- Ensure each conversation reuses the latest thread id when calling `/api/chat/send` and `/api/chat/history`.

**Tool calls fail**
- Verify `/tools/invoke` exists and expects `{"tool":"name","args":{...}}`.

**Health check fails**
- Verify `/health` is exposed and that the configured base URL has no extra path prefix.

## 8. Notes

- Older OpenClaw-era instructions may still mention Chat Completions or device-pairing flows that do not apply to IronClaw-native HTTP usage.
- ClawTalk's maintained primary transport is the IronClaw thread API via `/api/chat/thread/new`, `/api/chat/send`, and `/api/chat/history`.
