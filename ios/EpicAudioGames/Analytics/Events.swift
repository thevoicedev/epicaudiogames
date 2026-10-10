// analytics/Events.kt: every event the app sends as usage data, the server's whitelist as the app has it, and an
// event as the server takes it.

import Foundation

/**
 * Something that happened in the app, for the usage data (docs/DESIGN.md › Usage data): an event of
 * web/analytics/events.json, the whitelist our server checks every event against, with some of the details it lists
 * for that event and nothing else. Made by [Events], never by hand. Android: analytics/Events.kt.
 */
nonisolated struct Event: Sendable, Equatable, CustomStringConvertible {
    let name: String
    /// Its details: yes or no (Bool), a count (Int), or a few words (String): an id, or one of a few fixed words.
    let props: [String: any Sendable]

    /// An event with these details; a detail that's nil is left out (the event hasn't got it).
    init(_ name: String, _ props: [String: (any Sendable)?] = [:]) {
        self.name = name
        self.props = props.compactMapValues { $0 }
    }

    /// An event as the app's code told it (Analytics.track's name and details).
    init(name: String, props: [String: any Sendable]) {
        self.name = name
        self.props = props
    }

    /// The same event with the same details (the details compared as they'd be sent).
    static func == (a: Event, b: Event) -> Bool {
        a.name == b.name && Events.propsJSON(a.props) == Events.propsJSON(b.props)
    }

    var description: String { "\(name) \(Events.propsJSON(props))" }
}

/// Where the microphone was asked for: mic_permission's "where".
nonisolated enum MicAsked: String, CaseIterable, Sendable {
    case onboarding, game, settings

    var key: String { rawValue }
}

/// Where help was opened from: help_viewed's "source". Which topic is never sent.
nonisolated enum HelpSource: String, CaseIterable, Sendable {
    case tab, game, onboarding

    var key: String { rawValue }
}

/// How a purchase ended: purchase_result's "result".
nonisolated enum PurchaseResult: String, CaseIterable, Sendable {
    case purchased
    /// Waiting for a parent's OK (Ask to Buy) or the bank: the App Store says when it's bought.
    case pending
    case cancelled
    case failed
    /// The player had it already (Play says so; the App Store sells it again for nothing, as bought).
    case owned

    var key: String { rawValue }
}

/// How "Restore purchases" went: restore's "result" (`nothing` is the whitelist's "none": Optional has a .none).
nonisolated enum RestoreResult: String, CaseIterable, Sendable {
    case restored
    case nothing = "none"
    case failed

    var key: String { rawValue }
}

/**
 * Every event the app sends, each with only the details web/analytics/events.json lists for it: which game, node,
 * pack or product (the maps' and the catalog's ids), counts and times, yes or no, and a few fixed words. Never
 * anything the player says or types, no words of a story, no audio, nothing about VoiceOver or any setting, not which
 * help topic was read, nothing about the device but the coarse details in [About] (docs/DESIGN.md › Usage data's
 * never-sent list). This file is the whole list: EventsTests holds it to events.json, and finds every place in the app
 * that names an event. Android: analytics/Events.kt.
 */
