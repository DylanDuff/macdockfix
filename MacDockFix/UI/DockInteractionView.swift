import AppKit
import SwiftUI

/// Root view of a dock panel. Owns all mouse handling (hover, click, right-click, long-press);
/// the SwiftUI view above it only draws.
final class DockInteractionView: NSView {
    struct Handlers {
        var layout: (CGSize) -> DockLayout
        var orientation: () -> DockOrientation
        var isSelectable: (Int) -> Bool
        var click: (Int, NSEvent.ModifierFlags) -> Void
        var menu: (Int) -> Void
    }

    let state: PanelState
    var handlers: Handlers?

    private var tracking: NSTrackingArea?
    private var longPress: Timer?
    private var longPressFired = false
    private static let longPressDelay: TimeInterval = 0.55

    init(state: PanelState) {
        self.state = state
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unused") }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways,
                                                         .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    // MARK: - Hit testing

    /// Returns the item index under a point, or nil when outside the active dock area.
    private func hit(_ event: NSEvent) -> (index: Int?, inside: Bool, along: CGFloat) {
        guard let handlers else { return (nil, false, 0) }
        let point = convert(event.locationInWindow, from: nil)
        let orientation = handlers.orientation()
        let (along, cross) = orientation.components(of: point, in: bounds.size)
        let layout = handlers.layout(bounds.size)
        let metrics = layout.metrics

        // While magnified, the hover area extends to the top of the tallest icon.
        let largestIcon: CGFloat = layout.slots.map(\.iconSize).max() ?? metrics.tileSize
        let magnifiedReach: CGFloat = metrics.iconBaseline + largestIcon + metrics.crossPadding
        let shelfReach: CGFloat = metrics.edgeGap + metrics.shelfThickness
        let reach: CGFloat = state.pointer == nil ? shelfReach : max(shelfReach, magnifiedReach)
        let inside = cross >= 0 && cross <= reach && layout.shelf.contains(along)
        guard inside, let index = layout.slotIndex(at: along), handlers.isSelectable(index) else {
            return (nil, inside, along)
        }
        return (index, inside, along)
    }

    // MARK: - Hover

    override func mouseMoved(with event: NSEvent) {
        updateHover(event)
    }

    override func mouseExited(with event: NSEvent) {
        clearHover()
    }

    private func updateHover(_ event: NSEvent) {
        let result = hit(event)
        guard result.inside else { return clearHover() }
        if state.pointer == nil {
            animate(0.12) { self.state.pointer = result.along }
        } else {
            state.pointer = result.along
        }
        state.hoveredIndex = result.index
    }

    func clearHover() {
        guard state.pointer != nil || state.hoveredIndex != nil else { return }
        animate(0.2) {
            self.state.pointer = nil
            self.state.hoveredIndex = nil
        }
    }

    // MARK: - Clicks

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { return rightMouseDown(with: event) }
        guard let index = hit(event).index else { return }
        state.pressedIndex = index
        longPressFired = false
        longPress = Timer.scheduledTimer(withTimeInterval: Self.longPressDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.state.pressedIndex == index else { return }
                self.longPressFired = true
                self.state.pressedIndex = nil
                self.handlers?.menu(index)
            }
        }
    }

    override func mouseUp(with event: NSEvent) {
        longPress?.invalidate()
        defer { state.pressedIndex = nil }
        guard !longPressFired, let pressed = state.pressedIndex, hit(event).index == pressed else { return }
        handlers?.click(pressed, event.modifierFlags)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let index = hit(event).index else { return }
        handlers?.menu(index)
    }
}

private func animate(_ duration: Double, _ body: () -> Void) {
    withAnimation(.easeOut(duration: duration), body)
}
