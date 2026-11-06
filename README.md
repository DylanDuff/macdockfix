# MacDockFix

A copy of the macOS Dock on every display. Click an app in a display's dock and its window opens (or moves) on that display.

## Build

Requires macOS 26+, Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
xcodegen generate
xcodebuild -project MacDockFix.xcodeproj -scheme MacDockFix -derivedDataPath build/DerivedData build
open build/DerivedData/Build/Products/Debug/MacDockFix.app
```

Grant Accessibility access when prompted. It's needed to move windows between displays.

To build under your own Apple account, change `DEVELOPMENT_TEAM` in `project.yml`.

More detail is in [docs/](docs/).

## License

[MIT](LICENSE)
