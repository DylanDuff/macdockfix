# MacDockFix

A copy of the macOS Dock on every display. Clicking an app in a display's dock opens its window
(or moves an existing one) on that display.

- Mirrors pinned apps, running apps, recents, folders/stacks and Trash, with magnification,
  launch bounce, running indicators and right-click menus.
- Hides itself on whichever display currently has the real Dock.
- Lives in the menu bar (no Dock icon of its own).

## Requirements

- macOS 26+, Xcode 26+, [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- Accessibility permission (to move windows between displays)
- Automation permission for Finder (Trash state and Empty Trash)

## Build

```bash
xcodegen generate
xcodebuild -project MacDockFix.xcodeproj -scheme MacDockFix -derivedDataPath build/DerivedData build
open build/DerivedData/Build/Products/Debug/MacDockFix.app
```

## Documentation

- [Dock mirroring](docs/dock-mirroring.md): data sources, real Dock tracking, interactions
- [Window placement](docs/window-placement.md): how windows end up on the clicked display
- [CLAUDE.md](CLAUDE.md): architecture and conventions for contributors
