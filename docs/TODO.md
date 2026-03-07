# ClawTalk iOS — Feature Roadmap & Research

## Current State

What's built and working:
- Streaming chat via `POST /v1/chat/completions` (SSE)
- Push-to-talk voice input (WhisperKit on-device STT)
- Conversation mode (VAD, auto-listen, interrupt)
- Pluggable TTS (ElevenLabs, OpenAI, Apple)
- Settings UI (gateway config, voice toggles, TTS/STT config)
- Secure credential storage (iOS Keychain)
- HTTPS-only enforcement
- Conversation persistence (local)
- WhisperKit model download with progress bar

---

## Feature Backlog

### Phase 1 — Quick Wins

- [ ] **Multi-agent channels**
  - OpenClaw supports `"openclaw:<agentId>"` in the model field to route to different agents
  - Also supports `x-openclaw-agent-id` header
  - Build a Channel model (name, icon/color, agentId) with a channel list/picker UI
  - Each channel gets its own conversation history
  - Gateway URL + token can be shared or per-channel
  - Reference: `src/gateway/openai-http.ts`

- [ ] **Image sending**
  - Chat completions endpoint accepts base64 images inline
  - Up to 8 images per message, 20 MB total
  - Supported: JPEG, PNG, GIF, WebP, HEIC, HEIF
  - Add photo picker + camera capture to chat input
  - Encode as base64 in the messages array

- [ ] **Stop speaking button in conversation mode**
  - Regular mode already has an X button next to "Speaking..."
  - Add manual stop button to conversation mode UI as well

### Phase 2 — Richer API Support

- [ ] **OpenResponses API (`POST /v1/responses`)**
  - Richer item-based streaming with structured events
  - Supports file attachments (PDF, text, markdown, CSV, JSON — up to 5 MB)
  - Supports function call outputs (feed tool results back to agent)
  - Better streaming event model:
    - `response.created`, `response.in_progress`
    - `response.output_text.delta`, `response.output_text.done`
    - `response.completed`, `response.failed`
  - Token usage reporting
  - Reference: `src/gateway/openresponses-http.ts`
  - Docs: `docs/gateway/openresponses-http-api.md`

- [ ] **Direct tool invocation (`POST /tools/invoke`)**
  - Invoke agent tools without going through chat
  - Request: `{tool, action?, args, sessionKey?, dryRun?}`
  - Response: `{ok, result}` or `{ok: false, error}`
  - Useful tools for mobile:
    - `memory_search` / `memory_get` — browse agent's memory
    - `sessions_list` / `sessions_get` / `sessions_create` — manage sessions
    - `fs_read` / `fs_list` — browse agent's workspace files
    - `browser_screenshot` — see what the agent's browser is doing
  - HTTP deny list: `sessions_spawn`, `sessions_send`, `gateway`, `whatsapp_login`
  - Body limit: 2 MB
  - Reference: `src/gateway/tools-invoke-http.ts`
  - Docs: `docs/gateway/tools-invoke-http-api.md`

- [ ] **Session management**
  - Session key format: `agent:<agentId>:<sessionId>`
  - Isolation modes: `main`, `per-peer`, `per-channel-peer`, `per-account-channel-peer`
  - Could expose session switching in the app (view different conversation threads)
  - Session pruning policies available server-side

### Phase 3 — WebSocket & Real-Time

- [ ] **WebSocket control plane**
  - Protocol v3: `ws://gateway:18789`
  - Lower latency than HTTP SSE for streaming
  - Bidirectional — can receive events (presence, approvals, status)
  - Handshake:
    1. Server sends `connect.challenge` with nonce
    2. Client responds with `connect` (role, scopes, device identity + Ed25519 signature)
    3. Server responds with `hello-ok` + device token
  - Frame types: `req` (request), `res` (response), `event` (push)
  - Key methods: `status`, `channels.list`, `nodes.list`, `chat.stream`, `memory.search`, `tools.catalog`
  - Operator scopes: `operator.read`, `operator.write`, `operator.admin`, `operator.approvals`
  - Requires Ed25519 keypair generation + stable device identity
  - Reference: `src/gateway/server/ws-connection.ts`
  - Docs: `docs/gateway/protocol.md`

