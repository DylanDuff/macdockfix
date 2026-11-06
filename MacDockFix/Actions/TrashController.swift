import AppKit

/// Trash state and actions go through Finder: `~/.Trash` is TCC-protected (needs Full Disk Access),
/// whereas Apple Events to Finder only need the one-time Automation prompt.
final class TrashController {
    private let queue = DispatchQueue(label: "macdockfix.trash")
    private var timer: Timer?

    func startMonitoring(_ update: @escaping @MainActor (Bool) -> Void) {
        let poll: @Sendable () -> Void = { [queue] in
            queue.async {
                let result = Self.runScript("tell application \"Finder\" to return (count of items of trash) > 0")
                Task { @MainActor in update(result == "true") }
            }
        }
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { _ in poll() }
    }

    func reveal() {
        queue.async {
            _ = Self.runScript("tell application \"Finder\"\nopen trash\nactivate\nend tell")
        }
    }

    func empty() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Are you sure you want to permanently erase the items in the Trash?"
        alert.informativeText = "You can't undo this action."
        alert.addButton(withTitle: "Empty Trash")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        queue.async {
            _ = Self.runScript("tell application \"Finder\" to empty trash")
        }
    }

    /// osascript in a child process: NSAppleScript is main-thread-bound and Finder can be slow to answer.
    nonisolated private static func runScript(_ source: String) -> String? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
