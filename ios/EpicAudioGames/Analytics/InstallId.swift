// analytics/InstallId.kt: the random ID usage data is sent under, kept in a file of its own.

import Foundation

/**
 * The random ID usage data is sent under (docs/DESIGN.md › Usage data): a UUID made the first time an event needs it,
 * and kept in [file] (Application Support/analytics/install_id). Never in a backup ([NoBackup]), so a device restored
 * from one, or the app installed again, starts with a new one; never in the keychain (which outlives the app) or
 * UserDefaults (which is backed up); no ID of the device's, the player's or their Apple Account's, so nothing else
 * knows it. Forgotten when usage data is turned off or deleted; the next event then makes a new one.
 *
 * Not thread-safe: only the usage data's own queue uses it (UsageData's [Worker]). Android: analytics/InstallId.kt
 * (no_backup/analytics/install_id).
 */
nonisolated final class InstallId: @unchecked Sendable {
    private let file: URL
    private let make: @Sendable () -> UUID
    private var id: String?
    private var read = false

    init(file: URL, make: @escaping @Sendable () -> UUID = { UUID() }) {
        self.file = file
        self.make = make
    }

    /// The ID, if there is one; a damaged file is none.
    func peek() -> String? {
        if !read {
            let text = try? String(contentsOf: file, encoding: .utf8)
            id = text.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.flatMap {
                Events.isUUID($0) ? $0 : nil
            }
            read = true
        }
        return id
    }

    /**
     * The ID, made now if there isn't one (in lower case, as the server keeps it). A file that can't be written (a
     * full device) leaves it in memory, for as long as the app runs.
     */
    func get() -> String {
        if let known = peek() { return known }
        let made = make().uuidString.lowercased()
        id = made
        do {
            try NoBackup.folder(file.deletingLastPathComponent())
            try Data(made.utf8).write(to: file, options: .atomic)
            NoBackup.exclude(file)
        } catch {
            // Kept in memory: the next run makes another.
        }
        return made
    }

    /// Forgets it: the file goes, and the next [get] makes another.
    func forget() {
        try? FileManager.default.removeItem(at: file)
        id = nil
        read = true
    }
}

/**
 * The usage data's folder and files, out of every backup (iCloud's and a computer's), as Android's no_backup is:
 * Application Support is backed up unless a file says otherwise, and a folder that says so keeps everything in it out.
 */
nonisolated enum NoBackup {
    /// [dir], made if it isn't there, and kept out of backups with all it holds.
    static func folder(_ dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        exclude(dir)
    }

    /// [url] (a folder or a file) kept out of backups. A file written whole again is a new file: it's said again.
    static func exclude(_ url: URL) {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var url = url
        try? url.setResourceValues(values)
    }
}
