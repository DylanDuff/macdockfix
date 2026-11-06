import AppKit

/// A tile as stored in the real Dock's preferences (`persistent-apps`, `persistent-others`, `recent-apps`).
struct DockTile: Equatable {
    enum TileType: Equatable {
        case file
        case directory(StackOptions)
        case spacer(small: Bool)
    }

    var type: TileType
    var url: URL?
    var label: String
    var bundleIdentifier: String?
}

/// Reads and edits `com.apple.dock` through CFPreferences so we see the same values cfprefsd serves the Dock.
enum DockPreferences {
    private static let domain = "com.apple.dock" as CFString

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Preferences/com.apple.dock.plist")
    }

    static func synchronize() {
        CFPreferencesAppSynchronize(domain)
    }

    private static func value(_ key: String) -> Any? {
        CFPreferencesCopyAppValue(key as CFString, domain)
    }

    private static func number(_ key: String) -> CGFloat? {
        (value(key) as? NSNumber).map { CGFloat($0.doubleValue) }
    }

    private static func bool(_ key: String, default fallback: Bool) -> Bool {
        (value(key) as? NSNumber)?.boolValue ?? fallback
    }

    static func readSettings() -> DockSettings {
        var settings = DockSettings()
        if let size = number("tilesize") { settings.tileSize = size.clamped(16, 128) }
        if let size = number("largesize") { settings.largeSize = size.clamped(16, 128) }
        settings.largeSize = max(settings.largeSize, settings.tileSize)
        settings.magnification = bool("magnification", default: false)
        settings.orientation = (value("orientation") as? String).flatMap(DockOrientation.init) ?? .bottom
        settings.showRecents = bool("show-recents", default: true)
        settings.showIndicators = bool("show-process-indicators", default: true)
        return settings
    }

    static func readTiles(_ key: String) -> [DockTile] {
        guard let entries = value(key) as? [[String: Any]] else { return [] }
        return entries.compactMap(parseTile)
    }

    private static func parseTile(_ entry: [String: Any]) -> DockTile? {
        let tileType = entry["tile-type"] as? String ?? ""
        let data = entry["tile-data"] as? [String: Any] ?? [:]
        switch tileType {
        case "spacer-tile", "flex-spacer-tile":
            return DockTile(type: .spacer(small: false), label: "")
        case "small-spacer-tile":
            return DockTile(type: .spacer(small: true), label: "")
        case "file-tile", "directory-tile":
            guard let url = fileURL(from: data["file-data"] as? [String: Any]) else { return nil }
            let label = data["file-label"] as? String ?? url.deletingPathExtension().lastPathComponent
            if tileType == "file-tile" {
                return DockTile(type: .file, url: url, label: label,
                                bundleIdentifier: data["bundle-identifier"] as? String)
            }
            let options = StackOptions(
                display: StackDisplay(rawValue: (data["showas"] as? Int) ?? 0) ?? .automatic,
                arrangement: StackArrangement(rawValue: (data["arrangement"] as? Int) ?? 1) ?? .name,
                showsFolderIcon: (data["displayas"] as? Int) == 1)
            return DockTile(type: .directory(options), url: url, label: label)
        default:
            return nil
        }
    }

    private static func fileURL(from data: [String: Any]?) -> URL? {
        guard let string = data?["_CFURLString"] as? String else { return nil }
        // _CFURLStringType 15 is a file:// URL string, 0 is a POSIX path.
        if (data?["_CFURLStringType"] as? Int) == 0 {
            return URL(fileURLWithPath: string)
        }
        return URL(string: string)
    }

    // MARK: - Editing (Keep in Dock / Remove from Dock)

    static func isPinned(_ url: URL) -> Bool {
        readTiles("persistent-apps").contains { $0.url?.standardizedFileURL == url.standardizedFileURL }
    }

    static func pin(appAt url: URL) {
        var entries = value("persistent-apps") as? [[String: Any]] ?? []
        let bundle = Bundle(url: url)
        let tile: [String: Any] = [
            "tile-type": "file-tile",
            "tile-data": [
                "file-data": ["_CFURLString": url.absoluteString, "_CFURLStringType": 15],
                "file-label": FileManager.default.displayName(atPath: url.path)
                    .replacingOccurrences(of: ".app", with: ""),
                "bundle-identifier": bundle?.bundleIdentifier ?? "",
                "file-type": 41,
            ] as [String: Any],
        ]
        entries.append(tile)
        writeAndRestartDock("persistent-apps", entries)
    }

    static func unpin(_ url: URL) {
        let entries = value("persistent-apps") as? [[String: Any]] ?? []
        let kept = entries.filter { entry in
            let data = entry["tile-data"] as? [String: Any]
            return fileURL(from: data?["file-data"] as? [String: Any])?.standardizedFileURL != url.standardizedFileURL
        }
        guard kept.count != entries.count else { return }
        writeAndRestartDock("persistent-apps", kept)
    }

    /// The Dock only re-reads its tiles on launch, so edits require a restart (launchd relaunches it).
    private static func writeAndRestartDock(_ key: String, _ entries: [[String: Any]]) {
        CFPreferencesSetAppValue(key as CFString, entries as CFArray, domain)
        synchronize()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["Dock"]
        try? process.run()
    }
}

extension Comparable {
    func clamped(_ lower: Self, _ upper: Self) -> Self {
        min(max(self, lower), upper)
    }
}
