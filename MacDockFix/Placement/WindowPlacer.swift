import AppKit

/// Moves app windows onto a target display. macOS has no "launch on display X" API, so we let the
/// app open where it likes and relocate its windows through the Accessibility API.
final class WindowPlacer {
    /// Space our own dock occupies on a screen (it can't shrink `visibleFrame` like the real Dock).
    var reservedEdge: (NSScreen) -> (edge: DockOrientation, thickness: CGFloat)? = { _ in nil }

    private var watchers: [UUID: Timer] = [:]
    private static let pollInterval: TimeInterval = 0.12
    private static let watchDuration: TimeInterval = 8
    /// After the first window is placed keep watching briefly for splash → main window handoffs.
    private static let settleDuration: TimeInterval = 1.5

    // MARK: - Geometry

    /// Usable area of a screen in top-left global space.
    func usableFrame(of screen: NSScreen) -> CGRect {
        var frame = screen.visibleFrame
        if let reserved = reservedEdge(screen) {
            switch reserved.edge {
            case .bottom:
                frame.origin.y += reserved.thickness
                frame.size.height -= reserved.thickness
            case .left:
                frame.origin.x += reserved.thickness
                frame.size.width -= reserved.thickness
            case .right:
                frame.size.width -= reserved.thickness
            }
        }
        return ScreenGeometry.toTopLeft(frame)
    }

    func isWindow(_ window: AXWindow, on screen: NSScreen) -> Bool {
        guard let frame = window.frame else { return false }
        return ScreenGeometry.screen(containingTopLeft: frame) == screen
    }

    /// Moves a window to `target`, keeping its relative position and size; windows that filled their
    /// old display's usable area fill the new one.
    func move(_ window: AXWindow, to target: NSScreen) {
        guard !window.isFullScreen, let frame = window.frame else { return }
        let destination = usableFrame(of: target)
        guard let source = ScreenGeometry.screen(containingTopLeft: frame), source != target else { return }
        let origin = usableFrame(of: source)

        let filledSource = abs(frame.width - origin.width) < 4 && abs(frame.height - origin.height) < 4
        if filledSource {
            window.setFrame(destination)
            return
        }

        let size = CGSize(width: min(frame.width, destination.width), height: min(frame.height, destination.height))
        func relative(_ offset: CGFloat, _ free: CGFloat) -> CGFloat {
            free > 0 ? (offset / free).clamped(0, 1) : 0.5
        }
        let fractionX = relative(frame.minX - origin.minX, origin.width - frame.width)
        let fractionY = relative(frame.minY - origin.minY, origin.height - frame.height)
        window.setFrame(CGRect(
            x: destination.minX + fractionX * (destination.width - size.width),
            y: destination.minY + fractionY * (destination.height - size.height),
            width: size.width, height: size.height))
    }

    // MARK: - Bringing a running app here

    /// Dock-click semantics for a running app on `screen`:
    /// focus a window already there, else pull the frontmost (or a minimised) window over.
    /// Returns false when the app has no usable window, so the caller should ask it to reopen one.
    @discardableResult
    func bringApp(_ pid: pid_t, to screen: NSScreen) -> Bool {
        let windows = AXApplication.standardWindows(pid)
        let visible = windows.filter { !$0.isMinimized }

        if let here = visible.first(where: { isWindow($0, on: screen) }) {
            focus(here, pid: pid)
            return true
        }
        if let movable = visible.first(where: { !$0.isFullScreen }) {
            move(movable, to: screen)
            focus(movable, pid: pid)
            return true
        }
        if let minimized = windows.first(where: \.isMinimized) {
            bring(minimized, pid: pid, to: screen)
            return true
        }
        if let fullScreen = visible.first {
            focus(fullScreen, pid: pid) // switches to its Space rather than tearing it out of full screen
            return true
        }
        return false
    }

    func bring(_ window: AXWindow, pid: pid_t, to screen: NSScreen) {
        if window.isMinimized { window.unminimize() }
        move(window, to: screen)
        focus(window, pid: pid)
    }

    private func focus(_ window: AXWindow, pid: pid_t) {
        window.raise()
        AXApplication.setFrontmost(pid)
    }

    // MARK: - Placing windows that are about to appear

    /// Runs `action` (launch, reopen, open a document…) then moves any new standard windows the app
    /// identified by `bundleIdentifier` creates in the next few seconds onto `screen`.
    func placeNewWindows(of bundleIdentifier: String, on screen: NSScreen, after action: () -> Void) {
        let existingPID = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .first?.processIdentifier
        var known = Set(existingPID.map(AXApplication.standardWindows) ?? [])
        action()

        let token = UUID()
        let started = Date.now
        var firstPlacement: Date?
        let displayID = screen.displayID

        let timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let now = Date.now
                let expired = now.timeIntervalSince(started) > Self.watchDuration
                    || firstPlacement.map { now.timeIntervalSince($0) > Self.settleDuration } ?? false
                guard !expired, let target = ScreenGeometry.screen(withDisplayID: displayID),
                      let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first
                else {
                    if expired || ScreenGeometry.screen(withDisplayID: displayID) == nil { self.stopWatching(token) }
                    return
                }
                for window in AXApplication.standardWindows(app.processIdentifier) where !known.contains(window) {
                    // Wait until the window has a frame; brand-new windows can report none for a tick.
                    guard window.frame != nil else { continue }
                    known.insert(window)
                    if !self.isWindow(window, on: target) { self.move(window, to: target) }
                    self.focus(window, pid: app.processIdentifier)
                    firstPlacement = firstPlacement ?? now
                }
            }
        }
        watchers[token] = timer
    }

    private func stopWatching(_ token: UUID) {
        watchers.removeValue(forKey: token)?.invalidate()
    }
}
