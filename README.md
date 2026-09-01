# Harbormaster

A macOS menu bar app for watching and killing the TCP ports your dev servers are sitting on.

A harbormaster assigns berths and can order a vessel out. Same idea: see what's docked on your
dev ports, and evict it.

Native Swift + SwiftUI (`MenuBarExtra`, macOS 13+). No Electron, no Tauri, no dock icon, no
main window. It replaces a `ports.sh` script + web UI, and stays compatible with the script by
sharing the same label file.

```
 🔌 3   ← menu bar: filled plug + count when ports are listening, outline plug when idle

┌───────────────────────────────────────────────────────┐
│ Ports                                        3 active │
├───────────────────────────────────────────────────────┤
│ 3001   node          [ storefront   ]        [Kill]   │
│        PID 61619                                      │
│ 3002   node          [ admin-dashb… ]        [Kill]   │  <- grey: auto-detected
│        PID 63934                                      │
│ 5432   postgres      [ db           ]        [Kill]   │
│        PID 9041                                       │
├───────────────────────────────────────────────────────┤
│ ↻ Refresh   ⚙ Preferences                      Quit   │
└───────────────────────────────────────────────────────┘
```

## Features

- **Menu bar only** (`LSUIElement`) — an outline plug when nothing is listening, a filled plug
  plus a count badge when ports are active. Both are template images, so macOS tints them
  black or white to match the menu bar, the same as any built-in status item.
- **Watch individual ports**, not a range — `3000`, `5432`, `8080` and `6379` can all be
  watched together without dragging in everything in between.
- **Only active ports are listed.** Idle watched ports are still scanned and still keep their
  labels; they just don't clutter the dropdown.
- **Auto-detected labels** — an unlabeled port shows its project name greyed out, taken from
  the server process's working directory. Type over it to set a real label.
- **Inline labels** — click the text field, type, press Enter or click away to save.
- **Kill** — SIGKILL with an inline two-step confirmation.
- **Auto-refresh** on a timer (default 3s), plus manual refresh (`⌘R`).
- **Preferences** (`⌘,`) — add/remove watched ports, refresh interval, launch at login.

## Requirements

- macOS 13 (Ventura) or later
- Xcode 16 or later to build (Swift Testing is used for the unit tests)

## Build and run

```bash
git clone https://github.com/oppatrickk/harbormaster.git
cd harbormaster

# Build
xcodebuild build -project Harbormaster.xcodeproj -scheme Harbormaster -configuration Release

# Run it from the build directory
open "$(xcodebuild -project Harbormaster.xcodeproj -scheme Harbormaster -configuration Release \
        -showBuildSettings 2>/dev/null \
        | awk -F' = ' '/ BUILT_PRODUCTS_DIR/ {print $2}')/Harbormaster.app"
```

Or just open `Harbormaster.xcodeproj` in Xcode and hit Run.

Nothing appears in the Dock — look for the plug icon in the menu bar.

### Install to /Applications

Recommended, and **required** for launch-at-login to work reliably:

```bash
xcodebuild build -project Harbormaster.xcodeproj -scheme Harbormaster -configuration Release \
  -derivedDataPath ./build
cp -R ./build/Build/Products/Release/Harbormaster.app /Applications/
open /Applications/Harbormaster.app
```

### Run the tests

```bash
xcodebuild test -project Harbormaster.xcodeproj -scheme Harbormaster
```

94 tests across 5 suites covering the `lsof` parsers, the row model, the settings store, and
the label file format. None of them touch your real `~/.ports_labels.tsv` or app settings —
the label tests use a temp directory and the settings tests use an isolated UserDefaults suite.

## Choosing which ports to watch

Preferences → **Watched Ports**. Type a port, press Enter or click Add. Click the ⊖ next to a
port to stop watching it.

Ports are watched individually and don't have to be consecutive. A fresh install watches
3000–3010 (as eleven individual entries), which you can prune or extend.

The dropdown lists only the ports that are actually in use. Watching a port you rarely run is
therefore cheap — it stays out of the list until something binds it.

If you're upgrading from a version that stored a contiguous range, that range is migrated into
the individual ports it covered, so nothing changes out from under you.

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
   `CODE_SIGN_IDENTITY` on the `Harbormaster` target and it becomes reliable.

Any failure is shown inline in Preferences rather than silently flipping the toggle back.

