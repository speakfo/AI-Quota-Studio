# AGENTS.md

Repository guide for coding agents.

## What this is

A native macOS menu bar app, "AI Quota Studio", plus a WidgetKit extension: desktop widgets
showing quota usage for Claude Code, Antigravity and Codex. The project is **100% Swift**, with
no external scripts.

The app runs as a menu bar agent (`LSUIElement = true`): no Dock icon, a compact status popover
opens from the menu bar icon.

Percentages everywhere show **usage**, not what is left, so the numbers match `/usage` in
Claude Code.

## Language

Code, comments, logs and docs are in English. The UI is localized (English by default, Russian
available) and the language is picked in Settings, independently of the system language:

- Translations live in `Shared/Localizable.xcstrings`; the key is the English text.
- Visible strings go through `L10n.tr("…")` / `L10n.tr("… %@", arg)` (`Shared/L10n.swift`),
  which looks up the `.lproj` of the chosen language. Use `Text(verbatim:)` for text that must
  not be localized (numbers, product names).
- The choice is stored in the App Group defaults (`L10n.languageKey`), so the sandboxed widget
  renders in the same language. Changing it reloads widget timelines.
- Widget gallery names (`configurationDisplayName`, `description`) are resolved by the system
  in the system language — WidgetKit does not let the app choose.
- `STRING_CATALOG_GENERATE_SYMBOLS` is off: keys like "No data" and "no data" would clash.

To add a language: add a case to `AppLanguage`, add translations to the catalog and the region
to `knownRegions` in `project.pbxproj`.

## Building

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

# The app; the extension is built as a dependency and embedded into the .app
xcodebuild -project "AI Quota Studio.xcodeproj" -scheme "AI Quota Studio" -configuration Debug build

# The extension only
xcodebuild -project "AI Quota Studio.xcodeproj" -scheme AIQuotaWidgetExtension build
```

Bump `CURRENT_PROJECT_VERSION` whenever widgets change: macOS caches the widget list per build
number and may not notice a new widget otherwise.

## Project layout

The project uses Xcode 16 synchronized groups (`PBXFileSystemSynchronizedRootGroup`).
- `AI Quota Studio/` → the menu bar app
- `AIQuotaWidget/` → the widget extension
- `Shared/` → models, collectors and localization, compiled into both targets
  (`ClaudeCollector`, `AntigravityCollector`, `CodexCollector`, `CLIRunner`, `CLILocator`,
  `QuotaSnapshot`, `QuotaStore`, `QuotaConfig`, `L10n`, `Localizable.xcstrings`)
- `Config/` → signing and identifiers (`Base.xcconfig`, `Local.example.xcconfig`, `App-Info.plist`)
- Entitlements: `Entitlements/App.entitlements`, `Entitlements/AIQuotaWidget.entitlements`
- App Group: `$(DEVELOPMENT_TEAM).$(BUNDLE_ID_PREFIX).AIQuota`

## Data flow

```
AI Quota Studio (QuotaBridge, background timer with a configurable interval)
  ├─ ClaudeCollector ──→ `claude -p /usage --output-format json`
  ├─ AntigravityCollector ──→ `agy --print-timeout 30s -p /usage`
  ├─ CodexCollector ──→ `codex app-server`, JSON-RPC `account/rateLimits/read`
  │    └─ all locate the CLI via CLILocator and run it via CLIRunner
  ├─ QuotaStore.save ──→ <App Group>/AIQuota/<provider>-quota.json
  │                      ──→ WidgetCenter.reloadAllTimelines()
  └─ collection error (CollectorError) ──→ <App Group>/AIQuota/<provider>-error.json,
                                           removed on success
Desktop widgets (WidgetKit, sandboxed)
  └─ QuotaStore.load reads the same files from the App Group
