# OpenClaw Server Setup for iOS App

Instructions for configuring your OpenClaw instance to accept connections from the iOS app via Cloudflare tunnel.

## 1. Enable the OpenAI-Compatible HTTP API

OpenClaw's HTTP API is disabled by default. You need to enable it.

Edit your OpenClaw config file (usually `~/.openclaw/config.json` or `openclaw.json` in your project root):

```json
{
  "gateway": {
    "http": {
      "endpoints": {
        "chatCompletions": {
          "enabled": true
        }
      }
    }
  }
}
```

If you already have a config file with other settings, merge the `gateway.http.endpoints.chatCompletions.enabled` key into it.

Restart OpenClaw after making this change.

### Verify it works locally

```bash
curl -X POST http://127.0.0.1:18789/v1/chat/completions \
  -H "Authorization: Bearer YOUR_GATEWAY_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "openclaw:main",
    "messages": [{"role": "user", "content": "Hello, are you there?"}],
    "stream": false
  }'
```

You should get back a JSON response with `choices[0].message.content`. If you get a connection refused or 404, the API isn't enabled or OpenClaw isn't running.

### Find your gateway token

Your gateway token is set via the `OPENCLAW_GATEWAY_TOKEN` environment variable or the `--token` CLI flag when you start OpenClaw. If you haven't set one, check your OpenClaw startup command or config.

```bash
# Check if it's set in your environment
echo $OPENCLAW_GATEWAY_TOKEN

# Or look in your config
cat ~/.openclaw/config.json | grep -i token
```

If you don't have one set, add one:

```bash
export OPENCLAW_GATEWAY_TOKEN="your-secure-token-here"
```

Use a strong random string. You'll enter this same token in the iOS app.

## 2. Set Up the Cloudflare Tunnel

This exposes your OpenClaw gateway securely via `https://openclaw.samdavid.net` (or whatever subdomain you choose) without opening any ports on your router.

### Install cloudflared (if not already installed)

```bash
# macOS
brew install cloudflare/cloudflare/cloudflared

# Linux (Debian/Ubuntu)
curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
sudo dpkg -i cloudflared.deb

# Linux (other)
curl -L --output cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
sudo mv cloudflared /usr/local/bin/
sudo chmod +x /usr/local/bin/cloudflared
```

### Authenticate with Cloudflare

```bash
cloudflared tunnel login
```

This opens a browser. Select the `samdavid.net` domain and authorize.

### Create the tunnel

```bash
cloudflared tunnel create openclaw
```

This outputs a tunnel ID (UUID). Note it down.

### Configure the tunnel

Create `~/.cloudflared/config.yml`:

```yaml
tunnel: <TUNNEL_ID>
credentials-file: /home/<your-user>/.cloudflared/<TUNNEL_ID>.json

ingress:
  - hostname: openclaw.samdavid.net
    service: http://127.0.0.1:18789
    originRequest:
      noTLSVerify: false
  - service: http_status:404
```

Replace `<TUNNEL_ID>` with the UUID from the create step, and adjust the credentials-file path for your OS/user.

### Create the DNS record

```bash
cloudflared tunnel route dns openclaw openclaw.samdavid.net
```

This creates a CNAME record pointing `openclaw.samdavid.net` to your tunnel.

### Start the tunnel

```bash
cloudflared tunnel run openclaw
```

### Verify it works remotely

From any other machine (or your phone):

```bash
curl -X POST https://openclaw.samdavid.net/v1/chat/completions \
  -H "Authorization: Bearer YOUR_GATEWAY_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "openclaw:main",
    "messages": [{"role": "user", "content": "Hello from the tunnel!"}],
    "stream": false
  }'
```

If this returns a response, everything is working.

### Run the tunnel as a service (optional, recommended)

So it starts automatically on boot:

```bash
# macOS
sudo cloudflared service install
sudo launchctl start com.cloudflare.cloudflared

# Linux (systemd)
sudo cloudflared service install
sudo systemctl enable cloudflared
sudo systemctl start cloudflared
```

## 3. Configure the iOS App

Open the app on your phone/simulator:

1. Tap the gear icon (Settings)
2. Under **OpenClaw Gateway**:
   - URL: `https://openclaw.samdavid.net`
   - Token: your gateway token from step 1
3. Go back to the chat screen
4. Tap the keyboard icon and type a message to test

## 4. Security Checklist

- [ ] Gateway token is a strong random string (not something guessable)
- [ ] Cloudflare tunnel handles TLS termination — traffic is encrypted end-to-end
- [ ] The OpenClaw gateway only listens on `127.0.0.1` (localhost) — the tunnel connects locally
- [ ] No ports are open on your firewall/router
- [ ] The iOS app enforces HTTPS-only — it will reject `http://` URLs
- [ ] Consider enabling Cloudflare Access for additional authentication (IP allowlists, SSO, etc.)

## Troubleshooting

**"Connection refused" from curl locally**
- OpenClaw isn't running, or it's on a different port. Check `ps aux | grep openclaw` and verify the port.

**404 from the /v1/chat/completions endpoint**
- The HTTP API isn't enabled. Double-check your config and restart OpenClaw.

**401 Unauthorized**
- Token mismatch. Make sure the token in your curl/app matches `OPENCLAW_GATEWAY_TOKEN`.

**502 Bad Gateway from Cloudflare**
- The tunnel is running but OpenClaw isn't, or the port in `config.yml` doesn't match. Check that `http://127.0.0.1:18789` is reachable locally.

**Tunnel not starting**
- Check `cloudflared tunnel info openclaw` and verify credentials file exists.
