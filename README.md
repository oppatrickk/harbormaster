# Ports

A macOS menu bar app for watching and killing the TCP ports your dev servers are sitting on.

Native Swift + SwiftUI (`MenuBarExtra`, macOS 13+). No Electron, no Tauri, no dock icon, no
main window. It replaces a `ports.sh` script + web UI, and stays compatible with the script by
sharing the same label file.

```
 🔌 3   ← menu bar: amber icon + count when ports are listening, dim when idle

┌─────────────────────────────────────────────────────┐
│ Ports 3000–3010                     3 ports active  │
├─────────────────────────────────────────────────────┤
│ 3001   node          [ storefront    ]      [Kill]  │
│        PID 61619                                    │
│ 3002   node          [ admin-api     ]      [Kill]  │
│        PID 63934                                    │
│ 3005   node          [              ]       [Kill]  │
│        PID 71798                                    │
├─────────────────────────────────────────────────────┤
│ ↻ Refresh   ⚙ Preferences                    Quit   │
└─────────────────────────────────────────────────────┘
```

## Features

- **Menu bar only** (`LSUIElement`) — dim icon when nothing is listening, amber icon with a
  count badge when ports are active.
- **One row per listening port** — port number, process name, PID.
- **Inline labels** — click the text field, type, press Enter or click away to save.
- **Kill** — SIGKILL with an inline two-step confirmation.
- **Auto-refresh** on a timer (default 3s), plus manual refresh (`⌘R`).
- **Preferences** (`⌘,`) — port range, refresh interval, launch at login.

## Requirements

- macOS 13 (Ventura) or later
- Xcode 16 or later to build (Swift Testing is used for the unit tests)

## Build and run

```bash
git clone https://github.com/oppatrickk/portside.git
cd portside

# Build
xcodebuild build -project Ports.xcodeproj -scheme Ports -configuration Release

# Run it from the build directory
open "$(xcodebuild -project Ports.xcodeproj -scheme Ports -configuration Release \
        -showBuildSettings 2>/dev/null \
        | awk -F' = ' '/ BUILT_PRODUCTS_DIR/ {print $2}')/Ports.app"
```

Or just open `Ports.xcodeproj` in Xcode and hit Run.

Nothing appears in the Dock — look for the plug icon in the menu bar.

### Install to /Applications

Recommended, and **required** for launch-at-login to work reliably:

```bash
xcodebuild build -project Ports.xcodeproj -scheme Ports -configuration Release \
  -derivedDataPath ./build
cp -R ./build/Build/Products/Release/Ports.app /Applications/
open /Applications/Ports.app
```

### Run the tests

```bash
xcodebuild test -project Ports.xcodeproj -scheme Ports
```

34 tests covering the `lsof` output parser and the label file format. Neither touches the real
`~/.ports_labels.tsv` — the label tests run against a temp directory.

## Launch at login

Open **Preferences → Launch at login** and flip the toggle. It's **off by default**.

This uses `SMAppService` (the modern API, not the deprecated `SMLoginItemSetEnabled` /
`LSSharedFileList` login-item APIs). The toggle reads its state back from
`SMAppService.mainApp.status` rather than caching it, so what you see is what the system
actually has registered.

**Caveat worth knowing about:** `SMAppService` requires a code-signed bundle. This project is
configured for ad-hoc signing (`CODE_SIGN_IDENTITY = "-"`) so it builds on any machine with no
Apple Developer account. Ad-hoc signed apps *can* register as login items, but macOS is
inconsistent about it. If the toggle throws an error:

1. Make sure the app is in `/Applications` and you launched it from there — not from
   `DerivedData`.
2. Check **System Settings → General → Login Items**; macOS may be waiting on your approval.
3. If you do have a Developer ID certificate, set `DEVELOPMENT_TEAM` and
   `CODE_SIGN_IDENTITY` on the `Ports` target and it becomes reliable.

Any failure is shown inline in Preferences rather than silently flipping the toggle back.

## Label file (`~/.ports_labels.tsv`)

Labels live in `~/.ports_labels.tsv`, tab-separated, one line per labeled port:

```
3000	api
3001	storefront
3005	worker-queue
```

This is the same file `ports.sh` uses, and both tools can be used interchangeably:

- Lines are sorted by port ascending, so the file stays diff-stable.
- A port's line is **removed** when its label is cleared or the port is killed.
- Every write re-reads the file first, so a label added by the script between refresh ticks is
  not clobbered.
- Malformed and blank lines are skipped rather than failing the load — it's a hand-editable
  file.
- Reads handle both LF and CRLF line endings.

Edit the file by hand and the app picks it up on the next refresh.

## How ports are discovered

One `lsof` call per refresh over the whole range:

```
/usr/sbin/lsof -nP -iTCP:3000-3010 -sTCP:LISTEN -F pcn +c 0
```

A few details that the implementation depends on, all of which are covered by tests:

- **`-F pcn` (field output), not the column output.** The default `COMMAND` column truncates to
  9 characters, turning `language_server_macos_arm` into `language_`. `+c 0` lifts the limit.
- **Field output is stateful.** A `p<pid>` line opens a process block and `c<command>` names it;
  *several* `f<fd>`/`n<address>` pairs can follow, all belonging to that process.
- **`lsof` exits 1 when it finds nothing.** That's the normal case for a quiet range, not an
  error — treating it as one would show a permanent failure whenever no dev servers are up.
- **Duplicate rows get collapsed.** A process listening on both IPv4 and IPv6 reports the same
  port on multiple descriptors; results are deduped on `(port, pid)`.
- **Three address shapes** are parsed: `[::1]:3001`, `*:63942`, `127.0.0.1:5037`.

Killing sends `SIGKILL` via `kill(2)`. `ESRCH` (already gone) counts as success; `EPERM` is
reported as "belongs to another user". PIDs are validated as `> 0` first, since `kill(0, …)`
signals an entire process group and `kill(-1, …)` signals everything you own.

## Project layout

```
Ports/
  PortsApp.swift          @main — MenuBarExtra + Preferences window scenes
  PortsViewModel.swift    refresh loop, orchestration (@MainActor)
  Core/                   no UI imports — this is the tested layer
    ListeningPort.swift
    PortScanner.swift     lsof invocation + parsing
    LabelStore.swift      ~/.ports_labels.tsv read/write
    ProcessKiller.swift
    LoginItem.swift       SMAppService wrapper
    Preferences.swift
  Views/
    MenuBarLabel.swift    status item icon + count badge
    PortListView.swift
    PortRowView.swift
    PreferencesView.swift
PortsTests/
  PortScannerParsingTests.swift
  LabelStoreTests.swift
```

`Core/` has no SwiftUI/AppKit dependency. `PortScanner` takes a `CommandRunner` and
`LabelStore` takes a file URL, so both are testable without spawning `lsof` or touching your
home directory.

## Notes and non-goals

- Not sandboxed, not built for App Store distribution — this is a local dev tool.
- No privilege elevation. You can only kill processes you own; anything else reports `EPERM`.
- `lsof` shows ports owned by other users, but killing them will fail by design.
