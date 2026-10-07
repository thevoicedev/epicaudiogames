// ui/Theme.kt's speaker colours (lines 63-70): each character's name colour, picked by name so each keeps theirs.

/// An sRGB colour as 0xRRGGBB, for the UI to turn into its own colour type.
public struct RGBColor: Equatable, Hashable, Sendable, CustomStringConvertible {
    public let hex: UInt32

    public init(_ hex: UInt32) {
        self.hex = hex & 0xFFFFFF
    }

    public var red: Double { Double((hex >> 16) & 0xFF) / 255 }
    public var green: Double { Double((hex >> 8) & 0xFF) / 255 }
    public var blue: Double { Double(hex & 0xFF) / 255 }

    /// "#C23D0A".
    public var description: String {
        let digits = String(hex, radix: 16, uppercase: true)
        return "#" + String(repeating: "0", count: 6 - digits.count) + digits
    }
}

public enum SpeakerPalette {
    /// The narrator's colour: the ink the text is in (Palette.ink).
    public static let ink = RGBColor(0x1F3B5C)

    /// Each at least 4.5:1 on white (the names are small).
    public static let colors: [RGBColor] = [
        RGBColor(0x2F72B9), RGBColor(0xC23D0A), RGBColor(0x237A36), RGBColor(0x862E9C), RGBColor(0xC2255C),
        RGBColor(0x0B7285), RGBColor(0xA85600), RGBColor(0x5F3DC4),
    ]

    /// A speaker's name colour: by the Java hash of their key, so each character keeps theirs; the narrator's is ink.
    public static func color(_ who: String) -> RGBColor {
        if Kt.utf16Equal(who, "NARRATOR") { return ink }
        return colors[Int(Kt.floorMod(Kt.javaHash(who), Int32(colors.count)))]
    }
}
