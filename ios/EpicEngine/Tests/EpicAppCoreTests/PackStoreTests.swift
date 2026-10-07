// PackStore.swift, StoredZip.swift and FileHash.swift: Packs.kt's install, with the zips tools/make_pack.py writes.

import CryptoKit
import Foundation
import Testing

@testable import EpicAppCore

struct PackStoreTests {
    let scratch: Scratch
    let store: PackStore

    init() throws {
        scratch = try Scratch()
        store = PackStore(root: scratch.folder("packs"))
    }

    private static let packJSON = #"{"format": 1, "game": "frootopia", "id": "frootopia-stories", "nodes": {}}"#

    /// The pack's catalog entry for [zip] (its real size and checksum), at [version].
    private func pack(_ zip: URL, version: Int = 1, game: String = "frootopia") throws -> PackInfo {
        let size = try FileManager.default.attributesOfItem(atPath: zip.path)[.size] as? NSNumber
        return PackInfo(
            id: "frootopia-stories", game: game, title: "Stories 2 to 5", description: "", product: "frootopia_stories",
            version: version, size: size?.int64Value ?? 0, sha256: try FileHash.sha256(zip))
    }

    private func zip(_ name: String, _ entries: [TestZip.Entry]) throws -> URL {
        let url = scratch.url.appendingPathComponent(name)
        try TestZip.write(entries, to: url)
        return url
    }

    private func text(_ url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }

    @Test func aPackIsInstalledFromItsZip() throws {
        let zip = try zip("p.zip", [
            .file("pack.json", Self.packJSON),
            .directory("scenes/"),
            .file("scenes/fr2-0.m4a", String(repeating: "a", count: 200_000)),
            .file("prompts/fr2-1.m4a", "b"),
        ])
        let pack = try pack(zip)
        #expect(!store.isInstalled(pack))
        try store.install(pack, zip: zip)
        let dir = try #require(store.folder(pack))
        #expect(dir.lastPathComponent == "frootopia-stories")
        #expect(try text(dir.appendingPathComponent("pack.json")) == Self.packJSON)
        #expect(try text(dir.appendingPathComponent("scenes/fr2-0.m4a")).count == 200_000)
        #expect(try text(dir.appendingPathComponent("prompts/fr2-1.m4a")) == "b")
        #expect(try text(dir.appendingPathComponent(".version")) == "1")
        #expect(!FileManager.default.fileExists(atPath: store.root.appendingPathComponent("frootopia-stories.new").path))
        let game = GameInfo(id: "frootopia", title: "F", blurb: "", free: "", packs: [pack])
        #expect(store.installed(game) == [InstalledPack(pack: pack, folder: dir)])
        // Kept out of backups.
        let values = try store.root.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }

    /// A new version replaces the old one whole; the catalog's version is the one that counts. Until it's in, the
    /// old one stays in use, at its own version (a save in it plays on, and the map is loaded again once it's in).
    @Test func aNewVersionReplacesTheOld() throws {
        let one = try zip("1.zip", [.file("pack.json", Self.packJSON), .file("old.m4a", "old")])
        try store.install(try pack(one, version: 1), zip: one)
        let two = try zip("2.zip", [.file("pack.json", Self.packJSON), .file("new.m4a", "new")])
        let v2 = try pack(two, version: 2)
        #expect(!store.isInstalled(v2))             // the catalog's version 2 isn't the one on the phone
        #expect(store.folder(v2) == nil)
        let game = GameInfo(id: "frootopia", title: "F", blurb: "", free: "", packs: [v2])
        let old = try #require(store.installed(game).first)
        #expect(old.pack == v2.at(version: 1))
        #expect(old.folder.lastPathComponent == "frootopia-stories")
        try store.install(v2, zip: two)
        #expect(store.installed(game) == [InstalledPack(pack: v2, folder: try #require(store.folder(v2)))])
        let dir = try #require(store.folder(v2))
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("new.m4a").path))
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("old.m4a").path))
        #expect(!store.isInstalled(try pack(one, version: 1)))
    }

    @Test func theSizeAndChecksumMustBeTheCatalogs() throws {
        let zip = try zip("p.zip", [.file("pack.json", Self.packJSON)])
        let good = try pack(zip)
        let small = PackInfo(id: good.id, game: good.game, title: good.title, description: "", product: good.product,
                             version: 1, size: good.size - 1, sha256: good.sha256)
        #expect(throws: PackError("the download is \(good.size) bytes, not \(good.size - 1)")) {
            try store.install(small, zip: zip)
        }
        let other = PackInfo(id: good.id, game: good.game, title: good.title, description: "", product: good.product,
                             version: 1, size: good.size, sha256: String(repeating: "0", count: 64))
        #expect(throws: PackError("the download's checksum isn't the pack's")) { try store.install(other, zip: zip) }
        #expect(!store.isInstalled(good))
    }

    @Test func aPackMustHaveItsPackJSON() throws {
        let zip = try zip("p.zip", [.file("scenes/a.m4a", "a")])
        #expect(throws: PackError("no pack.json in frootopia-stories")) { try store.install(try pack(zip), zip: zip) }
        #expect(!FileManager.default.fileExists(atPath: store.root.appendingPathComponent("frootopia-stories.new").path))
    }

    /// Packs.kt's canonical-path check: nothing lands outside the pack's folder.
    @Test func aPathOutsideThePackIsRefused() throws {
        for name in ["../evil.m4a", "scenes/../../evil.m4a", "a/b/../../../evil.m4a", "/../evil.m4a"] {
            let zip = try zip("slip.zip", [.file("pack.json", Self.packJSON), .file(name, "evil")])
            #expect(throws: ZipError("a path outside the pack: \(name)")) { try store.install(try pack(zip), zip: zip) }
        }
        #expect(!FileManager.default.fileExists(atPath: scratch.url.appendingPathComponent("evil.m4a").path))
        // ".." inside a name, and a path that stays inside, are fine.
        let fine = try zip("fine.zip", [.file("pack.json", Self.packJSON), .file("a..b/c.m4a", "c"),
                                         .file("x/./y.m4a", "y"), .file("x/../z.m4a", "z"),
                                         .file("/abs.m4a", "abs")])
        try store.install(try pack(fine), zip: fine)
        let dir = try #require(store.folder(try pack(fine)))
        #expect(try text(dir.appendingPathComponent("z.m4a")) == "z")
        #expect(try text(dir.appendingPathComponent("x/y.m4a")) == "y")
        #expect(try text(dir.appendingPathComponent("abs.m4a")) == "abs")      // File(tmp, "/abs.m4a")
    }

    @Test func compressedAndBrokenZipsAreRefused() throws {
        let deflated = try zip("d.zip", [.file("pack.json", Self.packJSON, method: 8)])
        #expect(throws: ZipError("pack.json is compressed (packs are stored)")) {
            try store.install(try pack(deflated), zip: deflated)
        }
        let locked = try zip("e.zip", [.file("pack.json", Self.packJSON, encrypted: true)])
        #expect(throws: ZipError("pack.json is encrypted")) { try store.install(try pack(locked), zip: locked) }
        let notZip = try scratch.write("n.zip", "not a zip at all, just some text that goes on for a while")
        #expect(throws: ZipError("not a zip")) { try store.install(try pack(notZip), zip: notZip) }
    }

    @Test func entriesAreReadFromTheDirectory() throws {
        let zip = try zip("p.zip", [.file("pack.json", "{}", extra: 9), .directory("audio/"), .file("audio/x", "xyz")])
        let entries = try StoredZip.entries(zip)
        #expect(entries.map(\.name) == ["pack.json", "audio/", "audio/x"])
        #expect(entries.map(\.size) == [2, 0, 3])
        #expect(entries[1].isDirectory)
        let data = try Data(contentsOf: zip)
        let x = entries[2]
        #expect(String(decoding: data[Int(x.offset)..<Int(x.offset + x.size)], as: UTF8.self) == "xyz")
    }

    /// What an unpacking that didn't finish left (the app stopped, the phone full) goes as the store starts.
    @Test func cleanUpTakesAwayUnfinishedUnpacking() throws {
        let zip = try zip("p.zip", [.file("pack.json", Self.packJSON)])
        let pack = try pack(zip)
        try store.install(pack, zip: zip)
        let stray = store.root.appendingPathComponent("the-werewolf-stories.new/audio", isDirectory: true)
        try FileManager.default.createDirectory(at: stray, withIntermediateDirectories: true)
        try Data("half".utf8).write(to: stray.appendingPathComponent("a.m4a"))
        store.cleanUp()
        #expect(!FileManager.default.fileExists(atPath: stray.deletingLastPathComponent().path))
        #expect(store.isInstalled(pack))
        PackStore(root: scratch.folder("none")).cleanUp()       // no folder yet: nothing to do
    }

    /// The room a pack needs is checked before it's downloaded: 2.2 times its size.
    @Test func roomForAPack() throws {
        let small = PackInfo(id: "p", game: "g", title: "P", description: "", product: "p", version: 1, size: 1_000,
                             sha256: "")
        #expect(small.roomNeeded == 2_200)
        #expect(store.hasRoom(for: small))          // the folder isn't there yet: its volume's room counts
        let huge = PackInfo(id: "p", game: "g", title: "P", description: "", product: "p", version: 1,
                            size: 1 << 55, sha256: "")
        #expect(!store.hasRoom(for: huge))
    }

    @Test func removeTakesThePackAway() throws {
        let zip = try zip("p.zip", [.file("pack.json", Self.packJSON)])
        let pack = try pack(zip)
        try store.install(pack, zip: zip)
        try store.remove(pack)
        #expect(!store.isInstalled(pack))
        try store.remove(pack)        // already gone
    }

    @Test func fileHashIsLowercaseHex() throws {
        let file = try scratch.write("h.txt", "hello")
        #expect(try FileHash.sha256(file) == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
        let big = scratch.url.appendingPathComponent("big")
        let bytes = Data((0..<200_000).map { UInt8($0 % 251) })
        try bytes.write(to: big)
        #expect(try FileHash.sha256(big) == SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined())
    }

    /// The real pack, if this machine has it (dist/packs): it installs as the catalog says.
    @Test func theRealFrootopiaPackInstalls() throws {
        let game = try AppTestRepo.game("frootopia")
        let pack = try #require(game.packs.first)
        let zip = try AppTestRepo.games().deletingLastPathComponent()
            .appendingPathComponent("dist/packs/\(pack.zipName)")
        guard FileManager.default.fileExists(atPath: zip.path) else { return }
        try store.install(pack, zip: zip)
        #expect(store.isInstalled(pack))
    }
}

