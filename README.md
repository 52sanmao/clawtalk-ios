# ClawTalk

A native iOS app for voice and text chat with your [OpenClaw](https://github.com/openclaw/openclaw) agents.

Push-to-talk or hands-free conversation mode with on-device speech recognition, streaming text responses with markdown rendering, text-to-speech output, image sending, and multi-agent channels — all over a secure HTTPS connection to your self-hosted OpenClaw gateway.

## Features

- **Voice input** — Push-to-talk or hands-free conversation mode with Voice Activity Detection
- **On-device speech-to-text** — WhisperKit runs entirely on your phone. Audio never leaves the device.
- **Streaming responses** — Text streams in real-time as your agent generates it
- **Text-to-speech** — Responses are spoken aloud. Choose from ElevenLabs, OpenAI, or Apple's built-in voice.
- **Image sending** — Attach up to 8 photos per message
- **Multi-agent channels** — Create channels for different OpenClaw agents
- **Markdown rendering** — Agent responses render with full markdown support
- **Token usage** — See input/output token counts per message (Open Responses API)
- **Dark mode** — Designed for dark mode with OpenClaw lobster branding
- **Security first** — All credentials in iOS Keychain, HTTPS enforced, on-device STT

## Requirements

- iOS 17.0+
- Xcode 16.0+ with Swift 5.10
- [xcodegen](https://github.com/yonaskolb/XcodeGen) — generates the Xcode project from `project.yml`
- A running [OpenClaw](https://github.com/openclaw/openclaw) instance with the HTTP API enabled

## Building

### 1. Install dependencies

```bash
brew install xcodegen
```

### 2. Generate the Xcode project

```bash
cd openclaw-chat-ios
xcodegen generate
```

This reads `project.yml` and generates `OpenClawChat.xcodeproj`. Run this again any time you add or remove source files.

### 3. Open and build

```bash
open OpenClawChat.xcodeproj
```

Or build from the command line:

```bash
xcodebuild -project OpenClawChat.xcodeproj \
  -scheme OpenClawChat \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  build
```

Swift Package Manager dependencies (WhisperKit, KeychainAccess, MarkdownUI) resolve automatically on first build.

### 4. Run on device

To run on a physical device, update the development team in `project.yml`:

```yaml
settings:
  base:
    DEVELOPMENT_TEAM: YOUR_TEAM_ID
```

Then regenerate: `xcodegen generate`

## OpenClaw Gateway Setup

ClawTalk connects to your self-hosted OpenClaw instance over HTTPS. You need to:

1. **Enable the HTTP API** in your OpenClaw config
2. **Expose it securely** via Cloudflare Tunnel or Tailscale

### Enable Chat Completions (minimum)

Edit your OpenClaw config (`~/.openclaw/config.json`):

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

### Enable Open Responses (optional, for token usage)

```json
{
  "gateway": {
    "http": {
      "endpoints": {
        "chatCompletions": {
          "enabled": true
        },
        "responses": {
          "enabled": true
        }
      }
    }
  }
}
```

The Open Responses API provides real token usage data (input/output counts) and structured streaming events. Chat Completions is the simpler default that works with all gateways.

### Set a gateway token

```bash
export OPENCLAW_GATEWAY_TOKEN="your-secure-random-token"
```

You'll enter this same token in the app's Settings.

### Expose securely

**Tailscale (recommended):** Install [Tailscale](https://tailscale.com/download) on your server and iPhone, then use Tailscale Serve:

```bash
tailscale serve https / http://127.0.0.1:18789
```

Your gateway is now at `https://<hostname>.your-tailnet.ts.net`.

**Cloudflare Tunnel:** Alternative if you want a public-facing URL without installing Tailscale on your phone.

See [docs/server-setup.md](docs/server-setup.md) for detailed step-by-step instructions for both options.

### Verify

```bash
curl -X POST https://your-gateway-url/v1/chat/completions \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"model":"openclaw:main","messages":[{"role":"user","content":"Hello!"}],"stream":false}'
```

## App Configuration

On first launch:

1. **Settings → OpenClaw Gateway**
   - **URL**: Your gateway URL (e.g., `https://openclaw.yourdomain.com`)
   - **Token**: Your gateway token
   - **API Mode**: Chat Completions (default) or Open Responses

2. **Settings → Text-to-Speech** (optional)
   - **ElevenLabs**: Best quality. Enter your API key and voice ID.
   - **OpenAI**: Good quality, cost-effective. Enter your API key.
   - **Apple**: Free, offline. No setup needed.

3. **Settings → Speech-to-Text**
   - **Small** (250 MB): Faster, good for most use. Downloaded on first voice input.
   - **Large Turbo** (1.6 GB): Best accuracy. Download prompted with confirmation.

4. **Settings → Voice**
   - Toggle voice input and output independently for text-only mode.

5. **Settings → Display**
   - Toggle token usage display under assistant messages (requires Open Responses API).

## Tools Dashboard

The wrench icon on the channel list opens the **Tools** view — a dashboard for interacting directly with your agent's internals without going through chat.

| Tool | What it does |
|------|-------------|
| **Memory** | Search and read your agent's memory files |
| **Agents** | View available agents on your gateway |
| **Sessions** | List active sessions, view status and conversation history |
| **Browser** | View browser status, tabs, and take screenshots |
| **Files** | Read files from your agent's workspace |

Tools are automatically probed for availability on each visit. Unavailable tools appear greyed out with "Not enabled on gateway".

### Enabling tools on the gateway

Tools require specific **tool profiles** on your agents. In `~/.openclaw/openclaw.json`:

```json
{
  "agents": {
    "list": [{
      "id": "main",
      "tools": {
        "profile": "coding"
      }
    }]
  }
}
```

| Profile | Tools enabled |
|---------|--------------|
| `minimal` | Session status only |
| `coding` | Filesystem, exec, sessions, memory, image |
| `messaging` | Messaging, session management |
| `full` | Everything |

**Memory tools** additionally require an embedding provider configured under `plugins.slots.memory`.

**File read** requires the `coding` profile or explicit `tools.alsoAllow: ["read"]`.

## Multi-Agent Channels

Each channel routes to a specific OpenClaw agent:

1. Tap **+** on the channel list
2. Select an agent from the list, or type an agent ID manually
3. Each channel maintains its own conversation history

The agent ID maps to `"openclaw:<agentId>"` in the model field. Your OpenClaw instance routes the request to the corresponding agent.

### Agent picker visibility

The "New Channel" agent picker uses the `agents_list` tool, which is scoped by the calling agent's `subagents.allowAgents` config. To see all your agents in the picker, add to your main agent's config:

```json
{
  "agents": {
    "list": [{
      "id": "main",
      "subagents": {
        "allowAgents": ["*"]
      }
    }]
  }
}
```

Without this, only the calling agent and explicitly allowlisted agents appear. You can always type any agent ID manually using the text field.

### Creating agents

Agents are defined in `~/.openclaw/openclaw.json` under `agents.list`. Each agent has:
- **`id`**: Stable identifier (e.g., `main`, `coder`, `research`)
- **`workspace`**: Directory with agent context files (`SOUL.md`, `AGENTS.md`)
- **`tools.profile`**: What the agent can do (`minimal`, `coding`, `messaging`, `full`)

The agent's personality comes from `SOUL.md` in its workspace directory.

## Project Structure

```
OpenClawChat/
  App/            # Entry point, service wiring, theme
  Core/
    Agent/        # OpenClaw HTTP client (Chat Completions + Open Responses + Tools)
    Audio/        # Mic capture (AVAudioEngine) + streaming playback
    STT/          # On-device WhisperKit + OpenAI fallback
    TTS/          # ElevenLabs, OpenAI, Apple speech services
    Security/     # iOS Keychain wrapper
    Storage/      # Channel + conversation persistence
  Features/
    Channels/     # Channel list + creation UI (agent picker)
    Chat/         # Chat view, message bubbles, talk button
    Settings/     # All configuration UI
    Setup/        # WhisperKit model download
    Tools/        # Direct tool invocation dashboard
  Models/         # Data models (Message, Channel, AppSettings, ToolTypes, API types)
```

See [ARCHITECTURE.md](ARCHITECTURE.md) for detailed architecture documentation.

## Dependencies

| Package | Purpose |
|---------|---------|
| [WhisperKit](https://github.com/argmaxinc/WhisperKit) | On-device speech-to-text (Apple Neural Engine) |
| [KeychainAccess](https://github.com/kishikawakatsumi/KeychainAccess) | Secure credential storage |
| [MarkdownUI](https://github.com/gonzalezreal/swift-markdown-ui) | Markdown rendering in chat bubbles |

## Security

- **Credentials** stored in iOS Keychain (encrypted by Secure Enclave)
- **HTTPS enforced** — the app rejects plain HTTP connections
- **On-device STT** — audio is transcribed locally, never sent to any server
- **Chat history** stored locally with iOS Data Protection (encrypted at rest)
- **No open ports** — Cloudflare Tunnel / Tailscale handles secure access
- **TLS 1.2 minimum** enforced on all network connections

## License

MIT
