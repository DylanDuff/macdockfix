# Window placement

macOS has no API for "launch this app on display X". Apps open windows wherever they choose
(usually the display with keyboard focus, or a restored position). MacDockFix lets the app open
normally, then relocates windows through the Accessibility API.

## Click on a running app (`WindowPlacer.bringApp`)

In order:

1. If the app is hidden, unhide it.
2. A non-minimised standard window already on this display → raise it and make the app frontmost.
3. Otherwise the frontmost non-full-screen window → move it here, raise it.
4. Otherwise a minimised window → unminimise, move, raise.
5. Only full-screen windows → focus one (switches Space; we don't pull windows out of full screen).
6. No windows → send the reopen event (`NSWorkspace.openApplication`, same as the real Dock) and
   treat it like a launch (below).

## Launches and opening files/folders (`WindowPlacer.placeNewWindows`)

- Snapshot the app's existing standard windows (by bundle id), run the action, then poll AX every
  120 ms for new windows.
- Each new window is moved once (so the user can drag it away afterwards).
- Watching stops 8 s after the action, or 1.5 s after the first window is placed (this catches
  splash → main window handoffs).
- Files open with their default handler; folders and Trash go through Finder; "Show in Finder" too.

## Geometry (`WindowPlacer.move`)

- Keeps the window's relative position within the usable area and clamps its size to the target.
- A window that filled its old display's usable area fills the new one.
- Usable area = `visibleFrame` minus our dock's thickness on displays where our copy is shown.

## Known limits

- Windows appear briefly on the original display before moving.
- Without Accessibility permission, clicks fall back to plain activation and reopen.
- Apps that create non-standard windows (subrole other than `AXStandardWindow`) are ignored.
