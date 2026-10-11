# AeroSpaceIconz — spec & design

The source of truth for what the app does and why. Update it in the same change when a
decision changes.

A native macOS menu bar status item that shows, for each AeroSpace workspace, the
icons of the apps with windows on it. Click a workspace to switch to it.

Target: macOS 15 Sequoia, SIP on, no private APIs, stock AeroSpace (Homebrew,
verified against 0.21.3-Beta).

## Requirements

Hard requirements; everything below is how they're met.

1. Updates feel as instant as AeroSpace's own menu bar indicator when switching
   workspaces, opening/closing apps, or moving windows between workspaces.
2. Runs on macOS 15 Sequoia with SIP enabled. No private APIs, no SIP changes.
3. Works with stock AeroSpace (not a fork), installed via Homebrew.
4. Light on CPU and battery while idle.
5. A native status item in the existing menu bar (not a replacement bar), movable with
   Cmd-drag and Ice. No Dock icon, no main window.
6. Each workspace is a pill holding the icons of the apps with windows on it; the
   focused workspace is highlighted; clicking a workspace switches to it.
7. The AeroSpace CLI sits behind one seam, so the workspace/app model and its logic
   are built test-first without AeroSpace running.

## Shape

- One `NSStatusItem`, `LSUIElement` (no Dock icon, no windows).
- App: `AeroSpaceIconz.app`, bundle id `local.aerospace-iconz`, installed to `~/Applications`.
- Fixed `autosaveName` so the position survives restarts, Cmd-drag and Ice.
  AeroSpace's own tray icon goes in Ice's "Always Hidden" section (manual step).

## Data source & events

Everything goes through the public `aerospace` CLI.

- **Events:** one long-lived child process `aerospace subscribe --all` emitting JSON
  lines (`focus-changed`, `focused-workspace-changed`, `focused-monitor-changed`,
  `window-detected`, `binding-triggered`, `mode-changed`). Restarted if it exits, after
  1 / 2 / 5 / 10 s for consecutive failures; the first event after a restart resets the backoff.
- **State:** on any event, full re-read (two CLI calls in parallel, ~15–18 ms each):
  - `aerospace list-windows --all --json --format '%{window-id} %{app-bundle-id} %{app-name} %{app-pid} %{workspace}'`
    (`--format` is required: plain `--json` omits bundle id and workspace)
  - `aerospace list-workspaces --all --json --format '%{workspace} %{workspace-is-focused} %{workspace-is-visible}'`
  - Redraw only when the derived model differs.
  - Re-reads never overlap: one requested while another is in flight runs once, afterwards.
  - Every CLI call is killed after 2 s (`cliTimeout`), so a stuck `aerospace` can't stall
    the bar; the killed call counts as a failed read.
- **Gap coverage** (AeroSpace has no window-closed / window-moved events):
  - NSWorkspace `didTerminateApplication`.
  - Burst re-check at +100 ms and +500 ms after every event, timed from the event itself
    (covers windows that are still listed when their event fires). A newer event restarts the burst.
  - Idle poll every 3 s. Stopped (no timer at all) while the displays sleep or the screen is
    locked (`com.apple.screenIsLocked` / `screenIsUnlocked` distributed notifications), and
    until both clear; resuming re-reads at once. Events still re-read while paused.
- **AeroSpace not running:** a single dimmed, outlined placeholder pill (`–`); keep retrying.
  `subscribe` sends the current state on connect, so a reconnect refreshes immediately.
  Any failed read (CLI missing, non-zero exit, timeout, unparseable output) shows the
  placeholder; the next good read clears it. A read cancelled mid-burst changes nothing.
- **Switching:** `aerospace workspace <name>`.

## What's shown

- One pill per **non-empty** workspace, plus the **focused** workspace even if empty
  (name only). Order = AeroSpace's `list-workspaces` order.
- Pill = workspace name label + app icons.
  - Deduped: one icon per app (bundle id).
  - Icon order = first time that app appeared on that workspace (stable across refreshes).
    Apps new in the same read are ordered by their oldest window id (a proxy for creation
    order); an app that leaves and comes back goes to the end.
  - Max 4 icons per pill, then `+N`.
  - Every window in `list-windows` counts (floating, minimized, hidden).
- **Width budget:** if the total width exceeds `maxTotalWidth` (400 pt), lower the
  per-pill icon cap for non-focused pills 4 → 3 → 2 → 1 until it fits. The focused pill keeps 4.
- **Multi-monitor:** one item, all workspaces. Focused = fill; a non-empty workspace visible
  on another monitor = outline. An empty workspace on another monitor is hidden like any
  other empty one: the only empty pill ever shown is the focused workspace.

## Visual style

Exact values live in `Config.swift`.

- Icons 16 pt, 2 pt gap, 4 pt between label and first icon; pills 20 pt tall, 5 pt
  horizontal padding, 5 pt corner radius, 6 pt between pills.
- Label: system font 11 pt, medium, monospaced digits. `+N` at 55 % of the label color.
- Focused pill: fill with menu bar label color at ~20 % alpha. Visible-not-focused:
  1 pt stroke at 35 %. Others: no fill. Icons always full color. Placeholder: whole image at 40 %.
