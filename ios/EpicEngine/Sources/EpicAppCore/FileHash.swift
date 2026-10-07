// Packs.kt's sha256 (lines 58-69): a file's SHA-256, read 64 KB at a time, in lowercase hex.

import CryptoKit
import Foundation

public enum FileHash {
    /// [file]'s SHA-256 as 64 lowercase hex digits (Packs.kt's "%02x" per byte).
    public static func sha256(_ file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 16), !chunk.isEmpty {
            hash.update(data: chunk)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
