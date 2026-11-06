import AppKit

/// Target that runs a closure; retained by its menu item via `representedObject`.
private final class MenuHandler: NSObject {
    let handler: () -> Void

    init(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc func run() { handler() }
}

/// An NSMenuItem that runs a closure, so menus can be built inline.
func ActionMenuItem(_ title: String, image: NSImage? = nil, handler: @escaping () -> Void) -> NSMenuItem {
    let target = MenuHandler(handler)
    let item = NSMenuItem(title: title, action: #selector(MenuHandler.run), keyEquivalent: "")
    item.target = target
    item.representedObject = target
    item.image = image
    return item
}

/// Builds the right-click / long-press menus for dock tiles.
struct DockMenuBuilder {
    let actions: DockActions

    func menu(for item: DockItem, on screen: NSScreen) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        switch item.kind {
        case .app: addAppItems(item, to: menu, screen: screen)
        case .folder, .file: addFileItems(item, to: menu, screen: screen)
        case .trash: addTrashItems(to: menu, screen: screen)
        case .spacer, .separator: break
        }
        return menu
    }

    private func addAppItems(_ item: DockItem, to menu: NSMenu, screen: NSScreen) {
        if let app = item.runningApplication, AXApplication.isTrusted {
            let windows = AXApplication.standardWindows(app.processIdentifier)
            for window in windows {
                let title = window.title.isEmpty ? item.label : window.title
                let entry = ActionMenuItem(title) { actions.bring(window, of: item, to: screen) }
                if window.isMinimized {
                    entry.state = .mixed
                }
                menu.addItem(entry)
            }
            if !windows.isEmpty { menu.addItem(.separator()) }
        }

        let options = NSMenuItem(title: "Options", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        if item.url != nil, item.kind == .app, item.bundleIdentifier != "com.apple.finder" {
            let keep = ActionMenuItem("Keep in Dock") { actions.setPinned(item, pinned: !item.isPinned) }
            keep.state = item.isPinned ? .on : .off
            keep.toolTip = "Updates the real Dock, which restarts briefly."
            submenu.addItem(keep)
        }
        if let url = item.url {
            submenu.addItem(ActionMenuItem("Show in Finder") { actions.revealInFinder(url, on: screen) })
        }
        options.submenu = submenu
        if !submenu.items.isEmpty {
            menu.addItem(options)
            menu.addItem(.separator())
        }

        guard let app = item.runningApplication else {
            menu.addItem(ActionMenuItem("Open") { actions.activate(item, on: screen) })
            return
        }
        menu.addItem(ActionMenuItem(app.isHidden ? "Show" : "Hide") { actions.toggleHidden(item) })
        guard item.bundleIdentifier != "com.apple.finder" else { return }
        menu.addItem(ActionMenuItem("Quit") { actions.quit(item, force: false) })
        let forceQuit = ActionMenuItem("Force Quit") { actions.quit(item, force: true) }
        forceQuit.isAlternate = true
        forceQuit.keyEquivalentModifierMask = .option
        menu.addItem(forceQuit)
    }

    private func addFileItems(_ item: DockItem, to menu: NSMenu, screen: NSScreen) {
        guard let url = item.url else { return }
        menu.addItem(ActionMenuItem("Open \"\(item.label)\"") { actions.open(url, on: screen) })
        menu.addItem(ActionMenuItem("Show in Finder") { actions.revealInFinder(url, on: screen) })
    }

    private func addTrashItems(to menu: NSMenu, screen: NSScreen) {
        menu.addItem(ActionMenuItem("Open") { actions.activate(.trashItem, on: screen) })
        let empty = ActionMenuItem("Empty Trash") { actions.trash.empty() }
        empty.isEnabled = actions.model.isTrashFull
        menu.addItem(empty)
    }
}

extension DockItem {
    static let trashItem = DockItem(id: "trash", kind: .trash, section: .others, label: "Trash", isPinned: true)
}
