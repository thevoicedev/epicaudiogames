// Packs.kt's install (lines 37-50): a pack's zip unpacked into a folder, refusing any path outside it.

import Foundation

/// A zip that can't be unpacked (Android's ZipException, or the require() for a path outside the pack).
public struct ZipError: Error, Equatable, Sendable, CustomStringConvertible {
    public let message: String

    public init(_ message: String) { self.message = message }

    public var description: String { message }
}

/**
 * Unpacks a zip whose entries are STORED (not compressed), as tools/make_pack.py writes packs: their audio is
 * already compressed. It reads the central directory, then copies each entry's bytes out. An entry whose path would
 * land outside the folder ("..") is refused, as Packs.kt refuses one whose canonical path isn't inside the pack (a
 * name starting with "/" lands inside it, as java.io.File(parent, child) puts it). A compressed or encrypted entry is refused too (Android's ZipInputStream
 * would inflate one; no pack has them).
 */
public enum StoredZip {
    /// An entry: its path in the zip, where its bytes start in the file, and how many there are.
    public struct Entry: Equatable, Sendable {
        public let name: String
        public let offset: UInt64
        public let size: UInt64

        public var isDirectory: Bool { name.hasSuffix("/") }
    }

    /// Unpacks [zip] into [folder] (which must exist): its files, and its folders, even empty ones.
    public static func unpack(_ zip: URL, into folder: URL) throws {
        let handle = try FileHandle(forReadingFrom: zip)
        defer { try? handle.close() }
        let top = folder.standardizedFileURL.path
        let fm = FileManager.default
        for e in try entries(handle) {
            let out = try destination(e.name, in: folder, top: top)
            if e.isDirectory {
                try fm.createDirectory(at: out, withIntermediateDirectories: true)
                continue
            }
            try fm.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard fm.createFile(atPath: out.path, contents: nil) else { throw ZipError("can't write \(e.name)") }
            let writer = try FileHandle(forWritingTo: out)
            defer { try? writer.close() }
            try handle.seek(toOffset: e.offset)
            var left = e.size
            while left > 0 {
                let n = Int(min(left, 1 << 16))
                guard let chunk = try handle.read(upToCount: n), chunk.count == n else {
                    throw ZipError("\(e.name) is cut short")
                }
                try writer.write(contentsOf: chunk)
                left -= UInt64(n)
            }
        }
    }

    /// The zip's entries, from its central directory, with where each one's bytes are.
    public static func entries(_ zip: URL) throws -> [Entry] {
        let handle = try FileHandle(forReadingFrom: zip)
        defer { try? handle.close() }
        return try entries(handle)
    }

    /// Where an entry goes under [folder]; an error for a path outside it.
    static func destination(_ name: String, in folder: URL, top: String) throws -> URL {
        let bad = ZipError("a path outside the pack: \(name)")
        if name.isEmpty || name.contains("\0") { throw bad }
        let out = folder.appendingPathComponent(name, isDirectory: name.hasSuffix("/")).standardizedFileURL
        guard out.path.hasPrefix(top.hasSuffix("/") ? top : top + "/") else { throw bad }
        return out
    }

    // ----- The zip's structure -----

    private static let endSignature: UInt32 = 0x0605_4b50
    private static let centralSignature: UInt32 = 0x0201_4b50
    private static let localSignature: UInt32 = 0x0403_4b50

    private static func entries(_ handle: FileHandle) throws -> [Entry] {
        let length = try handle.seekToEnd()
        // The end record is 22 bytes, followed by a comment of up to 65535.
        let tail = min(length, 22 + 65_535)
        try handle.seek(toOffset: length - tail)
        let end = try handle.read(upToCount: Int(tail)) ?? Data()
        guard end.count >= 22,
              let at = stride(from: end.count - 22, through: 0, by: -1).first(where: { end.u32($0) == endSignature })
        else { throw ZipError("not a zip") }
        let count = Int(end.u16(at + 10))
        let size = UInt64(end.u32(at + 12))
        let start = UInt64(end.u32(at + 16))
        if count == 0xFFFF || start == 0xFFFF_FFFF { throw ZipError("a zip64 file isn't supported") }
        guard start + size <= length else { throw ZipError("the zip's directory is cut short") }
        try handle.seek(toOffset: start)
        let dir = try handle.read(upToCount: Int(size)) ?? Data()
        guard dir.count == Int(size) else { throw ZipError("the zip's directory is cut short") }

        var out: [Entry] = []
        var p = 0
        for _ in 0..<count {
            guard p + 46 <= dir.count, dir.u32(p) == centralSignature else { throw ZipError("a bad zip directory") }
            let flags = dir.u16(p + 8)
            let method = dir.u16(p + 10)
            let compressed = UInt64(dir.u32(p + 20))
            let stored = UInt64(dir.u32(p + 24))
            let nameLength = Int(dir.u16(p + 28))
            let extra = Int(dir.u16(p + 30))
            let comment = Int(dir.u16(p + 32))
            let local = UInt64(dir.u32(p + 42))
            guard p + 46 + nameLength <= dir.count else { throw ZipError("a bad zip directory") }
            let name = String(decoding: dir[(dir.startIndex + p + 46)..<(dir.startIndex + p + 46 + nameLength)],
                              as: UTF8.self)
            if flags & 1 != 0 { throw ZipError("\(name) is encrypted") }
            if method != 0 || compressed != stored { throw ZipError("\(name) is compressed (packs are stored)") }
            out.append(Entry(name: name, offset: try dataStart(handle, local, length: length), size: stored))
            p += 46 + nameLength + extra + comment
        }
        for e in out where e.offset + e.size > length { throw ZipError("\(e.name) is cut short") }
        return out
    }

    /// Where an entry's bytes start: after its local header, whose name and extra field can differ in length from
    /// the directory's.
    private static func dataStart(_ handle: FileHandle, _ local: UInt64, length: UInt64) throws -> UInt64 {
        guard local + 30 <= length else { throw ZipError("a bad zip entry") }
        try handle.seek(toOffset: local)
        let header = try handle.read(upToCount: 30) ?? Data()
        guard header.count == 30, header.u32(0) == localSignature else { throw ZipError("a bad zip entry") }
        return local + 30 + UInt64(header.u16(26)) + UInt64(header.u16(28))
    }
}

private extension Data {
    func u16(_ i: Int) -> UInt16 {
        UInt16(self[startIndex + i]) | UInt16(self[startIndex + i + 1]) << 8
    }

    func u32(_ i: Int) -> UInt32 {
        UInt32(u16(i)) | UInt32(u16(i + 2)) << 16
    }
}
