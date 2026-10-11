# AeroSpaceIconz

A macOS menu bar status item that shows each AeroSpace workspace as a pill of app icons.

**[DESIGN.md](DESIGN.md) is the spec.** Read it before changing behaviour, visuals, timing
or the AeroSpace integration, and update it in the same change when a decision changes.

## Loop

1. Write the test first and watch it go red. Tests use Swift Testing (`import Testing`):
   only Command Line Tools are installed, so there is no XCTest and no Xcode.
2. `make test` until green.
3. `make install` rebuilds, replaces `~/Applications/AeroSpaceIconz.app` and relaunches it.
4. To see the drawing: `swift build && .build/debug/AeroSpaceIconz --render-png <dir>`, then
   view `pills-light.png` / `pills-dark.png`. It draws the live AeroSpace state (it reads
   `list-*`). Screen capture here returns only the wallpaper (no Screen Recording
   permission), so these PNGs are how you see the bar.

## Where code goes

- Logic lives in `IconzCore` (no AppKit) and is tested in `IconzCoreTests` through fakes
  of the `AeroSpaceClient` and `MonotonicClock` seams. `FakeClock` jumps to each deadline
  (for single bursts); `ManualClock` holds sleepers until advanced (for the coordinator's
  loops started by `start()`).
- `AeroSpaceIconz` stays thin AppKit glue; testable glue goes in `AeroSpaceIconzTests`.
  `CLIClientTests` drives a fake `aerospace` shell script that answers only the exact
  command lines: extend it when the CLI usage changes. Tests touching the process-wide
  `Subscriptions` belong in that `.serialized` suite.
- Tunables go in `Config.swift`.

## AeroSpace is live

The user's real AeroSpace (stock 0.21.3-Beta, Homebrew) is running. Read-only commands
are free: `list-*`, `subscribe`, `<command> --help` (check flags there before relying on
them). Ask first before `workspace`, `move-node-*`, `reload-config`, or editing
`~/.config/aerospace/aerospace.toml`: they move the user's windows and cursor.

## Traps already hit

- `Process.waitUntilExit()` adds ~60 ms per call; `CLIClient` waits on `terminationHandler`.
- A hung `aerospace` call blocks every later refresh; `CLIClient` kills calls after `cliTimeout`.
- `aerospace subscribe` children outlive a killed app; every one goes through
  `Subscriptions` so Quit and SIGTERM can kill them.
- `list-windows --json` without `--format` omits bundle id and workspace.
- In `#expect`, comparing a `Double?` against an integer-literal sum failed spuriously;
  bind the expected value to a typed `let` first.
