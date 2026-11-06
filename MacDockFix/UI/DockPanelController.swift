import AppKit
import SwiftUI

/// One dock copy, pinned to one display.
final class DockPanelController {
    let displayID: CGDirectDisplayID
    private let model: DockModel
    private let actions: DockActions
    private let stacks: StackPresenter
    private let menus: DockMenuBuilder
    private let panel = DockPanel()
    private let state = PanelState()
    private let interaction: DockInteractionView

    private(set) var isShown = false

    var screen: NSScreen? { ScreenGeometry.screen(withDisplayID: displayID) }
    var metrics: DockMetrics { DockMetrics(settings: model.settings) }
    private var orientation: DockOrientation { model.settings.orientation }

    init(displayID: CGDirectDisplayID, model: DockModel, actions: DockActions, stacks: StackPresenter) {
        self.displayID = displayID
        self.model = model
        self.actions = actions
        self.stacks = stacks
        menus = DockMenuBuilder(actions: actions)
        interaction = DockInteractionView(state: state)
        configure()
    }

    private func configure() {
        let hosting = PassiveHostingView(rootView: DockView(model: model, state: state) { [weak self] size in
            self?.layout(size) ?? .empty
        })
        hosting.autoresizingMask = [.width, .height]
        interaction.addSubview(hosting)
        panel.contentView = interaction
        hosting.frame = interaction.bounds

        interaction.handlers = .init(
            layout: { [weak self] size in self?.layout(size) ?? .empty },
            orientation: { [weak self] in self?.orientation ?? .bottom },
            isSelectable: { [weak self] index in
                guard let items = self?.model.items, index < items.count else { return false }
                return items[index].kind.isSelectable
            },
            click: { [weak self] index, modifiers in self?.click(index, modifiers: modifiers) },
            menu: { [weak self] index in self?.showMenu(index) })
    }

    func layout(_ size: CGSize) -> DockLayout {
        DockLayout.compute(kinds: model.items.map(\.kind), metrics: metrics,
                           axisLength: orientation.axisLength(of: size), pointer: state.pointer,
                           magnification: model.settings.magnification)
    }

    // MARK: - Placement

    func refreshFrame() {
        guard let screen else { return }
        let frame = screen.frame
        let thickness = metrics.panelThickness(for: orientation)
        let panelFrame: CGRect = switch orientation {
        case .bottom: CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: thickness)
        case .left: CGRect(x: frame.minX, y: frame.minY, width: thickness, height: frame.height)
        case .right: CGRect(x: frame.maxX - thickness, y: frame.minY, width: thickness, height: frame.height)
        }
        if panel.frame != panelFrame { panel.setFrame(panelFrame, display: true) }
    }

    func setShown(_ shown: Bool) {
        guard shown != isShown else { return }
        isShown = shown
        if shown {
            refreshFrame()
            panel.orderFrontRegardless()
        } else {
            interaction.clearHover()
            panel.orderOut(nil)
        }
    }

    func close() {
        panel.orderOut(nil)
        panel.close()
    }

    // MARK: - Actions

    private func item(at index: Int) -> DockItem? {
        index < model.items.count ? model.items[index] : nil
    }

    private func click(_ index: Int, modifiers: NSEvent.ModifierFlags) {
        guard let item = item(at: index), let screen else { return }
        if modifiers.contains(.command), let url = item.url {
            return actions.revealInFinder(url, on: screen)
        }
        if case .folder(let options) = item.kind {
            return presentStack(item, options: options, index: index, screen: screen)
        }
        actions.activate(item, on: screen)
    }

    private func presentStack(_ item: DockItem, options: StackOptions, index: Int, screen: NSScreen) {
        state.openIndex = index
        stacks.present(item, options: options, anchor: iconRectOnScreen(index), orientation: orientation,
                       screen: screen, showMenu: { [weak self] menu in self?.popUp(menu, at: index) },
                       onClose: { [weak self] in
                           self?.state.openIndex = nil
                           self?.interaction.clearHover()
                       })
    }

    private func showMenu(_ index: Int) {
        guard let item = item(at: index), let screen else { return }
        popUp(menus.menu(for: item, on: screen), at: index)
    }

    /// Pops a menu beside the tile, on the side away from the screen edge. Blocks while open.
    private func popUp(_ menu: NSMenu, at index: Int) {
        let size = interaction.bounds.size
        let layout = layout(size)
        guard index < layout.slots.count else { return }
        let slot = layout.slots[index]
        let iconFar = layout.metrics.iconBaseline + slot.iconSize + 6
        let menuSize = menu.size
        let point: CGPoint = switch orientation {
        case .bottom: CGPoint(x: slot.center - menuSize.width / 2, y: size.height - iconFar - menuSize.height)
        case .left: CGPoint(x: iconFar, y: slot.center - 12)
        case .right: CGPoint(x: size.width - iconFar - menuSize.width, y: slot.center - 12)
        }
        state.openIndex = index
        menu.popUp(positioning: nil, at: point, in: interaction)
        state.openIndex = nil
        interaction.clearHover()
    }

    /// The tile's icon rect in AppKit screen coordinates.
    private func iconRectOnScreen(_ index: Int) -> CGRect {
        let size = interaction.bounds.size
        let layout = layout(size)
        guard index < layout.slots.count else { return .zero }
        let slot = layout.slots[index]
        let center = orientation.point(along: slot.center, cross: layout.metrics.iconBaseline + slot.iconSize / 2,
                                       in: size)
        let local = CGRect(x: center.x - slot.iconSize / 2, y: center.y - slot.iconSize / 2,
                           width: slot.iconSize, height: slot.iconSize)
        return panel.convertToScreen(interaction.convert(local, to: nil))
    }
}

extension DockLayout {
    static var empty: DockLayout {
        compute(kinds: [], metrics: DockMetrics(settings: DockSettings()), axisLength: 0, pointer: nil,
                magnification: false)
    }
}

/// Draw-only hosting view: all events go to the `DockInteractionView` beneath it.
final class PassiveHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
