import AppKit

enum DockOrientation: String {
    case bottom, left, right
}

/// Mirrors the subset of `com.apple.dock` settings the copies honour.
struct DockSettings: Equatable {
    var tileSize: CGFloat = 48
    var largeSize: CGFloat = 128
    var magnification = false
    var orientation: DockOrientation = .bottom
    var showRecents = true
    var showIndicators = true
}

/// How a folder tile presents its contents when clicked (`showas` in the Dock plist).
enum StackDisplay: Int {
    case automatic = 0, fan = 1, grid = 2, list = 3
}

/// Sort order of a folder tile's contents (`arrangement` in the Dock plist).
enum StackArrangement: Int {
    case name = 1, dateAdded = 2, dateModified = 3, dateCreated = 4, kind = 5
}

struct StackOptions: Equatable {
    var display: StackDisplay = .automatic
    var arrangement: StackArrangement = .name
    /// `displayas` 1 shows the plain folder icon; 0 shows the top item ("stack").
    var showsFolderIcon = false
}

enum DockItemKind: Equatable {
    case app
    case folder(StackOptions)
    case file
    case spacer(small: Bool)
    case separator
    case trash

    var isSelectable: Bool {
        switch self {
        case .spacer, .separator: false
        default: true
        }
    }
}

enum DockSection {
    case apps, recents, others
}

struct DockItem: Identifiable, Equatable {
    let id: String
    var kind: DockItemKind
    var section: DockSection
    var label: String
    var url: URL?
    var bundleIdentifier: String?
    var isPinned: Bool
    var processIdentifier: pid_t?

    var isRunning: Bool { processIdentifier != nil }

    var runningApplication: NSRunningApplication? {
        processIdentifier.flatMap(NSRunningApplication.init(processIdentifier:))
    }

    static func separator(_ name: String) -> DockItem {
        DockItem(id: "separator:\(name)", kind: .separator, section: .apps, label: "", isPinned: true)
    }
}
