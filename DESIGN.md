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
- App icon (seen in Launchpad, Finder, Spotlight, Login Items; never in the Dock): the
  focused pill "2" with three app tiles (orange, blue, purple), floating on a navy-to-plum
  gradient with a coral glow, no menu bar band. The pill uses v1's pill proportions
  (16 pt icons, 20 pt tall) at 9.5 px per pt on the 1024 grid, label at 1.45× v1's 11 pt;
  neighbouring pills would fall outside the squircle, so only the focused one shows. Chosen
  from a two-round prototype kept on branch `prototype/app-icon`.
- Fixed `autosaveName` so the position survives restarts, Cmd-drag and Ice.
  AeroSpace's own tray icon goes in Ice's "Always Hidden" section (manual step).

## Data source & events

Everything goes through the public `aerospace` CLI.

- **Events:** one long-lived child process `aerospace subscribe --all` emitting JSON
  lines (`focus-changed`, `focused-workspace-changed`, `focused-monitor-changed`,
  `window-detected`, `binding-triggered`, `mode-changed`). Restarted if it exits, after
  1 / 2 / 5 / 10 s for consecutive failures; the first event after a restart resets the backoff.
- **State:** on any event, full re-read (two or three CLI calls in parallel, ~15–18 ms each):
  - `aerospace list-windows --all --json --format '%{window-id} %{app-bundle-id} %{app-name} %{app-pid} %{workspace}'`
    (`--format` is required: plain `--json` omits bundle id and workspace)
  - `aerospace list-workspaces --all --json --format '%{workspace} %{workspace-is-focused} %{workspace-is-visible}'`
  - plus `aerospace list-modes --current --json` (the binding mode, for the mode badge) in
    parallel, on every re-read except the idle poll's. Every mode change fires an event, so
    the poll reuses the last mode; reading it there too cost ~0.3 % idle CPU (see Verified).
    After a failed `list-*` read the next re-read, poll included, reads the mode again. The
    mode is decoration: if only its read fails, the badge is hidden (the bar stays
    available) until the next event re-reads it, so an unreadable mode costs no idle CPU.
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
- **Focusing a window:** `aerospace focus --window-id <id>`. Which windows an app has on a
  workspace comes from the last good re-read, kept by the coordinator but not part of the
  drawn model (so windows coming and going don't redraw). The focused window is read only at
  click time: `aerospace list-windows --focused --json --format '%{window-id}'`.
- **Window menu:** read when it's asked for, never stored, two calls in parallel:
  `aerospace list-windows --workspace <name> --json --format '%{window-id} %{app-bundle-id} %{app-name} %{app-pid} %{workspace} %{window-title}'`
  (~25 ms; there is no `%{window-is-focused}`) and the focused-window read above. The menu
  opens once both are in, or after `windowMenuTimeout` (0.5 s, shorter than `cliTimeout` so
  a stuck `aerospace` can't hold it back long): windows not read by then make it unreadable;
  a focus not read by then, or failed, only leaves nothing checked. A late call keeps running
  until `cliTimeout` kills it, and its answer is dropped. From the click that asks for a menu
  until it closes, further menu clicks are ignored (`MenuGate`, held by the status item, since
  the menu pops up a run loop pass after the read), so repeated clicks open one menu. Costs
  nothing while idle.

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
- **Width budget:** if the total width exceeds `maxTotalWidth` (500 pt), lower the
  per-pill icon cap for non-focused pills 4 → 3 → 2 → 1 until it fits. The focused pill keeps 4.
- **Mode badge:** while AeroSpace's binding mode is not in `hiddenModes` (default `main`),
  a badge pill with the mode name comes before the first workspace pill. It counts toward
  the width budget but has no icons, so it's never shrunk. Clicking it does nothing.
- **Multi-monitor:** one item, all workspaces. Focused = fill; a non-empty workspace visible
  on another monitor = outline. An empty workspace on another monitor is hidden like any
  other empty one: the only empty pill ever shown is the focused workspace.

## Visual style

Exact values live in `Config.swift`.

- Icons 20 pt, 2 pt gap, 4 pt between label and first icon; pills 24 pt tall (the full
  height of the status item, see Verified), 6 pt horizontal padding, 6 pt corner radius,
  6 pt between pills. Chosen over 16 pt icons (v1) and four other styles (tabs, segmented
  control, overlapping stacks, number badged on the icon) from a prototype kept on branch
  `prototype/menubar-styles`.
- Label: system font 12 pt, medium, monospaced digits. `+N` at 55 % of the label color.
- Focused pill: fill with menu bar label color at ~20 % alpha. Visible-not-focused:
  1 pt stroke at 35 %. Others: no fill. Icons always full color. Placeholder: whole image at 40 %.
- Mode badge: same size and corner radius as a pill, `systemOrange` fill, white label.
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
  one; past either end, to the end pill. The mode badge and the placeholder do nothing.
- Left-click an icon (the icon plus half the icon gap on each side) → focus that app's
  oldest window (lowest id) on that workspace. If one of that app's windows there is
  already focused, focus its next one instead, wrapping around. If the focused window can't
  be read, it counts as not focused. If the app has no window there any more, or the focus
  fails, switch to the workspace instead. Label, padding and gaps still switch.
  Each click reads focus on its own, so a fast double-click advances one window, not two.
- Left-click `+N` (with half the icon gap on each side, like an icon) → that pill's window
  menu.
- Right-click or Ctrl-click → menu. On a pill (found the way a left-click finds it: gaps to
  the nearer pill, past either end to the end pill) the menu starts with that workspace's
  windows; on the mode badge or the placeholder it has only the global items:
  - A "Workspace <name>" section header, then one row per window on that workspace: the app
    icon (16 pt) and the window title, or the app name when the title is empty. Titles over
    60 characters are cut in the middle with "…"; duplicate titles stay as they are. Rows go
    in the pill's icon order, then window id; apps not on the pill yet (new since its last
    read) come after, by oldest window, where the pill would add them. The focused window is
    checked. Choosing a row focuses that window (`focus --window-id`); if it's gone or the
    focus fails, it switches to the workspace instead, as an icon click does.
  - No windows (only the focused workspace can be empty): a disabled "No windows" row.
    Windows not read: a disabled "Couldn't read windows" row.
  - Then a separator and the global items: Refresh, Launch at Login (`SMAppService.mainApp`),
    a separator, Quit.
  - Launch at Login is checked when enabled. When macOS needs the user to allow it, it shows
    mixed with "(Allow in System Settings…)" and opens Login Items. A failed toggle shows an alert.

## Engineering

- Swift package (Command Line Tools only, no Xcode) + `Makefile` that builds release,
  assembles the `.app` with `Info.plist` (`LSUIElement`) and `AppIcon.icns`, ad-hoc
  codesigns, and installs. `scripts/make-app-icon.swift` draws the icon with CoreGraphics at
  every iconset size; `make icon` regenerates the committed `Resources/AppIcon.icns`.
- Tests: Swift Testing (`import Testing`); XCTest isn't available with CLT.
  `IconzCoreTests` covers the core; `AeroSpaceIconzTests` covers app-target glue
  (e.g. subscription process tracking).
- Modules:
  - `IconzCore` (pure, no AppKit), built test-first:
    - `Snapshot`: what AeroSpace reports (`WorkspaceInfo`, `WindowInfo`, and `TitledWindow`
      for the window menu), plus the `WorkspaceName`, `WindowId` and `AppKey` (bundle id,
      else app name) types. The binding mode is read separately and travels in `BarState`.
    - `CLIParsing`: CLI arguments and JSON decoding; `LineSplitter` for the `subscribe` stream.
    - `WorkspaceReducer`: snapshot → workspace groups (filtering, dedupe, stable icon order).
    - `PillLayout`: groups or unavailable state → pills with every position (mode badge, `+N`,
      width-fit, hit-testing: a `Selection` (workspace or app icon) or `+N`'s window menu; and
      the workspace a right-click lands on). The placeholder and the badge have no workspace:
      a left-click on them does nothing, a right-click opens only the global items.
    - `WindowMenu`: a workspace's titled windows → header, rows (order, label, truncation,
      focus) and the notice shown when there are none.
    - `RefreshCoordinator`: when to re-read (events, bursts, poll, pause reasons, reconnect
      backoff); publishes `BarState` on change; carries out selections (`select`: which
      window to focus, or which workspace); reads window menus (`windowMenu(for:)`) within
      `windowMenuTimeout`.
    - `MenuGate`: one status item menu at a time, from the click until it closes.
    - `AeroSpaceClient` and `MonotonicClock` seams, `Config`.
  - `AeroSpaceIconz` (executable, AppKit, thin glue): `CLIClient` (runs the CLI with a
    timeout), `Subscriptions` (live `subscribe` children), `IconCache`, `PillRenderer`,
    `StatusController` (status item, clicks, menu), `LaunchAtLogin` (menu item per
    `SMAppService` status), `AppDelegate` (wiring, sleep/lock/app-quit notifications,
    SIGTERM), `DebugRender`.