## Labels

An unlabeled port shows a greyed-out guess: the basename of the server process's working
directory, found with `lsof -a -p <pid> -d cwd`. A `vite dev` server started in
`~/Work/streamline_mes_due_soon` shows as `streamline_mes_due_soon`.

This is a placeholder only. It is **never** written to `~/.ports_labels.tsv` — the file shared
with `ports.sh` stays limited to labels you actually typed. Processes running from `/` or from
your bare home directory get no guess, since neither says anything useful.

Lookups are cached per PID and pruned to live processes, so the extra `lsof` call doesn't run
on every refresh tick.

## Label file (`~/.ports_labels.tsv`)

Labels live in `~/.ports_labels.tsv`, tab-separated, one line per labeled port:

```
3000	api
3001	storefront
5432	db
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

> **Note:** killing a port deletes its label line, per the original `ports.sh` contract. You may
> prefer labels to survive a kill so a restarted server keeps its name. That's a one-line
> change — drop the `removeLabel` call in `PortsViewModel.confirmKill`.

## How ports are discovered

One `lsof` call per refresh, with one `-i` flag per watched port:

```
/usr/sbin/lsof -nP -iTCP:3000 -iTCP:3001 -iTCP:5432 -sTCP:LISTEN -F pcn +c 0
```

A few details the implementation depends on, all verified against lsof 4.91 and covered by
tests:

- **Multiple `-i` flags are OR'd**, so one call covers the whole watch list however
  non-contiguous it is.
- **`lsof` exits 1 if *any* search term matched nothing — even when other terms returned
  data.** With one flag per port, a single idle port in your list produces exit 1 alongside
  perfectly good output. Treating exit 1 as failure would break the normal case entirely.
- **With no `-i` flag at all, `lsof` lists every open file on the system** (~30k lines). An
  empty watch list therefore short-circuits and never reaches the process spawn.
- **`-F pcn` (field output), not the column output.** The default `COMMAND` column truncates to
  9 characters, turning `language_server_macos_arm` into `language_`. `+c 0` lifts the limit.
- **Field output is stateful.** A `p<pid>` line opens a process block and `c<command>` names it;
  *several* `f<fd>`/`n<address>` pairs can follow, all belonging to that process.
- **Duplicate rows get collapsed.** A process listening on both IPv4 and IPv6 reports the same
  port on multiple descriptors; results are deduped on `(port, pid)`.
- **Three address shapes** are parsed: `[::1]:3001`, `*:63942`, `127.0.0.1:5037`.

Killing sends `SIGKILL` via `kill(2)`. `ESRCH` (already gone) counts as success; `EPERM` is
reported as "belongs to another user". PIDs are validated as `> 0` first, since `kill(0, …)`
signals an entire process group and `kill(-1, …)` signals everything you own.

## Project layout

```
Harbormaster/
  HarbormasterApp.swift   @main — MenuBarExtra + Preferences window scenes
  PortsViewModel.swift    refresh loop, orchestration (@MainActor)
  Core/                   no UI imports — this is the tested layer
    ListeningPort.swift   a socket found in LISTEN state
    PortRow.swift         a watched port + its listener (if any) + label
    PortScanner.swift     lsof invocation + parsing
    ProcessDirectory.swift  cwd -> project name, for auto-detected labels
    LabelStore.swift      ~/.ports_labels.tsv read/write
    ProcessKiller.swift
    LoginItem.swift       SMAppService wrapper
    Preferences.swift     watched ports, interval, migration
  Views/
    MenuBarLabel.swift    status item icon + count badge
    PortListView.swift
    PortRowView.swift
    PreferencesView.swift
HarbormasterTests/
  PortScannerParsingTests.swift
  PortRowTests.swift
  PreferencesTests.swift
  ProcessDirectoryTests.swift
  LabelStoreTests.swift
```

`Core/` has no SwiftUI/AppKit dependency. `PortScanner` takes a `CommandRunner`, `LabelStore`
takes a file URL, and `Preferences` takes a `UserDefaults`, so all three are testable without
spawning `lsof` or touching your home directory.

## Notes and non-goals

- Not sandboxed, not built for App Store distribution — this is a local dev tool.
- No privilege elevation. You can only kill processes you own; anything else reports `EPERM`.
- `lsof` shows ports owned by other users, but killing them will fail by design.
