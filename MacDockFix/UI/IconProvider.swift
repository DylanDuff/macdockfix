import AppKit

/// Icons for dock tiles, cached by path. Folder "stack" icons are refreshed every few seconds
/// because they show the folder's top item.
final class IconProvider {
    static let shared = IconProvider()

    private var files: [String: NSImage] = [:]
    private var stacks: [String: (image: NSImage, made: Date)] = [:]
    private static let stackLifetime: TimeInterval = 5

    private let trashEmpty = NSImage(contentsOfFile:
        "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/TrashIcon.icns")
    private let trashFull = NSImage(contentsOfFile:
        "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/FullTrashIcon.icns")

    func icon(for item: DockItem, trashFull isFull: Bool) -> NSImage? {
        switch item.kind {
        case .trash:
            return (isFull ? trashFull : trashEmpty) ?? NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
        case .folder(let options):
            guard let url = item.url else { return nil }
            return options.showsFolderIcon ? icon(forFile: url) : stackIcon(url, arrangement: options.arrangement)
        case .app, .file:
            if let app = item.runningApplication, item.url == nil { return app.icon }
            return item.url.map(icon(forFile:))
        case .spacer, .separator:
            return nil
        }
    }

    func icon(forFile url: URL) -> NSImage {
        if let cached = files[url.path] { return cached }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        files[url.path] = image
        return image
    }

    private func stackIcon(_ url: URL, arrangement: StackArrangement) -> NSImage {
        if let cached = stacks[url.path], Date.now.timeIntervalSince(cached.made) < Self.stackLifetime {
            return cached.image
        }
        let image = FolderContents.list(url, arrangement: arrangement).first
            .map { NSWorkspace.shared.icon(forFile: $0.path) } ?? icon(forFile: url)
        stacks[url.path] = (image, .now)
        return image
    }
}

enum FolderContents {
    static func list(_ folder: URL, arrangement: StackArrangement) -> [URL] {
        let keys: [URLResourceKey] = [.nameKey, .addedToDirectoryDateKey, .contentModificationDateKey,
                                      .creationDateKey, .localizedTypeDescriptionKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        else { return [] }

        func values(_ url: URL) -> URLResourceValues? { try? url.resourceValues(forKeys: Set(keys)) }
        func newestFirst(_ key: (URLResourceValues) -> Date?) -> [URL] {
            urls.sorted { (values($0).flatMap(key) ?? .distantPast) > (values($1).flatMap(key) ?? .distantPast) }
        }

        switch arrangement {
        case .name:
            return urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        case .dateAdded: return newestFirst(\.addedToDirectoryDate)
        case .dateModified: return newestFirst(\.contentModificationDate)
        case .dateCreated: return newestFirst(\.creationDate)
        case .kind:
            return urls.sorted {
                (values($0)?.localizedTypeDescription ?? "", $0.lastPathComponent)
                    < (values($1)?.localizedTypeDescription ?? "", $1.lastPathComponent)
            }
        }
    }
}
