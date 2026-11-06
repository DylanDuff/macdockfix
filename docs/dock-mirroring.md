# Dock mirroring

## Source data

Read from `com.apple.dock` via CFPreferences (re-read when the plist's modification date changes,
polled every 1.5 s):

| Key | Use |
| --- | --- |
| `persistent-apps` | pinned apps and spacers (`file-tile`, `spacer-tile`, `small-spacer-tile`) |
| `persistent-others` | folders (`directory-tile`: `showas`, `arrangement`, `displayas`) and files |
| `recent-apps` | recents section when `show-recents` is on |
| `tilesize`, `largesize`, `magnification`, `orientation`, `show-process-indicators` | appearance |

Finder is always first and Trash always last; neither is stored in the plist.

Running apps come from `NSWorkspace.runningApplications` (`.regular` activation policy only),
matched to pinned tiles by bundle URL, then bundle id.

## Real Dock tracking

The Dock owns a layer-20 window named "Dock" spanning the display it currently lives on.
`RealDockTracker` polls `CGWindowListCopyWindowInfo` every 0.5 s; the copy on that display is
hidden. Pushing the pointer against the bottom of another display moves the real Dock there (macOS
behaviour), and our copies swap accordingly.

## Interaction

| Input | Result |
| --- | --- |
| Click | app: launch/focus/move window here; folder: stack; file: open here; Trash: open here |
| ⌘-click | Show in Finder |
| Right-click / ⌃-click / long press | context menu (window list, Options ▸ Keep in Dock / Show in Finder, Hide, Quit; ⌥ → Force Quit) |

Stacks: `list` style uses an NSMenu; grid/fan/automatic use a glass grid panel.

## Not mirrored

Notification badges, attention bounces (requestUserAttention), drag-and-drop onto tiles, dragging
to reorder, auto-hide, and Dock menu items that apps supply themselves (no public API for these).