- Seam: `AeroSpaceClient` (`snapshot()`, `mode()`, `events()`, `focus(workspace:)`,
  `focusedWindowId()`, `focus(windowId:)`, `windows(on:)`). The real implementation runs the
  CLI; tests use a fake. Time goes through `MonotonicClock` (`SystemClock` in the app, a
  manually advanced fake in tests).
- Debug: `AeroSpaceIconz --render-png <dir> [--mode <name>]` reads the live AeroSpace, renders
  the current state in light and dark appearance to PNGs in `<dir>` (created if needed),
  prints their paths and exits; it says so when AeroSpace wasn't reachable. `--mode`
  overrides the binding mode, to see the badge without entering that mode. For checking
  the drawing without the menu bar. `AeroSpaceIconz --print-window-menu <workspace>` prints
  that workspace's window menu rows (checkmark, window id, label as shown) from the live
  AeroSpace and exits.
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

- `focus --window-id` on a window in another workspace switches to that workspace and
  focuses the window (exit 0). An id that no longer exists exits 2 and changes nothing.
- `list-windows --focused --json --format '%{window-id}'` → `[{"window-id": …}]`.
- Idle CPU over 5 minutes (CPU-time delta from `ps`, at the 3 s poll): v1 app 0.143 %;
  with `list-modes` on every poll 0.213 %, plus each `aerospace` child costs ~8 ms CPU
  (≈ 0.27 % at one per poll), which the app's own figure doesn't include; with the poll
  skipping it 0.150 %. AeroSpace's own CPU moved 2.4–3.1 % with user activity in every run,
  so it can't separate the builds.
