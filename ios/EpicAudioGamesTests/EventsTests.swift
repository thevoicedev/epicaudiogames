// analytics/EventsTest.kt: what the app can send as usage data, against the server's whitelist.

import Foundation
import Testing
@testable import EpicAudioGames

/**
 * What the app can send as usage data, against the server's whitelist (web/analytics/events.json and the id pattern in
 * web/analytics/whitelist.js; docs/DESIGN.md › Usage data): the app's copy of it is the file's; every event it makes
 * is one the server takes, and every one in the file is made somewhere; every place in the app that names an event
 * names one of the file's, with its details; and nothing about accessibility, nothing the player says or types, and
 * no audio can ride along in any event. Android: EventsTest.kt.
 */
@MainActor
struct EventsTests {
    @Test func theAppsWhitelistIsTheServers() throws {
        let w = try Whitelist.load()
        #expect(Dictionary(uniqueKeysWithValues: Events.common.map { ($0.name, $0.type) }) == w.common)
        let ours = Events.allowed.mapValues { Dictionary(uniqueKeysWithValues: $0.map { ($0.name, $0.type) }) }
        #expect(ours == w.events)
        // The same ids: the maps' own (capitals, a leading underscore), as the server takes them.
        #expect(Events.idPattern == w.idPattern)
        for id in ["noodle-rush", "L1_win", "L2_intro", "Page1", "_restart", "ac-diffGame", "CHOOSE_COUNTRY"] {
            #expect(Events.fits("id", id), "\(id)")
        }
        // The app's own check of an id (no regex) says what the pattern says.
        let samples = [
            "", "a", "_", "9", "-a", ".a", ":a", "a-b.c:d_e", "a b", "a/b", "a\n", "a\u{0}", "é", "Üna", "L1_win",
            String(repeating: "x", count: 80), String(repeating: "x", count: 81), "fr-53", "nr-start", "x!",
        ]
        for s in samples {
            #expect(Events.isId(s) == Whitelist.matches(w.idPattern, s), "\(s.debugDescription)")
        }
    }

    @Test func everyEventTheAppMakesIsOneTheServerTakes() throws {
        let w = try Whitelist.load()
        let made = everyEvent()
        for e in made {
            #expect(Events.problem(e.name, e.props) == nil, "\(e)")
            let json = try sent(e)
            #expect(w.problem(json) == nil, "\(e)")
        }
        // And every event in the whitelist is one the app makes.
        #expect(Set(w.events.keys) == Set(made.map(\.name)))
    }

    @Test func theMapsEndsAreTheWhitelistsKinds() {
        #expect(Events.endKind("chapter") == "chapter")
        #expect(Events.endKind("gameover") == "gameover")
        // The maps' and Nuclear War's last ends are "ending"; the whitelist (and the reports) call them "end".
        #expect(Events.endKind("ending") == "end")
        #expect(Events.endKind("something new") == "end")
    }

