# ClawTalk — Demo Recording Guide

Scripted prompts and instructions for capturing App Store previews and screenshots.

---

## Setup

1. In Xcode: **Edit Scheme > Run > Arguments** — add the launch argument for the template you want
2. Build and run on the **iPhone 15 Pro Max** simulator (6.7" — required for App Store)
3. Start screen recording: **Simulator > File > Record Screen**
4. Navigate into the channel, scroll up briefly to show conversation history
5. Type (or speak via mic) the scripted prompt below
6. Wait for the full streaming response to finish
7. Stop recording

---

## Template: General Assistant

**Launch argument:** `--seed-demo general`

**Seeded context:** Casual Q&A — weather, memory preference.

**Scripted prompt (type):**
> What's the current time in Tokyo?

*Why this works:* Produces a short 1-2 sentence response that streams quickly — perfect for a 15-30s recording without awkward waiting.

---

## Template: Coding

**Launch argument:** `--seed-demo coding`

**Seeded context:** SwiftUI animation questions — pulsing views, ripple effects, button styles.

**Scripted prompt (type):**
> What does the `withAnimation` closure return?

*Why this works:* Short technical answer (1-3 sentences), shows the app handling code questions without a long code block eating up recording time.

---

## Template: Creative Writing

**Launch argument:** `--seed-demo creative`

**Seeded context:** Writing a portfolio bio and tagline.

**Scripted prompt (type):**
> Which tagline is your favorite and why?

*Why this works:* Short opinionated answer referencing the seeded conversation — shows memory/context. 2-3 sentences max.

---

## Template: Tools & Research

**Launch argument:** `--seed-demo tools`

**Seeded context:** Checking gateway sessions, searching memory for deadlines, weekend planning.

**Scripted prompt (type):**
> Which deadline is the most urgent right now?

*Why this works:* Short answer referencing the seeded deadlines — 1-2 sentences. Shows the agent has context without a long response.

---

## Template: All (Multi-Channel)

**Launch argument:** `--seed-demo all`

Creates 4 channels (Main, Code Help, Writing, Research) each with their own seeded conversation. Good for:
- **Channel list screenshot** — shows multiple active channels
- **Scrolling through different conversations** in a single recording

---

## Voice Demo (Conversation Mode)

Best recorded on the **General** or **Creative** template.

1. Seed with `--seed-demo general`
2. Open the Main channel
3. **Tap** the mic button (enters conversation mode)
4. Say clearly: **"What's a good book to read this month?"**
5. Let it transcribe, send, stream the response, and speak it back via TTS
6. The full loop (listen > transcribe > send > stream > speak) is the money shot

**Push-to-talk variant:**
1. **Hold** the mic button
2. Say: **"Remind me to buy groceries later"**
3. Release — shows the PTT flow

---

## Screenshot Shot List

After seeding, capture these static screenshots (pause recording or use Cmd+S in Simulator):

| # | What | How to Get There |
|---|------|-----------------|
| 1 | Welcome screen | Fresh install (no `--seed-demo`), first launch |
| 2 | Text conversation | `--seed-demo general`, open Main channel |
| 3 | Code conversation | `--seed-demo coding`, open channel, scroll to show code block |
| 4 | Voice mode active | Tap mic button, capture while "Listening..." is showing |
| 5 | Channel list | `--seed-demo all`, stay on channel list screen |
| 6 | Tools dashboard | Open Tools tab (wrench icon) |
| 7 | Settings | Open Settings, show gateway config section |
| 8 | Model picker | Open model picker (CPU icon in nav bar, requires WebSocket) |

---

## App Preview Specs

- **Duration:** 15–30 seconds each
- **Resolution:** 1290 x 2796 (iPhone 15 Pro Max)
- **Format:** H.264 or HEVC, .mp4 or .mov
- **Audio:** Optional (autoplays muted in App Store)
- **Max previews:** 3

### Recommended 3 Previews

1. **Voice conversation** — General template, mic tap, full voice loop
2. **Text chat with code** — Coding template, type prompt, streaming markdown response
3. **Multi-channel + tools** — All template, flip between channels, open tools dashboard

---

## Tips

- **Scroll speed matters** — scroll slowly through history so text is readable in the preview
- **Pause on the response** — let the camera linger on a fully rendered response for 2-3 seconds
- **Dark mode is default** — the app looks best in dark mode, which is what ships
- **Clean the status bar** — in Simulator, the clock and carrier are already clean
- **Trim dead time** — cut any loading/waiting at the start before the UI appears