nonisolated enum Events {
    // ----- The app (AppModel) -----

    /**
     * The app came on screen: [cold] the first time since it started; [first] with no random ID yet, so the first time
     * since it was installed (or since its usage data was deleted, or turned off and on).
     */
    static func appOpen(cold: Bool, first: Bool) -> Event {
        Event("app_open", ["cold": cold, "first": first])
    }

    /// The app went off screen (the home screen, another app, the phone locked) after [seconds] on it.
    static func appBackground(seconds: Int) -> Event {
        Event("app_background", ["seconds": seconds])
    }

    /// The intro ended: by itself, or [skipped].
    static func introFinished(skipped: Bool) -> Event {
        Event("intro_finished", ["skipped": skipped])
    }

    /// Onboarding ended: Start playing ([completed]), or Skip.
    static func onboardingFinished(completed: Bool) -> Event {
        Event("onboarding_finished", ["outcome": completed ? "completed" : "skipped"])
    }

    /// What the player said to iOS's microphone question (the mic and speech recognition), and where the app asked it.
    static func micPermission(granted: Bool, where asked: MicAsked) -> Event {
        Event("mic_permission", ["result": granted ? "granted" : "denied", "where": asked.key])
    }

    /// A tab shown.
    static func tabView(_ tab: AppTab) -> Event {
        Event("tab_view", ["tab": tab.key])
    }

    /// A help topic opened, from the Help tab or a game (never which one).
    static func helpViewed(_ source: HelpSource) -> Event {
        Event("help_viewed", ["source": source.key])
    }

    // ----- The games (GameController) -----

    /// A game opened: [resumed] where the player left it.
    static func gameOpen(_ game: String, resumed: Bool) -> Event {
        Event("game_open", ["game": game, "resumed": resumed])
    }

    /**
     * A game reached an end at [node]: a chapter's end, a game over, or one of its ends (the maps' "ending", which the
     * whitelist calls "end"; any other kind is an end too, as the end panel says "The end" for it).
     */
    static func gameEnd(_ game: String, kind: String, node: String) -> Event {
        Event("game_end", ["game": game, "kind": endKind(kind), "node": node])
    }

    /// Next chapter, to the chapter [next].
    static func chapterNext(_ game: String, next: String) -> Event {
        Event("chapter_next", ["game": game, "next": next])
    }

    /// The free part of a game is over: [pack] has what comes next.
    static func lockedEnd(_ game: String, pack: String) -> Event {
        Event("locked_end", ["game": game, "pack": pack])
    }

    /// Play again, Try again or Start again.
    static func gameRestart(_ game: String) -> Event {
        Event("game_restart", ["game": game])
    }

    /**
     * A game closed: where it was ([node]; none if it never got going), how many turns it played and for how long,
     * and how many answers were spoken, typed and tapped and how many questions went unanswered (counts only: never
     * an answer).
     */
    static func gameLeave(
        _ game: String, node: String?, turns: Int, seconds: Int, spoken: Int, typed: Int, tapped: Int, silences: Int
    ) -> Event {
        Event("game_leave", [
            "game": game, "node": node, "turns": turns, "seconds": seconds, "answers_voice": spoken,
            "answers_typed": typed, "answers_tapped": tapped, "silences": silences,
        ])
    }

    /// The game went wrong and stopped, at [node] (none if it went wrong as it opened).
    static func gameError(_ game: String, node: String?) -> Event {
        Event("game_error", ["game": game, "node": node])
    }

    // ----- The shop (AppModel, Store) -----

    /// The Shop tab, or a store sheet, opened [from] somewhere.
    static func shopView(_ source: ShopSource) -> Event {
        Event("shop_view", ["source": source.key])
    }

    /// Buy pressed, and the App Store's purchase sheet shown for [product].
    static func purchaseStart(_ product: String) -> Event {
        Event("purchase_start", ["product": product])
    }

    /// How a purchase of [product] ended.
    static func purchaseResult(_ product: String, _ result: PurchaseResult) -> Event {
        Event("purchase_result", ["product": product, "result": result.key])
    }

    /// "Restore purchases": how it went, and how many of the catalog's packs the Apple Account has bought.
    static func restore(_ result: RestoreResult, count: Int) -> Event {
        Event("restore", ["result": result.key, "count": count])
    }

    /// A pack's download: whether it installed, how long it took and how much came down.
    static func packDownload(_ pack: String, installed: Bool, seconds: Int, bytes: Int64) -> Event {
        Event("pack_download", [
            "pack": pack, "result": installed ? "installed" : "failed", "seconds": seconds, "bytes": bytes,
        ])
    }

    // ----- The whitelist -----

    /// An end's kind as the whitelist names it.
    static func endKind(_ kind: String) -> String {
        kind == "chapter" || kind == "gameover" ? kind : "end"
    }

    /// web/analytics/events.json's "common": the details every event has (see [Stamp]), and their types, in its order.
    static let common: [(name: String, type: String)] = [
        ("install_id", "uuid"),
        ("session_id", "uuid"),
        ("seq", "int"),
        ("ts", "iso8601"),
        ("app_version", "string"),
        ("build", "string"),
        ("platform", "enum:ios,android"),
        ("form_factor", "enum:phone,tablet,desktop,watch"),
        ("os_version", "string"),
        ("lang", "string"),
    ]

    /// web/analytics/events.json's "events": each event's details and their types, in its order. Nothing else is sent.
    static let allowed: [String: [(name: String, type: String)]] = [
        "app_open": [("cold", "bool"), ("first", "bool")],
        "app_background": [("seconds", "int")],
        "intro_finished": [("skipped", "bool")],
        "onboarding_finished": [("outcome", "enum:completed,skipped")],
        "mic_permission": [("result", "enum:granted,denied"), ("where", "enum:onboarding,game,settings")],
        "tab_view": [("tab", "enum:games,shop,help,settings")],
        "help_viewed": [("source", "enum:tab,game,onboarding")],
        "game_open": [("game", "id"), ("resumed", "bool")],
        "game_end": [("game", "id"), ("kind", "enum:chapter,gameover,end"), ("node", "id")],
        "chapter_next": [("game", "id"), ("next", "id")],
        "locked_end": [("game", "id"), ("pack", "id")],
        "game_restart": [("game", "id")],
        "game_leave": [
            ("game", "id"), ("node", "id"), ("turns", "int"), ("seconds", "int"), ("answers_voice", "int"),
            ("answers_typed", "int"), ("answers_tapped", "int"), ("silences", "int"),
        ],
        "game_error": [("game", "id"), ("node", "id")],
        "shop_view": [("source", "enum:tab,card,menu,locked_end")],
        "purchase_start": [("product", "id")],
        "purchase_result": [("product", "id"), ("result", "enum:purchased,pending,cancelled,failed,owned")],
        "restore": [("result", "enum:restored,none,failed"), ("count", "int")],
        "pack_download": [("pack", "id"), ("result", "enum:installed,failed"), ("seconds", "int"), ("bytes", "int")],
    ]

    /**
     * An id, as web/analytics/whitelist.js takes it: a game, node, pack or product id as the maps and the catalog have
     * them, capitals and a leading underscore included ("L1_win", "_restart"). [isId] checks it without a regex.
     */
    static let idPattern = "^[A-Za-z0-9_][A-Za-z0-9_.:-]{0,79}$"
    static let maxInt: Int64 = 1_000_000_000
    /// The longest "string" detail, in UTF-16 units (JavaScript's length, as the server counts it).
    static let maxString = 64

    /**
     * Why an event can't be sent, or nil if it can: an event or a detail the whitelist hasn't got, or a value that
     * isn't of the detail's type (the server would turn away the whole batch it came in).
     */
    static func problem(_ name: String, _ props: [String: any Sendable]) -> String? {
        guard let allowed = allowed[name] else { return "unknown event \"\(name)\"" }
        for (key, value) in props.sorted(by: { $0.key < $1.key }) {
            guard let type = allowed.first(where: { $0.name == key })?.type else {
                return "\(name) has no property \"\(key)\""
            }
            if !fits(type, value) { return "\(name).\(key) has the wrong type" }
        }
        return nil
    }

    /// Whether [value] is of the whitelist's [type], as web/analytics/whitelist.js checks it.
    static func fits(_ type: String, _ value: any Sendable) -> Bool {
        switch type {
        case "bool":
            return value is Bool
        case "int":
            guard let n = integer(value) else { return false }
            return n >= 0 && n <= maxInt
        case "id":
            return (value as? String).map(isId) ?? false
        case "uuid":
            return (value as? String).map(isUUID) ?? false
        case "iso8601":
            return (value as? String).map(isISO8601) ?? false
        case "string":
            guard let s = value as? String else { return false }
            return s.utf16.count <= maxString && s == text(s)
        default:
            guard type.hasPrefix("enum:"), let s = value as? String else { return false }
            return type.dropFirst("enum:".count).split(separator: ",").contains { $0 == s }
        }
    }

    /// A whole number (never a yes or no, which Swift keeps apart), as the server's "int" takes it.
    static func integer(_ value: any Sendable) -> Int64? {
        if value is Bool { return nil }
        if let n = value as? Int { return Int64(n) }
        if let n = value as? Int64 { return n }
        return nil
    }

    /// [idPattern]: a letter, digit or underscore, then up to 79 of those, dots, colons and hyphens.
    static func isId(_ s: String) -> Bool {
        let bytes = Array(s.utf8)
        guard let first = bytes.first, bytes.count <= 80, word(first) else { return false }
        let marks: Set<UInt8> = [UInt8(ascii: "."), UInt8(ascii: ":"), UInt8(ascii: "-")]
        return bytes.dropFirst().allSatisfy { word($0) || marks.contains($0) }
    }

    /// A UUID as the server takes one: 8-4-4-4-12 hex digits, in either case.
    static func isUUID(_ s: String) -> Bool {
        let parts = s.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.map(\.utf8.count) == [8, 4, 4, 4, 12] else { return false }
        return parts.allSatisfy { $0.utf8.allSatisfy(isHex) }
    }

    /// "2026-10-09T09:41:00.123Z", or with an offset ("+01:00"): the shape whitelist.js's ISO8601 has.
    static func isISO8601(_ s: String) -> Bool {
        let b = Array(s.utf8)
        func digits(_ range: Range<Int>) -> Bool { range.upperBound <= b.count && b[range].allSatisfy(isDigit) }
        func at(_ i: Int, _ c: Character) -> Bool { i < b.count && b[i] == c.asciiValue }
        guard digits(0..<4), at(4, "-"), digits(5..<7), at(7, "-"), digits(8..<10), at(10, "T"), digits(11..<13),
              at(13, ":"), digits(14..<16), at(16, ":"), digits(17..<19) else { return false }
        var i = 19
        if at(i, ".") {
            var n = 0
            i += 1
            while i < b.count && isDigit(b[i]) {
                n += 1
                i += 1
            }
            guard (1...9).contains(n) else { return false }
        }
        if at(i, "Z") { return i + 1 == b.count }
        guard at(i, "+") || at(i, "-") else { return false }
        return digits(i + 1..<i + 3) && at(i + 3, ":") && digits(i + 4..<i + 6) && i + 6 == b.count
    }

    /**
     * An event as the server takes it: one JSON object with its name, its details, and the [stamp]'s common ones.
     * A common detail that's empty, or isn't of its type, is left out (every one but the ID, the session and the
     * number may be), so it can never cost the batch.
     */
    static func json(_ event: Event, _ stamp: Stamp) -> String {
        var fields = [
            "\"name\":" + quoted(event.name),
            "\"props\":" + propsJSON(event.props, order: allowed[event.name]?.map(\.name) ?? []),
            "\"install_id\":" + quoted(stamp.installId),
            "\"session_id\":" + quoted(stamp.sessionId),
            "\"seq\":" + String(stamp.seq),
        ]
        if let ts = iso(stamp.at) { fields.append("\"ts\":" + quoted(ts)) }
        let about: [(String, String)] = [
            ("app_version", text(stamp.about.appVersion)),
            ("build", text(stamp.about.build)),
            ("platform", "ios"),
            ("form_factor", stamp.about.formFactor),
            ("os_version", text(stamp.about.osVersion)),
            ("lang", text(stamp.about.lang)),
        ]
        for (key, value) in about {
            guard !value.isEmpty, let type = common.first(where: { $0.name == key })?.type, fits(type, value) else {
                continue
            }
            fields.append(quoted(key) + ":" + quoted(value))
        }
        return "{" + fields.joined(separator: ",") + "}"
    }

    /// An event's details as a JSON object: those named in [order] first, in that order, then any others by name.
    static func propsJSON(_ props: [String: any Sendable], order: [String] = []) -> String {
        let keys = order.filter { props[$0] != nil } + props.keys.filter { !order.contains($0) }.sorted()
        let fields = keys.compactMap { key in props[key].flatMap(value).map { quoted(key) + ":" + $0 } }
        return "{" + fields.joined(separator: ",") + "}"
    }

    /// A detail as JSON: true or false, a whole number, or text. Nil for anything else, which is never sent.
    static func value(_ value: any Sendable) -> String? {
        if let flag = value as? Bool { return flag ? "true" : "false" }
        if let n = integer(value) { return String(n) }
        if let s = value as? String { return quoted(s) }
        return nil
    }

    /// [s] as a JSON string: quoted, with quotes, backslashes and control characters escaped.
    static func quoted(_ s: String) -> String {
        var out = "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if u.value < 0x20 {
                    let hex = String(u.value, radix: 16)
                    out += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
                } else {
                    out.unicodeScalars.append(u)
                }
            }
        }
        return out + "\""
    }

    /// A time as the server takes it, UTC to the millisecond ("2026-10-09T09:41:00.123Z"); none outside 1970–2999.
    static func iso(_ date: Date) -> String? {
        let ms = (date.timeIntervalSince1970 * 1000).rounded()
        guard ms.isFinite, ms >= 0, ms < Double(year3000) else { return nil }
        let total = Int64(ms)
        let (year, month, day) = civil(days: total / 86_400_000)
        let inDay = total % 86_400_000
        return pad(year, 4) + "-" + pad(month, 2) + "-" + pad(day, 2) + "T" + pad(inDay / 3_600_000, 2) + ":"
            + pad(inDay / 60_000 % 60, 2) + ":" + pad(inDay / 1000 % 60, 2) + "." + pad(inDay % 1000, 3) + "Z"
    }

    /// Text from the device (its iOS version, language) as a "string" detail: no control characters, at most 64
    /// UTF-16 units, cut between characters' code points.
    static func text(_ value: String) -> String {
        var out = String.UnicodeScalarView()
        var units = 0
        for u in value.unicodeScalars where u.value >= 0x20 && u.value != 0x7F {
            let width = UTF16.width(u)
            if units + width > maxString { break }
            out.append(u)
            units += width
        }
        return String(out)
    }

    /// 3000-01-01T00:00:00Z, in milliseconds since 1970: the server takes times before it.
    private static let year3000: Int64 = 32_503_680_000_000

    /// The date [days] after 1970-01-01 (proleptic Gregorian; Howard Hinnant's civil_from_days).
    private static func civil(days: Int64) -> (Int64, Int64, Int64) {
        let z = days + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let day = doy - (153 * mp + 2) / 5 + 1
        let month = mp < 10 ? mp + 3 : mp - 9
        return (yoe + era * 400 + (month <= 2 ? 1 : 0), month, day)
    }

    private static func pad(_ n: Int64, _ width: Int) -> String {
        let s = String(n)
        return String(repeating: "0", count: max(0, width - s.count)) + s
    }

    /// A letter or digit of ASCII's, or an underscore.
    private static func word(_ b: UInt8) -> Bool {
        isDigit(b) || (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(b)
            || (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(b) || b == UInt8(ascii: "_")
    }

    private static func isDigit(_ b: UInt8) -> Bool { (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(b) }

    private static func isHex(_ b: UInt8) -> Bool {
        isDigit(b) || (UInt8(ascii: "a")...UInt8(ascii: "f")).contains(b)
            || (UInt8(ascii: "A")...UInt8(ascii: "F")).contains(b)
    }
}

/**
 * The details every event has (events.json's "common"), besides its own: the random ID, the session and the event's
 * number in it (never used twice in a session: the server keeps an event that comes twice once), when it happened,
 * and what the app runs on.
 */
nonisolated struct Stamp: Sendable {
    let installId: String
    let sessionId: String
    let seq: Int
    let at: Date
    let about: About
}

/**
 * What the app runs on, coarsely: its version and build, iOS's version, the player's language, and the kind of device
 * (phone, tablet, desktop or watch; never its make or model).
 */
nonisolated struct About: Sendable, Equatable {
    let appVersion: String
    let build: String
    let osVersion: String
    let lang: String
    let formFactor: String

    /**
     * The kind of device, as events.json's form_factor has it (docs/DESIGN.md › Tablets…): the iPad app on a Mac is a
     * desktop; an iPad (and the iPad app on Apple Vision Pro, which iOS calls an iPad) a tablet; else a phone.
     * Android: Events.kt's formFactor.
     */
    static func formFactor(pad: Bool, mac: Bool) -> String {
        if mac { return "desktop" }
        return pad ? "tablet" : "phone"
    }
}
