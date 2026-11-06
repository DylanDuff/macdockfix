import AppKit

/// Borderless, transparent, non-activating panel at Dock level. Clicking it never steals focus
/// from the frontmost app, and fully transparent pixels pass clicks through to windows below.
final class DockPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        hidesOnDeactivate = false
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Per-panel interaction state the SwiftUI view renders from.
@Observable
final class PanelState {
    /// Pointer position along the dock axis while hovering; drives magnification.
    var pointer: CGFloat?
    var hoveredIndex: Int?
    var pressedIndex: Int?
    /// Suppresses the hover label while a menu or stack is open for this index.
    var openIndex: Int?
}

extension DockOrientation {
    var isVertical: Bool { self != .bottom }

    /// Converts an (along, cross) dock position into top-left panel coordinates.
    func point(along: CGFloat, cross: CGFloat, in size: CGSize) -> CGPoint {
        switch self {
        case .bottom: CGPoint(x: along, y: size.height - cross)
        case .left: CGPoint(x: cross, y: along)
        case .right: CGPoint(x: size.width - cross, y: along)
        }
    }

    /// Inverse of `point(along:cross:in:)`.
    func components(of point: CGPoint, in size: CGSize) -> (along: CGFloat, cross: CGFloat) {
        switch self {
        case .bottom: (point.x, size.height - point.y)
        case .left: (point.y, point.x)
        case .right: (point.y, size.width - point.x)
        }
    }

    func axisLength(of size: CGSize) -> CGFloat {
        isVertical ? size.height : size.width
    }
}
