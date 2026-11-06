import AppKit

/// What happens when a dock item is used. Every action takes the screen of the dock it came from,
/// so resulting windows land on that display.
final class DockActions {
    let model: DockModel
    let placer: WindowPlacer
    let trash = TrashController()

    private static let finderIdentifier = "com.apple.finder"

    init(model: DockModel, placer: WindowPlacer) {
        self.model = model
        self.placer = placer
    }

    func activate(_ item: DockItem, on screen: NSScreen) {
        switch item.kind {
        case .app:
            activateApp(item, on: screen)
        case .file, .folder:
            if let url = item.url { open(url, on: screen) }
        case .trash:
            placer.placeNewWindows(of: Self.finderIdentifier, on: screen) { trash.reveal() }
        case .spacer, .separator:
            break
        }
    }

    private func activateApp(_ item: DockItem, on screen: NSScreen) {
        guard let url = item.url else { return }
        if let app = item.runningApplication {
            if app.isHidden { app.unhide() }
            if AXApplication.isTrusted, placer.bringApp(app.processIdentifier, to: screen) {
                return
            }
            // No usable window (or no permission): reopen, which is what the real Dock sends.
            reopen(url, bundleIdentifier: app.bundleIdentifier, on: screen)
            return
        }
        model.startBounce(itemID: item.id)
        reopen(url, bundleIdentifier: item.bundleIdentifier ?? Bundle(url: url)?.bundleIdentifier, on: screen)
    }

    /// Launches, or sends a running app the reopen event, then places the window it creates.
    private func reopen(_ appURL: URL, bundleIdentifier: String?, on screen: NSScreen) {
        let launch = {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
        }
        guard let bundleIdentifier else { return launch() }
        placer.placeNewWindows(of: bundleIdentifier, on: screen, after: launch)
    }

    /// Opens a file or folder with its default app and places the resulting window.
    func open(_ url: URL, on screen: NSScreen) {
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        let isPackage = (try? url.resourceValues(forKeys: [.isPackageKey]).isPackage) ?? false
        let handler: String? = if isDirectory && !isPackage {
            Self.finderIdentifier
        } else if url.pathExtension == "app" {
            Bundle(url: url)?.bundleIdentifier
        } else {
            NSWorkspace.shared.urlForApplication(toOpen: url).flatMap { Bundle(url: $0)?.bundleIdentifier }
        }
        guard let handler else {
            NSWorkspace.shared.open(url)
            return
        }
        placer.placeNewWindows(of: handler, on: screen) { NSWorkspace.shared.open(url) }
    }

    func revealInFinder(_ url: URL, on screen: NSScreen) {
        placer.placeNewWindows(of: Self.finderIdentifier, on: screen) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    func bring(_ window: AXWindow, of item: DockItem, to screen: NSScreen) {
        guard let app = item.runningApplication else { return }
        if app.isHidden { app.unhide() }
        placer.bring(window, pid: app.processIdentifier, to: screen)
    }

    func toggleHidden(_ item: DockItem) {
        guard let app = item.runningApplication else { return }
        _ = app.isHidden ? app.unhide() : app.hide()
    }

    func quit(_ item: DockItem, force: Bool) {
        guard let app = item.runningApplication else { return }
        _ = force ? app.forceTerminate() : app.terminate()
    }

    func setPinned(_ item: DockItem, pinned: Bool) {
        guard let url = item.url else { return }
        if pinned {
            DockPreferences.pin(appAt: url)
        } else {
            DockPreferences.unpin(url)
        }
    }
}
