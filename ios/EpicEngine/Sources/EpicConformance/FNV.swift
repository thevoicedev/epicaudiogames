// Canon.kt's fnv and hex: 64-bit FNV-1a over UTF-16 code units (fixtures/engine/README.md, section 3).

/// 64-bit FNV-1a over a string's UTF-16 code units (not its UTF-8 bytes), as the fixtures' hashes are made.
public enum FNV {
    public static let start: UInt64 = 0xcbf2_9ce4_8422_2325
    static let prime: UInt64 = 0x100_0000_01b3

    /// The hash of [s], carried on from [h] (so lines can be hashed one after another).
    public static func hash(_ s: String, _ h: UInt64 = start) -> UInt64 {
        var h = h
        var s = s
        // The UTF-8 bytes decoded to UTF-16 units as we go: much faster than s.utf16, and the same units.
        s.withUTF8 { b in
            var i = 0
            while i < b.count {
                let b0 = b[i]
                if b0 < 0x80 {
                    h = (h ^ UInt64(b0)) &* prime
                    i += 1
                    continue
                }
                var scalar: UInt32
                let len: Int
                if b0 < 0xE0 {
                    scalar = UInt32(b0 & 0x1F)
                    len = 2
                } else if b0 < 0xF0 {
                    scalar = UInt32(b0 & 0x0F)
                    len = 3
                } else {
                    scalar = UInt32(b0 & 0x07)
                    len = 4
                }
                for k in 1..<len { scalar = (scalar << 6) | UInt32(b[i + k] & 0x3F) }
                i += len
                if scalar >= 0x10000 {
                    let v = scalar - 0x10000
                    h = (h ^ UInt64(0xD800 + (v >> 10))) &* prime
                    h = (h ^ UInt64(0xDC00 + (v & 0x3FF))) &* prime
                } else {
                    h = (h ^ UInt64(scalar)) &* prime
                }
            }
        }
        return h
    }

    /// 16 lowercase hex digits, zero padded.
    public static func hex(_ h: UInt64) -> String {
        let digits = String(h, radix: 16)
        return String(repeating: "0", count: 16 - digits.count) + digits
    }
}