- [ ] **Real-time events via WebSocket**
  - Agent status changes
  - Exec approval requests (agent wants to run a command, user approves from phone)
  - Node capability invocations
  - Presence/heartbeat

### Phase 4 — Node Mode (Device as Agent Peripheral)

- [ ] **Register as an OpenClaw node**
  - iOS app registers over WebSocket with role `"node"`
  - Declares capabilities: `camera`, `canvas`, `screen`, `location`, `voice`, `notifications`, `device`
  - Agent can then invoke device features remotely via `node.invoke`
  - Device pairing + approval workflow for security
  - Reference: `docs/platforms/ios.md`

- [ ] **Camera capability**
  - Agent can request photos/video from the phone's camera
  - `camera_snap` / `camera_record` commands
  - Return base64 or upload to agent workspace

- [ ] **Location capability**
  - Agent can request GPS coordinates
  - Useful for location-aware tasks

- [ ] **Canvas/A2UI**
  - Agent-driven visual workspace rendered in WKWebView
  - Agent can push HTML/JS to canvas, evaluate scripts, take snapshots
  - Operations: `canvas_navigate`, `canvas_eval`, `canvas_snapshot`, `canvas_present`
  - Could be a secondary tab/view in the app

- [ ] **Screen capability**
  - Agent can request screenshots of the app/device
  - `screen_snapshot` / `screen_record`

- [ ] **Notifications**
  - Agent can push local notifications to the device

### Phase 5 — Polish & App Store

- [ ] **Model selection** (branch: `feature/model-selection`)
  - Fetch models from `/v1/models` endpoint
  - Picker in Settings
  - Per-request model parameter
  - Currently shelved — endpoint behavior needs investigation

- [ ] **Onboarding flow**
  - First-launch setup wizard
  - Gateway URL + token entry
  - WhisperKit model download
  - Quick test message

- [ ] **App Store submission**
  - Privacy manifest (PrivacyInfo.xcprivacy)
  - App review notes explaining self-hosted gateway requirement
  - Screenshots & marketing copy
  - Pricing: $2.99 (see APP_STORE_PLAN.md)

---

## OpenClaw API Reference (Quick Reference)

### Endpoints

| Endpoint | Method | Purpose | Auth |
|---|---|---|---|
| `/v1/chat/completions` | POST | Streaming chat | Bearer token |
| `/v1/models` | GET | List available models | Bearer token |
| `/v1/responses` | POST | Rich item-based chat (files, tools) | Bearer token |
| `/tools/invoke` | POST | Direct tool invocation | Bearer token |
| WebSocket `:18789` | WS | Control plane, real-time events | Device identity + signature |

### Agent Routing

- Via model field: `"openclaw:main"` (default) or `"openclaw:<agentId>"`
- Via header: `x-openclaw-agent-id: <agentId>`

### Image Support (Chat Completions)

- Max 8 images per request
- Max 20 MB total
- MIME types: image/jpeg, image/png, image/gif, image/webp, image/heic, image/heif
- Format: base64 data URI in message content

### Tool Profiles

- `minimal` — basic tools only
- `coding` — filesystem + exec
- `messaging` — session + channel tools
- `full` — everything

### Tool Groups

- `group:runtime` — exec, process management
- `group:fs` — filesystem read/write
- `group:sessions` — session management
- `group:memory` — memory search/get
- `group:web` — browser control
- `group:ui` — canvas, notifications

### Key Source Files (OpenClaw)

- `src/gateway/openai-http.ts` — Chat completions handler
- `src/gateway/openresponses-http.ts` — Responses API handler
- `src/gateway/tools-invoke-http.ts` — Tool invocation handler
- `src/gateway/server/ws-connection.ts` — WebSocket handshake
- `src/channels/registry.ts` — Channel registry
- `docs/gateway/protocol.md` — WebSocket protocol spec
- `docs/gateway/openai-http-api.md` — Chat API docs
- `docs/gateway/openresponses-http-api.md` — Responses API docs
- `docs/gateway/tools-invoke-http-api.md` — Tool invoke docs
- `docs/platforms/ios.md` — iOS node guide
