# AI Quota Studio

A native macOS **menu bar** app and **WidgetKit widgets** for the desktop and Notification Center
that show 5-hour, weekly and monthly quota usage for **Claude Code**, **Antigravity (AGY)** and
**Codex** — written in **100% Swift**.

---

## ✨ Features

- 🧭 **Menu bar icon:** all quotas at a glance in a compact popover, no Dock icon.
- ⚡️ **Native Swift:** self-contained data collection, no Python scripts, external dependencies
  or system daemons.
- ⏱ **Live quotas:** 5-hour and 7-day windows for Claude Code and Antigravity (Gemini / Claude /
  GPT); Codex windows are 5 hours and a week, or a month on the free plan.
- 🕒 **Countdowns:** time until each window resets; widgets and the menu tick every minute and
  drop the bar to 0% once a window resets.
- 🩺 **Clear errors:** if a CLI is missing or signed out, the menu and the widget say so instead
  of showing an empty card.
- 🌐 **Languages:** English (default) and Russian, switchable in Settings.
- ⚙️ **Settings:** refresh interval (1 minute to 1 hour) and launch at login.
- 🎨 **Widget sizes:** Small and Medium (Antigravity also Large), dark and light appearance.

---

## 🍺 Install

```bash
brew tap speakfo/tap
brew install --cask ai-quota-studio
```

The app is signed ad-hoc and not notarized (there is no paid Apple Developer account behind it),
so the cask removes the quarantine flag after install. Prefer to build it yourself? See below.

---

## 🚀 Build from source

### 0. Requirements
- macOS 26.5+.
- Installed and signed-in CLIs: `claude` (Claude Code), `agy` (Antigravity) and/or `codex`
  (Codex). The app finds them on its own — in the usual directories or via your login shell PATH
  (nvm installs work too).
- Xcode 16+. No Apple Developer account is needed: the build is signed ad-hoc.

### 1. Configure (optional)
Copy the template and put in your bundle ID prefix:

```bash
cp Config/Local.example.xcconfig Config/Local.xcconfig
```

```
BUNDLE_ID_PREFIX = com.yourname
```

If you have an Apple Developer team, you can also enable team signing there: macOS then keeps
privacy permissions across rebuilds. `Config/Local.xcconfig` is ignored by git.

### 2. Build
Open the project in Xcode 16+ and build the `AI Quota Studio` scheme, or run:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project "AI Quota Studio.xcodeproj" -scheme "AI Quota Studio" -configuration Release build
```

### 3. Run
1. Launch **AI Quota Studio**.
2. In Settings, turn on *Launch at login* and pick the interface language if needed.
3. Right-click the desktop → **Edit Widgets** → choose **AI Quota Studio**.

---

## 🛠 How it works

```
AI Quota Studio (menu bar app)
  ├─ ClaudeCollector ──→ `claude -p /usage`
  ├─ AntigravityCollector ──→ `agy -p /usage`
  ├─ CodexCollector ──→ `codex app-server` (account/rateLimits/read)
  └─ QuotaBridge ──→ saves to ~/Library/Application Support/AIQuota and reloads WidgetKit
Desktop widgets (WidgetKit)
  └─ read the same directory (read-only) and redraw the bars
```

The app never talks to Anthropic, Google or OpenAI itself and stores no tokens: it asks the
installed CLIs, which use your existing sign-in.

---

## 📄 License

MIT — see [LICENSE](LICENSE).
