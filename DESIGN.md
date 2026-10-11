# AeroSpaceIconz — design

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
  `window-detected`, `binding-triggered`, `mode-changed`). Restarted with backoff if it exits.
- **State:** on any event, full re-read (~14 ms):
  - `aerospace list-windows --all --json --format '%{window-id} %{app-bundle-id} %{app-name} %{app-pid} %{workspace}'`
    (`--format` is required: plain `--json` omits bundle id and workspace)
  - `aerospace list-workspaces --all --json --format '%{workspace} %{workspace-is-focused} %{workspace-is-visible}'`
  - Redraw only when the derived model differs.
- **Gap coverage** (AeroSpace has no window-closed / window-moved events):
  - NSWorkspace `didTerminateApplication`.
  - Burst re-check at +100 ms and +500 ms after every event, timed from the event itself
    (covers windows that are still listed when their event fires). A newer event restarts the burst.
  - Idle poll every 3 s, paused while displays sleep / screen is locked.
- **AeroSpace not running:** a single dimmed, outlined placeholder pill (`–`); keep retrying.
  `subscribe` sends the current state on connect, so a reconnect refreshes immediately.
- **Switching:** `aerospace workspace <name>`.

## What's shown

- One pill per **non-empty** workspace, plus the **focused** workspace even if empty
  (name only). Order = AeroSpace's `list-workspaces` order.
- Pill = workspace name label + app icons.
  - Deduped: one icon per app (bundle id).
  - Icon order = first time that app appeared on that workspace (stable across refreshes).
  - Max 4 icons per pill, then `+N`.
  - Every window in `list-windows` counts (floating, minimized, hidden).
- **Width budget:** if the total width exceeds `maxTotalWidth` (400 pt), lower the
  per-pill icon cap for non-focused pills 4 → 3 → 2 → 1 until it fits. The focused pill keeps 4.
- **Multi-monitor:** one item, all workspaces. Focused = fill; visible on another monitor = outline.

## Visual style

- Icons 16 pt, 2 pt gap; pills 20 pt tall, 5 pt corner radius, 6 pt between pills.
- Label: system font 11 pt, medium, monospaced digits.
- Focused pill: fill with menu bar label color at ~20 % alpha. Visible-not-focused:
  1 pt stroke. Others: no fill. Icons always full color.
- Rendered as one `NSImage` (drawing-handler based, so it re-renders on appearance
  change) on the status item button. `PillLayout` computes every position (pill, label,
  each icon, `+N`); the renderer only paints at those positions, and clicks are mapped to
  pills with the same layout, so drawing and hit-testing can't drift apart.
- Icons from `NSRunningApplication` (by pid), cached by bundle id, generic app icon fallback.

## Interaction

- Left-click pill → switch workspace.
- Right-click → menu: Refresh, Launch at Login (`SMAppService.mainApp`), Quit.

## Engineering

- Swift package (Command Line Tools only, no Xcode) + `Makefile` that builds release,
  assembles the `.app` with `Info.plist` (`LSUIElement`), ad-hoc codesigns, and installs.
- Tests: Swift Testing (`import Testing`); XCTest isn't available with CLT.
  `IconzCoreTests` covers the core; `AeroSpaceIconzTests` covers app-target glue
  (e.g. subscription process tracking).
- Modules:
  - `IconzCore` (pure, no AppKit): snapshot types, CLI output parsing, the
    snapshot → pills reducer (filtering, dedupe, stable icon order, `+N`, width-fit),
    and the `AeroSpaceClient` protocol. Built test-first.
  - `AeroSpaceIconz` (executable, AppKit): CLI-backed client, event pump / scheduler,
    icon cache, renderer, status item, menu.
- Seam: `AeroSpaceClient` (`snapshot()`, `events()`, `focus(workspace:)`). The real
  implementation runs the CLI; tests use a fake. Time goes through `MonotonicClock`
  (`SystemClock` in the app, a manually advanced fake in tests).
- Debug: `AeroSpaceIconz --render-png <dir>` renders the current state in light and dark
  appearance to PNGs and exits, for checking the drawing without the menu bar.
- All tunables live in one `Config` struct (no TOML in v1).

## aerospace.toml changes

No additions. Cleanup of dead `borders` / `sketchybar` hooks:

```toml
after-startup-command = []
# exec-on-workspace-change block removed
```

## Verified during the build (AeroSpace 0.21.3-Beta)

- Closing a window fires `focus-changed`, but the closed window is still listed at +0 ms
  and gone by +100 ms. The +100 ms burst re-check is what makes closes feel instant.
- `binding-triggered` for `move-node-to-workspace` fires after the move is applied.
  For `workspace N` it fires before `focus-changed` / `focused-workspace-changed`.
- `Process.waitUntilExit()` adds ~60 ms per CLI call (polls the run loop); the client
  waits on `terminationHandler` instead (~18 ms per call).
- `aerospace subscribe` children outlive a killed app until their next write, so the app
  terminates them explicitly on Quit and SIGTERM.

## Out of scope (v1)

Click an icon to focus that app's window, hover tooltips, TOML config, per-monitor grouping.
