// AppManifest.kt: the app's own audio and help, from content/app/app.json (built by tools/app_audio.py).

import Foundation

/**
 * The app's own audio and help, from content/app/app.json (bundled as Content/app/app.json): built by
 * tools/app_audio.py from tools/app_text.toml, so the words shown are the words spoken. The intro's [sting], the
 * [earcons]' lengths, the [welcome] and the [help] pages for this app: a page marked for Android is left out, one
 * marked for iOS or for neither kept, in the file's order.
 *
 * A page's clips are steps in the maps' format (docs/MAP_FORMAT.md), so TurnPlayer plays them as a turn, with "app" as
 * the game (Content/app/<path>.m4a). Read with the engine's JSON reader, as the maps are, and tested with the real file
 * (AppManifestTests). Android's AppManifest.kt.
 */
public struct AppManifest: Equatable, Sendable {
    /// The app's folder in the content, and the "game" its clips are played as.
    public static let folder = "app"
    /// This app's pages, besides those for both.
    public static let platform = "ios"

    /// The intro's sound; nil until one is picked (the intro then goes without it).
    public let sting: Sting?
    /// Each earcon's length in seconds, by its name ("listen-start": AppCue's raw value).
    public let earcons: [String: Double]
    public let welcome: HelpPage?
    public let help: [HelpPage]

    public init(sting: Sting?, earcons: [String: Double], welcome: HelpPage?, help: [HelpPage]) {
        self.sting = sting
        self.earcons = earcons
        self.welcome = welcome
        self.help = help
    }

    /// The help page [id] ("voice"), if this app has one.
    public func topic(_ id: String) -> HelpPage? {
        help.first { $0.id == id }
    }

    /// The manifest at [url] (the app's Content/app/app.json); nil if there's none (content without it) or it can't
    /// be read.
    public static func load(_ url: URL) -> AppManifest? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? parse(data)
    }

    /// Reads app.json's [data], keeping the pages for [platform] (and those for every platform).
    public static func parse(_ data: Data, platform: String = AppManifest.platform) throws -> AppManifest {
        try parse(JSONParser.parse(data), platform: platform)
    }

    /// Reads app.json's [text], keeping the pages for [platform] (and those for every platform).
    public static func parse(_ text: String, platform: String = AppManifest.platform) throws -> AppManifest {
        try parse(JSONParser.parse(text), platform: platform)
    }

    private static func parse(_ json: JSON, platform: String) throws -> AppManifest {
        let root = try json.jsonObject()
        var sting: Sting?
        if let s = root["sting"]?.objectValue {
            sting = Sting(
                file: try str(s, "file"), seconds: try num(s, "dur"), voiceAt: try num(s, "voiceAt"),
                voiceEnd: try num(s, "voiceEnd"), text: try str(s, "text"))
        }
        var earcons: [String: Double] = [:]
        for (name, e) in root["earcons"]?.objectValue ?? JSONObject() {
            earcons[name] = try e.objectValue.map { try num($0, "dur") } ?? 0
        }
        // A page with no platform is for both apps.
        func mine(_ page: JSONObject) -> Bool {
            optStr(page, "platform").map { $0 == platform } ?? true
        }
        var welcome: HelpPage?
        if let w = root["welcome"]?.objectValue, mine(w) {
            welcome = try page("welcome", w)
        }
        var help: [HelpPage] = []
        for entry in root["help"]?.arrayValue ?? [] {
            let o = try entry.jsonObject()
            if mine(o) { help.append(try page(try str(o, "id"), o)) }
        }
        return AppManifest(sting: sting, earcons: earcons, welcome: welcome, help: help)
    }

    private static func page(_ id: String, _ o: JSONObject) throws -> HelpPage {
        HelpPage(
            id: id,
            title: try str(o, "title"),
            summary: optStr(o, "summary") ?? "",
            text: try (o["text"]?.arrayValue ?? []).map { try $0.primitiveContent() },
            clipParagraph: (o["clipParagraph"]?.arrayValue ?? []).map { $0.intOrNull.map(Int.init) ?? -1 },
            steps: try (o["steps"]?.arrayValue ?? []).compactMap { try step(try $0.jsonObject()) },
            links: try (o["links"]?.arrayValue ?? []).map { l in
                let lo = try l.jsonObject()
                return HelpLink(label: try str(lo, "label"), url: try str(lo, "url"))
            })
    }

    /// A clip, a pause or a bed, as MapParser reads them; a step of another kind is left out.
    private static func step(_ o: JSONObject) throws -> Step? {
        if o.contains("play") {
            let lines = try (o["lines"]?.arrayValue ?? []).map { l -> Line in
                let lo = try l.jsonObject()
                // Each word's start, from the line's: what the highlight follows (HelpHighlight).
                let words = try lo["w"]?.arrayValue?.map { w -> Double in
                    let c = try w.primitiveContent()
                    guard let d = Kt.toDoubleOrNull(c) else {
                        throw AppManifestError("app.json: \"\(c)\" isn't a time")
                    }
                    return d
                }
                return Line(
                    at: try num(lo, "at"), len: lo["len"]?.doubleOrNull ?? 0, who: optStr(lo, "who") ?? "",
                    text: try str(lo, "text"), words: words)
            }
            return .play(Clip(path: try str(o, "play"), dur: try num(o, "dur"), lines: lines,
                              sfx: o["sfx"]?.booleanOrNull == true))
        }
        if o.contains("pause") { return .pause(try num(o, "pause")) }
        if o.contains("bed") {
            var path: String?
            if case .string(let s) = o["bed"] { path = s }
            return .bed(path: path, volume: o["volume"]?.doubleOrNull ?? 1, dur: o["dur"]?.doubleOrNull ?? 0)
        }
        return nil
    }

    private static func str(_ o: JSONObject, _ key: String) throws -> String {
        guard let s = optStr(o, key) else { throw AppManifestError("app.json: missing \"\(key)\"") }
        return s
    }

    private static func optStr(_ o: JSONObject, _ key: String) -> String? {
        if case .string(let s) = o[key] { return s }
        return nil
    }

    private static func num(_ o: JSONObject, _ key: String) throws -> Double {
        guard let d = o[key]?.doubleOrNull else { throw AppManifestError("app.json: missing number \"\(key)\"") }
        return d
    }
}

