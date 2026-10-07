// Packs.kt: the packs on this phone, each unpacked in its own folder.

import Foundation

/// A pack that couldn't be installed (Packs.kt's require and check failures), with Android's wording.
public struct PackError: Error, Equatable, Sendable, CustomStringConvertible {
    public let message: String

    public init(_ message: String) { self.message = message }

    public var description: String { message }
}

/**
 * The packs on this phone, each unpacked in <root>/<id>/: its pack.json (the nodes it adds to its game's map) and its
 * audio, under the same paths as the game's own. A pack is installed only from a zip whose size and SHA-256 are the
 * catalog's, and replaces any older version of itself; until then the older one stays in use. The app's root is
 * Application Support/packs, kept out of backups (the packs download again).
 */
public final class PackStore: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// The app's own: Application Support/packs.
    public static func standard() throws -> PackStore {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return PackStore(root: support.appendingPathComponent("packs", isDirectory: true))
    }

    /**
     * A game's installed packs, in the catalog's order, with their folders. Each is as it is on the phone: an older
     * version stays in use (a save in it plays on) until its update replaces it, and its version is the one on disk.
     */
    public func installed(_ game: GameInfo) -> [InstalledPack] {
        game.packs.compactMap { p in
            let dir = directory(p)
            return version(dir).map { InstalledPack(pack: p.at(version: $0), folder: dir) }
        }
    }

    /// Installed at the catalog's version (an older one is downloaded again).
    public func isInstalled(_ pack: PackInfo) -> Bool { folder(pack) != nil }

    /// A pack's folder, if it's there at the catalog's version with its pack.json.
    public func folder(_ pack: PackInfo) -> URL? {
        let dir = directory(pack)
        return version(dir) == pack.version ? dir : nil
    }

    /// Whether there's room for a pack: its zip and the pack unpacked from it ([PackInfo.roomNeeded]).
    public func hasRoom(for pack: PackInfo) -> Bool {
        var url = root
        while !FileManager.default.fileExists(atPath: url.path), url.pathComponents.count > 1 {
            url = url.deletingLastPathComponent()
        }
        let free = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage
        guard let free, free > 0 else { return true }        // not known: the download says if it's full
        return free >= pack.roomNeeded
    }

    /// Takes away what an unpacking that didn't finish left behind (the app stopped, or the phone was full).
    public func cleanUp() {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        for name in names where name.hasSuffix(".new") {
            try? FileManager.default.removeItem(at: root.appendingPathComponent(name, isDirectory: true))
        }
    }

    private func directory(_ pack: PackInfo) -> URL { root.appendingPathComponent(pack.id, isDirectory: true) }

    /// The version in a pack's folder, if it's there with its pack.json.
    private func version(_ dir: URL) -> Int? {
        guard let text = try? String(contentsOf: dir.appendingPathComponent(Self.version), encoding: .utf8),
              let version = Int(Kt.trim(text)),
              FileManager.default.fileExists(atPath: dir.appendingPathComponent("pack.json").path)
        else { return nil }
        return version
    }

    /// Unpacks a downloaded zip, after checking it is the catalog's. Slow for a big pack: not on the main actor.
    public func install(_ pack: PackInfo, zip: URL) throws {
        let fm = FileManager.default
        let size = (try? fm.attributesOfItem(atPath: zip.path)[.size] as? NSNumber)?.int64Value ?? -1
        guard size == pack.size else { throw PackError("the download is \(size) bytes, not \(pack.size)") }
        guard try FileHash.sha256(zip) == pack.sha256 else { throw PackError("the download's checksum isn't the pack's") }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        excludeFromBackup()
        let tmp = root.appendingPathComponent("\(pack.id).new", isDirectory: true)
        try? fm.removeItem(at: tmp)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        do {
            try StoredZip.unpack(zip, into: tmp)
            guard fm.fileExists(atPath: tmp.appendingPathComponent("pack.json").path) else {
                throw PackError("no pack.json in \(pack.id)")
            }
            try Data(String(pack.version).utf8).write(to: tmp.appendingPathComponent(Self.version))
            let dir = root.appendingPathComponent(pack.id, isDirectory: true)
            try? fm.removeItem(at: dir)
            do {
                try fm.moveItem(at: tmp, to: dir)
            } catch {
                throw PackError("couldn't put \(pack.id) in place")
            }
        } catch {
            try? fm.removeItem(at: tmp)
            throw error
        }
    }

    /// Takes a pack off the phone (a refunded purchase, D11). The caller waits until its game is closed (L13).
    public func remove(_ pack: PackInfo) throws {
        let dir = root.appendingPathComponent(pack.id, isDirectory: true)
        if FileManager.default.fileExists(atPath: dir.path) { try FileManager.default.removeItem(at: dir) }
    }

    private func excludeFromBackup() {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var url = root
        try? url.setResourceValues(values)
    }

    private static let version = ".version"
}
