import AppKit

/// The single source of truth every per-display dock renders from.
///
/// Layout mirrors the real Dock: Finder, pinned apps, running unpinned apps,
/// [separator, recents], separator, folders/files, Trash.
@Observable
final class DockModel {
    private(set) var settings = DockSettings()
    private(set) var items: [DockItem] = []
    /// Item id → when its launch bounce started.
    private(set) var bounces: [String: Date] = [:]
    var isTrashFull = false

    private var lastPreferencesDate: Date?
    private var preferencesTimer: Timer?
    private var observers: [NSObjectProtocol] = []

    private static let finderURL = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
    static let bounceTimeout: TimeInterval = 12

    func start() {
        reloadPreferences(force: true)
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
        ]
        for name in names {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let bundleURL = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleURL
                MainActor.assumeIsolated {
                    if name == NSWorkspace.didLaunchApplicationNotification, let bundleURL {
                        self?.finishBounce(appURL: bundleURL)
                    }
                    self?.rebuild()
                }
            })
        }
        // cfprefsd rewrites the plist atomically, so poll its modification date rather than watching a file handle.
        preferencesTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadPreferences(force: false) }
        }
    }

    private func reloadPreferences(force: Bool) {
        let date = try? DockPreferences.plistURL.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate
        guard force || date != lastPreferencesDate else { return }
        lastPreferencesDate = date
        DockPreferences.synchronize()
        let newSettings = DockPreferences.readSettings()
        if newSettings != settings { settings = newSettings }
        rebuild()
    }

    func rebuild() {
        let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        var claimed = Set<pid_t>()

        func runningMatch(url: URL?, bundleIdentifier: String?) -> NSRunningApplication? {
            running.first { app in
                guard !claimed.contains(app.processIdentifier) else { return false }
                if let url, app.bundleURL?.standardizedFileURL == url.standardizedFileURL { return true }
                if let bundleIdentifier, !bundleIdentifier.isEmpty { return app.bundleIdentifier == bundleIdentifier }
                return false
            }
        }

        func appItem(url: URL?, label: String, bundleIdentifier: String?, pinned: Bool,
                     section: DockSection, idPrefix: String) -> DockItem {
            let match = runningMatch(url: url, bundleIdentifier: bundleIdentifier)
            if let match { claimed.insert(match.processIdentifier) }
            return DockItem(id: "\(idPrefix):\(url?.path ?? label)", kind: .app, section: section,
                            label: label, url: url ?? match?.bundleURL,
                            bundleIdentifier: bundleIdentifier ?? match?.bundleIdentifier,
                            isPinned: pinned, processIdentifier: match?.processIdentifier)
        }

        var result: [DockItem] = [
            appItem(url: Self.finderURL, label: "Finder", bundleIdentifier: "com.apple.finder",
                    pinned: true, section: .apps, idPrefix: "app"),
        ]

        for (index, tile) in DockPreferences.readTiles("persistent-apps").enumerated() {
            switch tile.type {
            case .spacer(let small):
                result.append(DockItem(id: "spacer:\(index)", kind: .spacer(small: small), section: .apps,
                                       label: "", isPinned: true))
            case .file, .directory:
                result.append(appItem(url: tile.url, label: tile.label, bundleIdentifier: tile.bundleIdentifier,
                                      pinned: true, section: .apps, idPrefix: "app"))
            }
        }

        for app in running where !claimed.contains(app.processIdentifier) {
            claimed.insert(app.processIdentifier)
            result.append(DockItem(id: "app:\(app.bundleURL?.path ?? "pid\(app.processIdentifier)")", kind: .app,
                                   section: .apps, label: app.localizedName ?? "App", url: app.bundleURL,
                                   bundleIdentifier: app.bundleIdentifier, isPinned: false,
                                   processIdentifier: app.processIdentifier))
        }

        if settings.showRecents {
            let recents = DockPreferences.readTiles("recent-apps").compactMap { tile -> DockItem? in
                guard case .file = tile.type,
                      !result.contains(where: { $0.url?.standardizedFileURL == tile.url?.standardizedFileURL })
                else { return nil }
                return appItem(url: tile.url, label: tile.label, bundleIdentifier: tile.bundleIdentifier,
                               pinned: false, section: .recents, idPrefix: "recent")
            }
            if !recents.isEmpty {
                result.append(.separator("recents"))
                result.append(contentsOf: recents)
            }
        }

        result.append(.separator("others"))
        for (index, tile) in DockPreferences.readTiles("persistent-others").enumerated() {
            switch tile.type {
            case .directory(let options):
                result.append(DockItem(id: "folder:\(tile.url?.path ?? "\(index)")", kind: .folder(options),
                                       section: .others, label: tile.label, url: tile.url, isPinned: true))
            case .file:
                result.append(DockItem(id: "file:\(tile.url?.path ?? "\(index)")", kind: .file,
                                       section: .others, label: tile.label, url: tile.url, isPinned: true))
            case .spacer(let small):
                result.append(DockItem(id: "spacer-others:\(index)", kind: .spacer(small: small),
                                       section: .others, label: "", isPinned: true))
            }
        }
        result.append(.trashItem)

        if result != items { items = result }
        pruneBounces()
    }

    // MARK: - Launch bounce

    func startBounce(itemID: String) {
        bounces[itemID] = .now
    }

    private func finishBounce(appURL: URL) {
        for item in items where item.url?.standardizedFileURL == appURL.standardizedFileURL {
            bounces[item.id] = nil
        }
    }

    private func pruneBounces() {
        let now = Date.now
        bounces = bounces.filter { id, started in
            now.timeIntervalSince(started) < Self.bounceTimeout
                && items.first(where: { $0.id == id }).map { !($0.runningApplication?.isFinishedLaunching ?? false) } ?? false
        }
    }
}
