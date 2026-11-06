import AppKit
import ServiceManagement

/// Owns one dock panel per display and keeps them in sync with displays, Dock settings
/// and the real Dock's location (the copy on the real Dock's display is hidden).
@Observable
final class DockCoordinator {
    let model = DockModel()
    let tracker = RealDockTracker()
    @ObservationIgnored let placer = WindowPlacer()
    @ObservationIgnored private(set) lazy var actions = DockActions(model: model, placer: placer)
    @ObservationIgnored private lazy var stacks = StackPresenter(actions: actions)
    @ObservationIgnored private var panels: [CGDirectDisplayID: DockPanelController] = [:]

    private(set) var isAccessibilityTrusted = AXApplication.isTrusted
    @ObservationIgnored private var permissionTimer: Timer?

    var realDockScreenName: String {
        tracker.displayID.flatMap(ScreenGeometry.screen(withDisplayID:))?.localizedName ?? "Unknown"
    }

    func start() {
        placer.reservedEdge = { [weak self] screen in
            guard let self, let panel = self.panels[screen.displayID], panel.isShown else { return nil }
            return (self.model.settings.orientation, panel.metrics.reservedThickness)
        }
        model.start()
        tracker.start()
        actions.trash.startMonitoring { [weak self] full in
            if self?.model.isTrashFull != full { self?.model.isTrashFull = full }
        }

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncPanels() }
        }
        observe { [weak self] in self?.syncPanels() }

        if !isAccessibilityTrusted { AXApplication.requestTrust() }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                let trusted = AXApplication.isTrusted
                if self?.isAccessibilityTrusted != trusted { self?.isAccessibilityTrusted = trusted }
            }
        }
    }

    /// Re-runs `apply` whenever an observable value it reads changes.
    private func observe(_ apply: @escaping @MainActor () -> Void) {
        withObservationTracking { apply() } onChange: { [weak self] in
            Task { @MainActor in self?.observe(apply) }
        }
    }

    private func syncPanels() {
        // Read the observed inputs up front so observation tracks them on every pass.
        _ = model.settings
        let realDock = tracker.displayID
        let screens = NSScreen.screens
        let current = Set(screens.map(\.displayID))

        for (displayID, panel) in panels where !current.contains(displayID) {
            panel.close()
            panels[displayID] = nil
        }
        for screen in screens {
            let panel = panels[screen.displayID] ?? {
                let created = DockPanelController(displayID: screen.displayID, model: model, actions: actions,
                                                  stacks: stacks)
                panels[screen.displayID] = created
                return created
            }()
            panel.refreshFrame()
            panel.setShown(screen.displayID != realDock)
        }
    }

    // MARK: - Status menu actions

    var launchesAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            try? newValue ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
        }
    }

    func openAccessibilitySettings() {
        AXApplication.requestTrust()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