/// app.json that can't be read: something missing, or not what it should be (Android's IllegalArgumentException).
public struct AppManifestError: Error, Equatable, Sendable, CustomStringConvertible {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var description: String { message }
}

/// The intro's sound: [file] in the app's folder, [seconds] long, the voice saying [text] from [voiceAt] to [voiceEnd].
public struct Sting: Equatable, Sendable {
    public let file: String
    public let seconds: Double
    public let voiceAt: Double
    public let voiceEnd: Double
    public let text: String

    public init(file: String, seconds: Double, voiceAt: Double, voiceEnd: Double, text: String) {
        self.file = file
        self.seconds = seconds
        self.voiceAt = voiceAt
        self.voiceEnd = voiceEnd
        self.text = text
    }
}

/**
 * A page the app shows and can read aloud: the welcome, or a help topic. [text] is its paragraphs as shown; [steps] its
 * clips (one per paragraph, with pauses, and the earcons it plays as examples), each clip's paragraph in
 * [clipParagraph] (-1 for an earcon, which has no words). Android's HelpPage.
 */
public struct HelpPage: Equatable, Sendable {
    public let id: String
    public let title: String
    /// One line about it, for the list of topics.
    public let summary: String
    public let text: [String]
    public let clipParagraph: [Int]
    public let steps: [Step]
    public let links: [HelpLink]

    public init(
        id: String, title: String, summary: String, text: [String], clipParagraph: [Int], steps: [Step],
        links: [HelpLink]
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.text = text
        self.clipParagraph = clipParagraph
        self.steps = steps
        self.links = links
    }

    /// Each clip's lines, in order (a clip is a .play step; TurnPlayer's position counts them so).
    public var clipLines: [[Line]] {
        steps.compactMap { if case .play(let clip) = $0 { clip.lines } else { nil } }
    }

    /// Whether it has anything to play.
    public var hasClips: Bool {
        steps.contains { if case .play = $0 { true } else { false } }
    }
}

/// A link under a help page's text: a web page, or an email (mailto:).
public struct HelpLink: Equatable, Sendable {
    public let label: String
    public let url: String

    public init(label: String, url: String) {
        self.label = label
        self.url = url
    }
}
