import AppKit

/// Finds the display currently hosting the real macOS Dock.
///
/// The Dock owns a full-screen, layer-20 window named "Dock" on whichever display it lives on;
/// macOS moves it when the pointer lingers at another display's Dock edge. There is no
/// notification for that, so we poll the window list (cheap: on-screen windows only).
@Observable
final class RealDockTracker {
    private(set) var displayID: CGDirectDisplayID?
    private var timer: Timer?

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func refresh() {
        // Keep the last known display while the Dock's window is briefly absent (e.g. Dock restarting).
        guard let found = Self.locateDock() else { return }
        if found != displayID { displayID = found }
    }

    private static func locateDock() -> CGDirectDisplayID? {
        let dockLevel = Int(CGWindowLevelForKey(.dockWindow))
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
            as? [[String: Any]] else { return nil }
        for window in windows {
            guard (window[kCGWindowOwnerName as String] as? String) == "Dock",
                  (window[kCGWindowLayer as String] as? Int) == dockLevel,
                  let boundsDictionary = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary)
            else { continue }
            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            for screen in NSScreen.screens where CGDisplayBounds(screen.displayID).contains(center) {
                return screen.displayID
            }
        }
        return nil
    }
}
