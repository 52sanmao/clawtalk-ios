# ClawTalk iOS — Feature Roadmap & Research

## Current State

What's built and working:
- Streaming chat via `POST /v1/chat/completions` (SSE)
- Open Responses API via `POST /v1/responses` (structured SSE with token usage)
- Push-to-talk voice input (WhisperKit on-device STT)
- Conversation mode (VAD, auto-listen, interrupt, echo cancellation)
- Pluggable TTS (ElevenLabs, OpenAI, Apple)
- Multi-agent channels (per-agent routing via `openclaw:<agentId>`)
- Image sending (up to 8 per message, base64 JPEG, both APIs)
- Settings UI (gateway config, API mode, voice toggles, TTS/STT config, token usage display)
- Secure credential storage (iOS Keychain)
- HTTPS-only enforcement
- Conversation persistence (per-channel, local)
- WhisperKit model download with progress bar
- Markdown rendering in assistant messages
- Stop speaking button (both regular and conversation mode)

---

## Feature Backlog

### Phase 1 — Quick Wins

- [x] **Multi-agent channels**
  - OpenClaw supports `"openclaw:<agentId>"` in the model field to route to different agents
  - Also supports `x-openclaw-agent-id` header
  - Channel model (name, emoji, agentId) with channel list/picker UI
  - Each channel gets its own conversation history

- [x] **Image sending**
  - Both Chat Completions and Open Responses endpoints accept base64 images
  - Up to 8 images per message, 20 MB total
  - Photo picker + camera capture in chat input
  - Supported: JPEG, PNG, GIF, WebP, HEIC, HEIF

- [x] **Stop speaking button in conversation mode**
  - Available in both regular and conversation mode UI

### Phase 2 — Richer API Support

- [x] **OpenResponses API (`POST /v1/responses`)**
  - Richer item-based streaming with structured events
  - Event types: `response.output_text.delta`, `response.completed`, `response.failed`
  - Token usage reporting (input/output counts)
  - Configurable via Settings (API Mode picker)
  - Requires `gateway.http.endpoints.responses.enabled: true`

- [ ] **Fix `input_tokens` reporting in Open Responses API**
  - Gateway reports incorrect `input_tokens` in `response.completed` events
  - Short messages can show higher counts than long ones — values don't correlate with input length
  - `output_tokens` and `total_tokens` appear accurate
  - Fix likely in `src/gateway/openresponses-http.ts`
  - Once fixed, restore `input/output` token display in ClawTalk (currently output-only)

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

### Phase 5 — Polish

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
