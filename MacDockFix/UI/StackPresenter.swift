import AppKit
import SwiftUI

/// Shows a folder tile's contents: a grid panel (grid/fan/automatic) or a menu (list).
final class StackPresenter {
    private let actions: DockActions
    private var panel: NSPanel?
    private var monitors: [Any] = []
    private var onClose: (() -> Void)?

    private static let maxItems = 60
    private static let menuItemLimit = 80

    init(actions: DockActions) {
        self.actions = actions
    }

    /// - Parameters:
    ///   - anchor: the tile's icon rect in AppKit screen coordinates.
    ///   - showMenu: pops a prepared NSMenu at the tile (used for list-style stacks).
    func present(_ item: DockItem, options: StackOptions, anchor: CGRect, orientation: DockOrientation,
                 screen: NSScreen, showMenu: (NSMenu) -> Void, onClose: @escaping () -> Void) {
        guard let folder = item.url else { return }
        dismiss()
        let contents = FolderContents.list(folder, arrangement: options.arrangement)

        if options.display == .list {
            showMenu(listMenu(folder: folder, contents: contents, screen: screen))
            onClose()
            return
        }

        let view = StackGridView(title: item.label, contents: Array(contents.prefix(Self.maxItems))) { [weak self] url in
            self?.dismiss()
            self?.actions.open(url, on: screen)
        } openFolder: { [weak self] in
            self?.dismiss()
            self?.actions.open(folder, on: screen)
        }
        let hosting = FirstClickHostingView(rootView: view)
        let size = hosting.fittingSize
        let panel = DockPanel()
        panel.level = .popUpMenu
        panel.contentView = hosting
        panel.setFrame(frame(size: size, anchor: anchor, orientation: orientation, screen: screen), display: true)
        panel.orderFrontRegardless()
        self.panel = panel
        self.onClose = onClose

        // Close on any click outside the panel, in our app or another.
        let outside: (NSEvent) -> Void = { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let panel = self.panel, !panel.frame.contains(NSEvent.mouseLocation) else { return }
                self.dismiss()
            }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: outside) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { event in
            outside(event)
            return event
        }) {
            monitors.append(local)
        }
    }

    func dismiss() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        panel?.orderOut(nil)
        panel = nil
        onClose?()
        onClose = nil
    }

    private func frame(size: CGSize, anchor: CGRect, orientation: DockOrientation, screen: NSScreen) -> CGRect {
        let gap: CGFloat = 10
        var origin: CGPoint = switch orientation {
        case .bottom: CGPoint(x: anchor.midX - size.width / 2, y: anchor.maxY + gap)
        case .left: CGPoint(x: anchor.maxX + gap, y: anchor.midY - size.height / 2)
        case .right: CGPoint(x: anchor.minX - gap - size.width, y: anchor.midY - size.height / 2)
        }
        let bounds = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        origin.x = origin.x.clamped(bounds.minX, max(bounds.minX, bounds.maxX - size.width))
        origin.y = origin.y.clamped(bounds.minY, max(bounds.minY, bounds.maxY - size.height))
        return CGRect(origin: origin, size: size)
    }

    private func listMenu(folder: URL, contents: [URL], screen: NSScreen) -> NSMenu {
        let menu = NSMenu()
        for url in contents.prefix(Self.menuItemLimit) {
            let icon = IconProvider.shared.icon(forFile: url).copy() as? NSImage
            icon?.size = NSSize(width: 16, height: 16)
            menu.addItem(ActionMenuItem(FileManager.default.displayName(atPath: url.path), image: icon) { [actions] in
                actions.open(url, on: screen)
            })
        }
        if !contents.isEmpty { menu.addItem(.separator()) }
        menu.addItem(ActionMenuItem("Open in Finder") { [actions] in actions.open(folder, on: screen) })
        return menu
    }
}

/// Hosting view for non-activating panels: the first click acts immediately.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct StackGridView: View {
    let title: String
    let contents: [URL]
    let open: (URL) -> Void
    let openFolder: () -> Void

    private static let tile: CGFloat = 64
    private static let cell: CGFloat = 92
    private static let maxColumns = 6

    var body: some View {
        let columns = max(1, min(Self.maxColumns, Int(Double(contents.count).squareRoot().rounded(.up))))
        let rows = Int((Double(contents.count) / Double(columns)).rounded(.up))
        VStack(spacing: 10) {
            Text(title).font(.headline)
            if contents.isEmpty {
                Text("Empty folder").foregroundStyle(.secondary).padding(20)
            } else {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(Self.cell), spacing: 6), count: columns),
                              spacing: 8) {
                        ForEach(contents, id: \.self) { url in
                            Button { open(url) } label: {
                                VStack(spacing: 4) {
                                    Image(nsImage: IconProvider.shared.icon(forFile: url))
                                        .resizable()
                                        .frame(width: Self.tile, height: Self.tile)
                                    Text(FileManager.default.displayName(atPath: url.path))
                                        .font(.caption)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.center)
                                        .frame(width: Self.cell)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(width: CGFloat(columns) * (Self.cell + 6),
                       height: min(CGFloat(rows) * (Self.cell + 20), 460))
            }
            Button("Open in Finder", action: openFolder)
                .buttonStyle(.glass)
        }
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