    @Test func everyPlaceTheAppNamesAnEventIsInTheWhitelist() throws {
        let w = try Whitelist.load()
        let app = Whitelist.repo.appendingPathComponent("ios/EpicAudioGames", isDirectory: true)
        let sources = swiftFiles(app)
        #expect(sources.count > 20, "no sources found under \(app.path)")
        var named: [String: Set<String>] = [:]
        for file in sources {
            let text = try String(contentsOf: file, encoding: .utf8)
            // An event made by name: Event("name", …), and any name handed straight to track, onEvent or event…
            for call in calls(text) {
                // …with its details in that call: "key": value.
                named[call.name, default: []].formUnion(Self.groups(#""([A-Za-z_]+)":\s"#, in: call.text))
            }
        }
        for (name, props) in named {
            let allowed = try #require(w.events[name], "the app names \"\(name)\", which isn't in events.json")
            let others = props.subtracting(allowed.keys)
            #expect(others.isEmpty, "\(name): \(others.sorted()) aren't in events.json")
        }
        #expect(Set(named.keys) == Set(w.events.keys), "events made by name")

        // Every one of Events' makers is used in the app, outside Events.swift: every event is wired.
        let events = try #require(sources.first { $0.lastPathComponent == "Events.swift" })
        let text = try String(contentsOf: events, encoding: .utf8)
        let section = try #require(text.components(separatedBy: "// ----- The whitelist").first)
        let makers = Self.groups(#"\n    static func ([a-z][A-Za-z]+)\("#, in: section)
        #expect(makers.count == 19)
        let elsewhere = try sources.filter { $0.lastPathComponent != "Events.swift" }
            .map { try String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
        for maker in makers.sorted() {
            #expect(elsewhere.contains("Events.\(maker)("), "Events.\(maker) isn't used")
        }
    }

    @Test func noEventCanCarryAnythingAboutAccessibilityWordsOrAudio() throws {
        // What's never sent (docs/DESIGN.md › Usage data), as words a detail's name could have.
        let never: Set<String> = [
            "screen", "reader", "talkback", "voiceover", "accessibility", "a11y", "theme", "contrast", "font", "text",
            "size", "scale", "bold", "motion", "speed", "volume", "haptics", "policy", "highlight", "caption", "said",
            "say", "words", "transcript", "utterance", "reply", "typed_text", "partial", "guess", "audio", "recording",
            "speech", "clip", "topic", "model", "device", "manufacturer", "brand", "advertising", "idfa", "location",
            "latitude", "longitude", "ip", "email", "name",
        ]
        // …and every setting there is, by its key, as it is and in snake case (a new setting is covered by itself).
        let settings = AppSettings.Key.allCases.map { String($0.rawValue.dropFirst("settings.".count)) }
        #expect(settings.count >= 18)
        let settingNames = Set(settings.flatMap { [$0.lowercased(), Self.snake($0)] })
        let w = try Whitelist.load()
        let ours = Events.allowed.mapValues { Dictionary(uniqueKeysWithValues: $0.map { ($0.name, $0.type) }) }
        for allowed in [w.events, ours] {
            for (event, props) in allowed {
                for (prop, type) in props {
                    #expect(!settingNames.contains(prop.lowercased()), "\(event).\(prop) names a setting")
                    let words = prop.lowercased().split(separator: "_").map(String.init)
                    #expect(words.allSatisfy { !never.contains($0) }, "\(event).\(prop)")
                    // A detail is a count, yes or no, one of a few words, or an id: never free text.
                    #expect(type != "string", "\(event).\(prop) is free text")
                }
            }
        }
        // And whatever the app's code asked, the whitelist keeps such details out.
        let forbidden: [String: any Sendable] = [
            "screen_reader": true, "voiceover": true, "theme": "contrast", "text_scale": 1.3, "voice_speed": 2,
            "music_volume": 0, "answer_time": "longest", "mic_auto": "never", "said": "yes please",
            "text": "Gribbo: who goes there?", "audio": "scenes/q1", "topic": "voice", "model": "iPhone17,1",
        ]
        for (event, props) in Events.allowed {
            var good: [String: any Sendable] = [:]
            for (name, type) in props { good[name] = Self.sample(type) }
            #expect(Events.problem(event, good) == nil, "\(event)")
            for (key, value) in forbidden {
                var bad = good
                bad[key] = value
                #expect(Events.problem(event, bad) != nil, "\(event) + \(key)")
            }
        }
        // Words in an id's place (an answer passed off as a node) aren't an id; nor is a yes for a count.
        for words in ["yes please", "Who goes there?", "I'd like the cake", "", String(repeating: "x", count: 81)] {
            let end: [String: any Sendable] = ["game": "noodle-rush", "kind": "end", "node": words]
            #expect(Events.problem("game_end", end) != nil, "\(words)")
        }
        #expect(Events.problem("app_background", ["seconds": true]) != nil)
        #expect(Events.problem("app_open", ["cold": 1]) != nil)
        #expect(Events.problem("app_background", ["seconds": -1]) != nil)
        #expect(Events.problem("app_background", ["seconds": 1_000_000_001]) != nil)
        #expect(Events.problem("tab_view", ["tab": "Games"]) != nil)
    }

    @Test func anEventAsSentIsWhatTheServerTakes() throws {
        let w = try Whitelist.load()
        let stamp = Stamp(
            installId: "4b0c8a8e-4f3d-4c6e-9a51-3b8a7f0f2d10", sessionId: "9d7e1c32-0a4b-4f53-8c6d-1e2f3a4b5c6d",
            seq: 7, at: Date(timeIntervalSince1970: 1_791_538_860.123),
            about: About(appVersion: "1.0", build: "3", osVersion: "18.1", lang: "en-GB", formFactor: "tablet"))
        let json = Events.json(Events.gameOpen("noodle-rush", resumed: true), stamp)
        let sent = try JSONValue.parse(json)
        #expect(w.problem(sent) == nil)
        guard case .object(let fields) = sent else { throw Trouble("not an object: \(json)") }
        #expect(Set(fields.keys) == [
            "name", "props", "install_id", "session_id", "seq", "ts", "app_version", "build", "platform",
            "form_factor", "os_version", "lang",
        ])
        #expect(sent["ts"]?.text == "2026-10-09T09:41:00.123Z")
        #expect(sent["platform"]?.text == "ios")
        #expect(sent["form_factor"]?.text == "tablet")
        #expect(sent["seq"] == .int(7))
        #expect(json.contains(#""props":{"game":"noodle-rush","resumed":true}"#), "\(json)")
        // One line: the queue keeps an event a line.
        #expect(!json.contains("\n"))

        // What the device says about itself is cleaned, or left out, rather than costing the batch.
        let odd = Stamp(
            installId: stamp.installId, sessionId: stamp.sessionId, seq: 0, at: Date(timeIntervalSince1970: -1),
            about: About(
                appVersion: "1.0", build: "3", osVersion: "16\u{0}beta", lang: String(repeating: "x", count: 100),
                formFactor: "foldable"))
        let cleaned = try JSONValue.parse(Events.json(Events.gameRestart("frootopia"), odd))
        #expect(w.problem(cleaned) == nil)
        #expect(cleaned["ts"] == nil)
        #expect(cleaned["form_factor"] == nil)
        #expect(cleaned["os_version"]?.text == "16beta")
        #expect(cleaned["lang"]?.text?.count == 64)
    }

    @Test func theKindOfDeviceIsCoarse() throws {
        #expect(About.formFactor(pad: false, mac: false) == "phone")
        #expect(About.formFactor(pad: true, mac: false) == "tablet")
        // The iPad app on a Mac ("Designed for iPad") says it's an iPad: it's a desktop.
        #expect(About.formFactor(pad: true, mac: true) == "desktop")
        let type = try #require(Events.common.first { $0.name == "form_factor" }?.type)
        for kind in ["phone", "tablet", "desktop", "watch"] {
            #expect(Events.fits(type, kind))
        }
        // This device, as the app reads it: iOS's version and a kind of device, and never a make or a model.
        let about = About.app()
        #expect(["phone", "tablet", "desktop"].contains(about.formFactor))
        #expect(!about.osVersion.isEmpty)
    }

    @Test func whereUsageDataGoes() {
        func release(_ argument: String?, testing: Bool = false) -> String? {
            UsageData.server(debug: false, argument: argument, testing: testing)
        }
        func debug(_ argument: String?, testing: Bool = false) -> String? {
            UsageData.server(debug: true, argument: argument, testing: testing)
        }
        // A release build: our server (never one from the launch), unless it's the unit tests' host or told "off".
        #expect(release(nil) == UsageData.ourServer)
        #expect(UsageData.ourServer == "https://epicaudiogames.com")
        #expect(release("http://evil.example") == UsageData.ourServer)
        #expect(release(nil, testing: true) == nil)
        #expect(release("off") == nil)
        // A Debug build: nowhere, unless it's given a server as it's launched.
        #expect(debug(nil) == nil)
        #expect(debug("http://127.0.0.1:3000") == "http://127.0.0.1:3000")
        #expect(debug("http://localhost:3000/api/events") == "http://localhost:3000")
        #expect(debug("https://epicaudiogames.com/") == "https://epicaudiogames.com")
        #expect(debug("OFF") == nil)
        #expect(debug("127.0.0.1:3000") == nil)
        #expect(debug("http://127.0.0.1:3000", testing: true) == nil)
    }

    @Test func timesIdsAndTextAreAsTheServerReadsThem() throws {
        #expect(Events.iso(Date(timeIntervalSince1970: 0)) == "1970-01-01T00:00:00.000Z")
        #expect(Events.iso(Date(timeIntervalSince1970: 1_791_538_860.123)) == "2026-10-09T09:41:00.123Z")
        #expect(Events.iso(Date(timeIntervalSince1970: 1_709_164_800)) == "2024-02-29T00:00:00.000Z")   // a leap day
        #expect(Events.iso(Date(timeIntervalSince1970: 32_503_679_999.999)) == "2999-12-31T23:59:59.999Z")
        #expect(Events.iso(Date(timeIntervalSince1970: 32_503_680_000)) == nil)
        #expect(Events.iso(Date(timeIntervalSince1970: -1)) == nil)
        let w = try Whitelist.load()
        let now = try #require(Events.iso(Date()))
        #expect(w.fits("iso8601", .string(now)))
        #expect(Events.isISO8601(now))
        #expect(Events.isISO8601("2026-10-09T10:41:00+01:00"))
        #expect(Events.isISO8601("2026-10-09T09:41:00Z"))
        #expect(!Events.isISO8601("2026-10-09 09:41:00Z"))
        #expect(!Events.isISO8601("2026-10-09T09:41:00.Z"))
        #expect(!Events.isISO8601("2026-10-09T09:41:00.123"))
        #expect(Events.isUUID("4B0C8A8E-4F3D-4C6E-9A51-3B8A7F0F2D10"))
        #expect(!Events.isUUID("4b0c8a8e4f3d4c6e9a513b8a7f0f2d10"))
        #expect(!Events.isUUID("4b0c8a8e-4f3d-4c6e-9a51-3b8a7f0f2d1g"))
        // Text from the device: no control characters, at most 64 UTF-16 units, and never half a character.
        #expect(Events.text("15\u{7}.1") == "15.1")
        #expect(Events.text(String(repeating: "é", count: 70)).utf16.count == 64)
        #expect(Events.text(String(repeating: "😀", count: 40)).utf16.count == 64)
        #expect(Events.text("a" + String(repeating: "😀", count: 40)).utf16.count == 63)
        // JSON strings: quotes, backslashes and control characters escaped.
        #expect(Events.quoted("a\"b\\c\nd\u{1}") == #""a\"b\\c\nd\u0001""#)
        #expect(try JSONValue.parse(Events.quoted("a\"b\\c\nd\u{1}é")) == .string("a\"b\\c\nd\u{1}é"))
    }

    // ----- Helpers -----

    /// Every event the app can make: each maker with every one of its choices.
    private func everyEvent() -> [Event] {
        var all: [Event] = []
        for cold in [true, false] {
            for first in [true, false] { all.append(Events.appOpen(cold: cold, first: first)) }
        }
        all += [Events.appBackground(seconds: 0), Events.appBackground(seconds: 86_400)]
        all += [Events.introFinished(skipped: true), Events.introFinished(skipped: false)]
        all += [Events.onboardingFinished(completed: true), Events.onboardingFinished(completed: false)]
        for asked in MicAsked.allCases {
            for granted in [true, false] { all.append(Events.micPermission(granted: granted, where: asked)) }
        }
        all += AppTab.allCases.map { Events.tabView($0) }
        all += HelpSource.allCases.map { Events.helpViewed($0) }
        all += [Events.gameOpen("alien-customs", resumed: true), Events.gameOpen("nuclear-war", resumed: false)]
        for kind in ["chapter", "gameover", "ending"] {
            all.append(Events.gameEnd("alien-customs", kind: kind, node: "L1_win"))
        }
        all.append(Events.chapterNext("alien-customs", next: "L2_intro"))
        all.append(Events.lockedEnd("the-werewolf", pack: "the-werewolf-stories"))
        all.append(Events.gameRestart("frootopia"))
        all.append(Events.gameLeave(
            "noodle-rush", node: "Page1", turns: 14, seconds: 312, spoken: 9, typed: 3, tapped: 2, silences: 1))
        all.append(Events.gameLeave(
            "noodle-rush", node: nil, turns: 0, seconds: 0, spoken: 0, typed: 0, tapped: 0, silences: 0))
        all += [Events.gameError("frootopia", node: "_restart"), Events.gameError("frootopia", node: nil)]
        all += ShopSource.allCases.map { Events.shopView($0) }
        all.append(Events.purchaseStart("alien_customs_levels"))
        all += PurchaseResult.allCases.map { Events.purchaseResult("frootopia_stories", $0) }
        all += RestoreResult.allCases.map { Events.restore($0, count: 2) }
        all.append(Events.packDownload("alien-customs-levels", installed: true, seconds: 41, bytes: 26_214_400))
        all.append(Events.packDownload("the-werewolf-stories", installed: false, seconds: 3, bytes: 0))
        return all
    }

    /// An event as the app sends it.
    private func sent(_ e: Event) throws -> JSONValue {
        let stamp = Stamp(
            installId: "00000000-0000-4000-8000-0000000000aa", sessionId: "00000000-0000-4000-8000-0000000000bb",
            seq: 0, at: Date(timeIntervalSince1970: 1_791_538_860),
            about: About(appVersion: "1.0", build: "3", osVersion: "18.1", lang: "en-GB", formFactor: "phone"))
        return try JSONValue.parse(Events.json(e, stamp))
    }

    /// A value of a whitelist type.
    private static func sample(_ type: String) -> any Sendable {
        switch type {
        case "bool": return true
        case "int": return 1
        case "id": return "noodle-rush"
        default:
            if type.hasPrefix("enum:") {
                return String(type.dropFirst("enum:".count).split(separator: ",")[0])
            }
            return "x"
        }
    }

    /// "voiceSpeed" as "voice_speed".
    private static func snake(_ name: String) -> String {
        var out = ""
        for c in name {
            if c.isUppercase, !out.isEmpty { out += "_" }
            out += c.lowercased()
        }
        return out
    }

    /// The Swift files in [dir], and in its folders.
    private func swiftFiles(_ dir: URL) -> [URL] {
        guard let all = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil) else { return [] }
        var found: [URL] = []
        while let url = all.nextObject() as? URL {
            if url.pathExtension == "swift" { found.append(url) }
        }
        return found.sorted { $0.path < $1.path }
    }

    /// A call found in the source: the event it names, and its text up to its closing bracket.
    private struct Call {
        let name: String
        let text: String
    }

    /// Every call that names an event (its first argument a string), with the text of its arguments.
    private func calls(_ text: String) -> [Call] {
        guard let regex = try? NSRegularExpression(pattern: #"\b(Event|track|onEvent|event)\(\s*"([^"]+)""#) else {
            return []
        }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let call = Range(match.range, in: text), let name = Range(match.range(at: 2), in: text),
                  let open = text[call].firstIndex(of: "(") else { return nil }
            var depth = 0
            var end = open
            for i in text[open...].indices {
                if text[i] == "(" { depth += 1 }
                if text[i] == ")" { depth -= 1 }
                if depth == 0 {
                    end = i
                    break
                }
            }
            return Call(name: String(text[name]), text: String(text[open...end]))
        }
    }

    /// The first group of every match of [pattern] in [text].
    private static func groups(_ pattern: String, in text: String) -> Set<String> {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return Set(regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            Range(match.range(at: 1), in: text).map { String(text[$0]) }
        })
    }
}