```

The App Group is the only storage: the app is not sandboxed but has the group entitlement, the
widget is sandboxed with the same entitlement. There are no other copies. Both the menu and the
widget read the error file: the widget shows the reason ("agy not found", "sign in to agy")
instead of "No data" or "data is stale". If a CLI is not found and there has never been data
for it, its card is hidden from the menu. A failed attempt also waits for the interval, so a
broken CLI is not hammered every 30 seconds.

## Codex

Codex has no `/usage` in non-interactive mode, so `CodexCollector` starts `codex app-server`,
writes `initialize` → `initialized` → `account/rateLimits/read` to stdin and kills the process
as soon as the response with `id: 2` arrives (`CLIRunner.run(input:until:)`). The request goes
straight to OpenAI and does not spend messages.

Windows are mapped by `windowDurationMins`, not by `primary`/`secondary`:
300 → `five_hour`, 10080 → `seven_day`, 43200 → `thirty_day`. Plus/Pro get 5 hours and a week,
the free plan only a month (`secondary: null`). The Codex menu card and widget build rows via
`QuotaSnapshot.codexRows`: "5 hours" is always present (without a window it is a dimmed
"not in your plan" row), longer windows only when they arrive.

## Locating CLIs

A menu bar app starts with a trimmed PATH, so `CLILocator` first checks the usual directories
(`~/.local/bin`, `~/.claude/local`, Homebrew, `/usr/local/bin`, `~/.npm-global/bin`, volta, bun),
then asks an interactive login shell (`$SHELL -l -i -c 'whence -p … || type -P …'`) — that is
how nvm installs are found. The path is cached. `CLIRunner` adds the binary's directory to PATH,
otherwise an npm script with `#!/usr/bin/env node` cannot find node.

## Signing and identifiers

No personal identifiers live in the repository. `Config/Base.xcconfig` (the project-level base
configuration) defines `DEVELOPMENT_TEAM`, `BUNDLE_ID_PREFIX` and the derived `APP_GROUP_ID`, and
includes the git-ignored `Config/Local.xcconfig` with the developer's own values (template:
`Config/Local.example.xcconfig`).

- Bundle IDs: `$(BUNDLE_ID_PREFIX).AI-Quota-Studio` and `….AIQuotaWidget`.
- Both `.entitlements` files use `$(APP_GROUP_ID)`.
- Code reads the group from the `AIQuotaAppGroup` Info.plist key (`Config/App-Info.plist` for the
  app, `AIQuotaWidget/Info.plist` for the widget), filled from `$(APP_GROUP_ID)` at build time —
  see `QuotaStore.appGroupID`.

Do not put `DEVELOPMENT_TEAM` or bundle IDs back into target settings: they would override the
xcconfig. Deployment target is macOS 26.5.

## Running CLIs in the background: what not to do

When `agy` loses its silent auth it falls back to interactive OAuth and opens a Google sign-in
tab. From a background poll this looks like browser tabs popping up on their own. The trigger is
system sleep: a closed-lid laptop wakes into DarkWake for a few seconds, the timer manages to
start the CLI, the system goes back to sleep and freezes the process mid TLS handshake. Half an
hour later `agy` sees expired deadlines, decides it is signed out and calls the browser.

Hence three rules in the code — do not remove them:

1. **CLIs run only through `CLIRunner`.** It puts a stub `open` first in `PATH` (and sets it as
   `$BROWSER`), so a background process physically cannot open a tab.
2. **Wall-clock timeouts** (`wait(wallTimeout:)`). Plain `DispatchTime` stops while the system
   sleeps: a hung process lived for tens of minutes instead of 30 seconds. On timeout — SIGTERM,
   then SIGKILL.
3. **`QuotaBridge` is power-aware.** Polling happens only while the display is awake
   (`CGDisplayIsAsleep`), running CLIs are killed on `NSWorkspace.willSleepNotification`, and
   after wake-up there is a pause for the network to come back.

Diagnostics: `agy` logs are in `~/.gemini/antigravity-cli/log/`. The tell-tale chain is
`keyringAuth: timed out after 10s` → `silent auth failed` → `triggering interactive OAuth` →
`consumerOAuth: starting OAuth flow`.
