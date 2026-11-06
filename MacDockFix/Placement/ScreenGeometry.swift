import AppKit

/// Converts between AppKit's bottom-left global space and the top-left global space
/// used by CoreGraphics and the Accessibility API.
enum ScreenGeometry {
    /// Height of the primary display (the one with the menu bar at the time of login), the flip axis.
    private static var primaryHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? 0
    }

    static func toTopLeft(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    static func toBottomLeft(_ rect: CGRect) -> CGRect {
        toTopLeft(rect) // the flip is its own inverse
    }

    static func screen(withDisplayID displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { $0.displayID == displayID }
    }

    /// The screen containing the centre of a top-left-space rect, falling back to the largest overlap.
    static func screen(containingTopLeft rect: CGRect) -> NSScreen? {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let screens = NSScreen.screens
        if let match = screens.first(where: { toTopLeft($0.frame).contains(center) }) {
            return match
        }
        return screens.max { overlap($0, rect) < overlap($1, rect) }
    }

    private static func overlap(_ screen: NSScreen, _ rect: CGRect) -> CGFloat {
        let intersection = toTopLeft(screen.frame).intersection(rect)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}
