import AppKit
import ApplicationServices

/// Thin wrapper over an Accessibility window element. All frames are in top-left global space.
struct AXWindow: Hashable {
    let element: AXUIElement

    private func attribute<T>(_ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    private var position: CGPoint? {
        guard let raw: AXValue = attribute(kAXPositionAttribute) else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(raw, .cgPoint, &point) ? point : nil
    }

    private var size: CGSize? {
        guard let raw: AXValue = attribute(kAXSizeAttribute) else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(raw, .cgSize, &size) ? size : nil
    }

    var title: String { attribute(kAXTitleAttribute) ?? "" }
    var isMinimized: Bool { attribute(kAXMinimizedAttribute) ?? false }
    var isFullScreen: Bool { attribute("AXFullScreen") ?? false }

    /// Excludes palettes, sheets, popovers and other non-document windows.
    var isStandard: Bool {
        (attribute(kAXSubroleAttribute) as String?) == (kAXStandardWindowSubrole as String)
    }

    var frame: CGRect? {
        guard let origin = position, let size else { return nil }
        return CGRect(origin: origin, size: size)
    }

    func setFrame(_ frame: CGRect) {
        var origin = frame.origin
        var size = frame.size
        guard let position = AXValueCreate(.cgPoint, &origin), let dimension = AXValueCreate(.cgSize, &size)
        else { return }
        // Position first so the size isn't clamped to the old display; re-apply position once the
        // window has adopted the new display's scale, as some apps nudge themselves on resize.
        AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, position)
        AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, dimension)
        AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, position)
    }

    func unminimize() {
        AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
    }

    func raise() {
        AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
    }
}

enum AXApplication {
    /// Keep a hung app from freezing the docks (AX calls are synchronous IPC).
    private static let messagingTimeout: Float = 0.4

    static func element(_ pid: pid_t) -> AXUIElement {
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        return element
    }

    /// Windows in front-to-back order.
    static func windows(_ pid: pid_t) -> [AXWindow] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element(pid), kAXWindowsAttribute as CFString, &value) == .success,
              let list = value as? [AXUIElement]
        else { return [] }
        return list.map(AXWindow.init)
    }

    static func standardWindows(_ pid: pid_t) -> [AXWindow] {
        windows(pid).filter(\.isStandard)
    }

    static func setFrontmost(_ pid: pid_t) {
        AXUIElementSetAttributeValue(element(pid), kAXFrontmostAttribute as CFString, kCFBooleanTrue)
    }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestTrust() {
        let key = "AXTrustedCheckOptionPrompt" // kAXTrustedCheckOptionPrompt, which Swift 6 flags as a mutable global
        AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }
}