- Rendered as one `NSImage` (drawing-handler based, so system colors resolve at draw time)
  on the status item button, redrawn when the button's `effectiveAppearance` changes.
  `PillLayout` computes every position (pill, label, each icon, `+N`); the renderer only
  paints at those positions, and clicks are mapped to pills with the same layout (including
  the image's centering in the button), so drawing and hit-testing can't drift apart.
- Icons from `NSRunningApplication` (by pid), else the installed app (by bundle id),
  cached by app key. An icon not available yet (app still launching) is drawn as the
  generic app icon and looked up again: redraw every 1 s, up to 5 times per state.

## Interaction

- Left-click pill → switch workspace. A click in the gap between pills goes to the nearer
  one; past either end, to the end pill.
- Right-click or Ctrl-click → menu: Refresh, Launch at Login (`SMAppService.mainApp`), Quit.
  - Launch at Login is checked when enabled. When macOS needs the user to allow it, it shows
    mixed with "(Allow in System Settings…)" and opens Login Items. A failed toggle shows an alert.

## Engineering

- Swift package (Command Line Tools only, no Xcode) + `Makefile` that builds release,
  assembles the `.app` with `Info.plist` (`LSUIElement`), ad-hoc codesigns, and installs.
- Tests: Swift Testing (`import Testing`); XCTest isn't available with CLT.
  `IconzCoreTests` covers the core; `AeroSpaceIconzTests` covers app-target glue
  (e.g. subscription process tracking).
- Modules:
  - `IconzCore` (pure, no AppKit), built test-first:
    - `Snapshot`: what AeroSpace reports (`WorkspaceInfo`, `WindowInfo`), plus the
      `WorkspaceName` and `AppKey` (bundle id, else app name) types.
    - `CLIParsing`: CLI arguments and JSON decoding; `LineSplitter` for the `subscribe` stream.
    - `WorkspaceReducer`: snapshot → workspace groups (filtering, dedupe, stable icon order).
    - `PillLayout`: groups or unavailable state → pills with every position (`+N`, width-fit,
      hit-testing). The placeholder pill has no workspace, so clicks on it do nothing.
    - `RefreshCoordinator`: when to re-read (events, bursts, poll, pause reasons, reconnect
      backoff); publishes `BarState` on change.
    - `AeroSpaceClient` and `MonotonicClock` seams, `Config`.
  - `AeroSpaceIconz` (executable, AppKit, thin glue): `CLIClient` (runs the CLI with a
    timeout), `Subscriptions` (live `subscribe` children), `IconCache`, `PillRenderer`,
    `StatusController` (status item, clicks, menu), `LaunchAtLogin` (menu item per
    `SMAppService` status), `AppDelegate` (wiring, sleep/lock/app-quit notifications,
    SIGTERM), `DebugRender`.
- Seam: `AeroSpaceClient` (`snapshot()`, `events()`, `focus(workspace:)`). The real
  implementation runs the CLI; tests use a fake. Time goes through `MonotonicClock`
  (`SystemClock` in the app, a manually advanced fake in tests).
- Debug: `AeroSpaceIconz --render-png <dir>` reads the live AeroSpace, renders the current
  state in light and dark appearance to PNGs in `<dir>` (created if needed), prints their
  paths and exits; it says so when AeroSpace wasn't reachable. For checking the drawing
  without the menu bar.
- All tunables live in one `Config` struct (no TOML in v1).

## aerospace.toml

The app needs nothing in `~/.config/aerospace/aerospace.toml`. Changes made alongside it
(original backed up at `aerospace.toml.before-iconz`):

- Dead `borders` / `sketchybar` hooks removed: `after-startup-command = []`, no
  `exec-on-workspace-change`.
- `on-focus-changed = 'move-mouse window-lazy-center'` removed at the user's request: on
  workspaces holding only floating windows it threw the cursor to a screen corner.

## Verified during the build (AeroSpace 0.21.3-Beta)

- Closing a window fires `focus-changed`, but the closed window is still listed at +0 ms
  and gone by +100 ms. The +100 ms burst re-check is what makes closes feel instant.
- `binding-triggered` for `move-node-to-workspace` fires after the move is applied.
  For `workspace N` it fires before `focus-changed` / `focused-workspace-changed`.
- `Process.waitUntilExit()` adds ~60 ms per CLI call (polls the run loop); the client
  waits on `terminationHandler` instead (~18 ms per call).
- `aerospace subscribe` children outlive a killed app until their next write, so the app
  terminates them explicitly on Quit and SIGTERM.
- A subscription's pipe EOF and its process exit arrive in either order. Ending the
  stream on whichever came first dropped trailing events and left the process tracked
  (17/20 test runs failed); the stream now ends only after both.

## Decided against

- Normalizing app icons to one visual size. Some icons fill more of their box than
  others (Obsidian is edge to edge; VS Code, Raycast, Ice are slightly small); the user
  chose to keep icons exactly as macOS provides them.

## Out of scope (v1)

Click an icon to focus that app's window, hover tooltips, TOML config, per-monitor grouping.
