# MacDockFix

Menu-bar agent (LSUIElement) that draws a copy of the macOS Dock on every display except the one
currently hosting the real Dock. Clicking a tile opens/moves windows onto *that* display.

## Build

- `project.yml` is the source of truth; `MacDockFix.xcodeproj` is generated and git-ignored.
  Run `xcodegen generate` after adding/removing files.
- `xcodebuild -project MacDockFix.xcodeproj -scheme MacDockFix -derivedDataPath build/DerivedData build`
- Signed with the Apple Development identity (team AQ4XYQUBV3). Keep it signed: ad-hoc signing changes
  the code hash every build and macOS drops the Accessibility grant each time.
- Not sandboxed (Accessibility + reading `com.apple.dock` require it) → not App Store distributable.
- Swift 6 with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Timer/notification closures are
  `@Sendable`; hop back with `MainActor.assumeIsolated`. Don't subclass non-isolated AppKit classes
  whose initialisers you override (e.g. NSMenuItem) — compose instead (see `ActionMenuItem`).

## Architecture

- `Model/` — `DockPreferences` (CFPreferences read/write of `com.apple.dock`), `DockModel` (one shared
  item list: Finder, pinned, running, recents, others, Trash), `RealDockTracker` (finds the real Dock's
  display by its layer-20 "Dock" window; polled, no notification exists).
- `Placement/` — `AXWindow`/`AXApplication` wrappers, `WindowPlacer` (move windows between displays;
  watch for new windows after launch/open and move them), `ScreenGeometry` (AppKit bottom-left ↔
  CG/AX top-left coordinate flip around the primary screen).
- `Actions/` — `DockActions` (every action takes the source `NSScreen`), `TrashController` (via Finder
  Apple Events because `~/.Trash` needs Full Disk Access).
- `UI/` — `DockPanelController` per display; `DockLayout` is pure geometry shared by rendering
  (`DockView`, SwiftUI) and hit-testing (`DockInteractionView`, AppKit). SwiftUI never receives events
  (`PassiveHostingView.hitTest` → nil).

## Invariants / gotchas

- Coordinates: AX + CGWindowList use top-left global space; NSScreen uses bottom-left. Always convert
  via `ScreenGeometry`.
- Layout uses "along"/"cross" axes so bottom/left/right docks share one code path
  (`DockOrientation.point(along:cross:in:)`).
- Panels are full-width transparent strips; clicks in transparent pixels fall through to windows below.
- Our dock can't shrink `visibleFrame`, so `WindowPlacer.usableFrame` subtracts its thickness manually.
- Keep in Dock edits the real Dock plist and runs `killall Dock` (the Dock only reads tiles on launch).
- AX calls are synchronous IPC on the main thread; per-app messaging timeout is 0.4s.

Docs: `docs/`.