- The status item button is 24 pt tall on a notched MacBook (window 37 pt, logged from the
  running app); an image taller than that is squeezed, so pills top out at 24 pt.

## Decided against

- Normalizing app icons to one visual size. Some icons fill more of their box than
  others (Obsidian is edge to edge; VS Code, Raycast, Ice are slightly small); the user
  chose to keep icons exactly as macOS provides them.

## Roadmap

Personal tool first: nothing that blocks a public release later, but no TOML config,
notarization or Homebrew cask until someone asks. The hard requirements stay hard; a
feature that breaks one is cut or redesigned.

Each feature: spec change here → test-first in `IconzCore` → `make test` → `--render-png`
→ `make install` and live with it for a day. On a short-lived branch, `/code-review`,
merged locally, then tagged.

1. **v1.1 Mode badge** (above). Rule: idle CPU over 5 minutes may not rise above v1 by
   more than ≈0.1 % average. Reading the mode on every poll broke it, so the poll skips it.
2. **v1.2 Click an icon to focus.** `focus --window-id` on that app's oldest window on
   that workspace; if that app is already focused there, cycle to its next window. The
   focused window is read at click time (`list-windows --focused`), not kept in the model.
   Label, padding and gaps still switch workspace. `+N` switches too until v1.3, where it
   opens the window menu.
3. **v1.3 Per-pill window menu** (above). Right-click a pill, or click its `+N`, for that
   workspace's windows; choose one to focus it. Titles and focus are read when the menu
   opens, never stored in the model, so idle CPU is unchanged.
4. **Deferred:** pinned/always-shown workspaces (if wanted); per-monitor grouping (when
   docking makes it hurt); hover tooltips; TOML config. Drag an icon onto a pill: probably never.