/// Writes small zips the way Python's zipfile does (local headers, then the central directory), with whatever
/// method, flags and names a test needs. The bytes of a "compressed" entry are left as they are: the reader must
/// refuse it before reading them.
enum TestZip {
    struct Entry {
        let name: String
        let data: Data
        var method: UInt16 = 0
        var encrypted = false
        var extra = 0

        static func file(_ name: String, _ text: String, method: UInt16 = 0, encrypted: Bool = false,
                         extra: Int = 0) -> Entry {
            Entry(name: name, data: Data(text.utf8), method: method, encrypted: encrypted, extra: extra)
        }

        static func directory(_ name: String) -> Entry { Entry(name: name, data: Data()) }
    }

    static func write(_ entries: [Entry], to url: URL) throws {
        var out = Data()
        var central = Data()
        for e in entries {
            let offset = UInt32(out.count)
            let name = Data(e.name.utf8)
            let crc = crc32(e.data)
            let flags: UInt16 = e.encrypted ? 1 : 0
            // The local header has a longer extra field than the directory, as some writers do.
            out.le32(0x0403_4b50); out.le16(20); out.le16(flags); out.le16(e.method); out.le16(0); out.le16(0)
            out.le32(crc); out.le32(UInt32(e.data.count)); out.le32(UInt32(e.data.count))
            out.le16(UInt16(name.count)); out.le16(UInt16(e.extra))
            out.append(name)
            out.append(Data(repeating: 0, count: e.extra))
            out.append(e.data)
            central.le32(0x0201_4b50); central.le16(20); central.le16(20); central.le16(flags); central.le16(e.method)
            central.le16(0); central.le16(0); central.le32(crc); central.le32(UInt32(e.data.count))
            central.le32(UInt32(e.data.count)); central.le16(UInt16(name.count)); central.le16(0); central.le16(0)
            central.le16(0); central.le16(0); central.le32(0); central.le32(offset)
            central.append(name)
        }
        let start = UInt32(out.count)
        out.append(central)
        out.le32(0x0605_4b50); out.le16(0); out.le16(0); out.le16(UInt16(entries.count)); out.le16(UInt16(entries.count))
        out.le32(UInt32(central.count)); out.le32(start); out.le16(0)
        try out.write(to: url)
    }

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = crc & 1 != 0 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1 }
        }
        return ~crc
    }
}

private extension Data {
    mutating func le16(_ v: UInt16) { append(contentsOf: [UInt8(v & 0xFF), UInt8(v >> 8)]) }
    mutating func le32(_ v: UInt32) { le16(UInt16(v & 0xFFFF)); le16(UInt16(v >> 16)) }
}
