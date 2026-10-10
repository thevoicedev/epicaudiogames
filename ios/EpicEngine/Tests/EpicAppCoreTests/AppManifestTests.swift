// AppManifest.swift: the app's help and sounds as iOS reads them, from the real content/app/app.json.

import Foundation
import Testing

@testable import EpicAppCore

/**
 * The app's help and sounds as iOS reads them ([AppManifest]): the real content/app/app.json (tools/app_audio.py's),
 * with this app's pages only, each paragraph read by its clip and every file it plays in the folder; and the rules for
 * what's kept, on small made-up manifests. Android's AppManifestTest.kt.
 */
struct AppManifestTests {
    let folder: URL
    let data: Data
    let manifest: AppManifest

    init() throws {
        folder = try AppTestRepo.appContent()
        data = try Data(contentsOf: folder.appendingPathComponent("app.json"))
        manifest = try AppManifest.parse(data)
    }

    @Test func theRealManifestHasTheIPhonesPagesInItsOrder() throws {
        // What the file has for iOS: pages for no platform, and iOS's own, in the file's order.
        let raw = try (JSONParser.parse(data)["help"]?.arrayValue ?? []).map { try $0.jsonObject() }
        let ours = raw.filter { Self.platform($0) == nil || Self.platform($0) == "ios" }
            .compactMap { $0["id"]?.content }
        #expect(manifest.help.map(\.id) == ours)
        #expect(Set(ours).count == ours.count, "a page twice")
        #expect(manifest.help.count >= 9, "no help pages")
        // A page with a version for each app is iOS's here.
        let iPhones = raw.filter { Self.platform($0) == "ios" }
        #expect(!iPhones.isEmpty)
        for page in iPhones {
            let id = try #require(page["id"]?.content)
            let kept = try #require(manifest.topic(id))
            #expect(kept.title == page["title"]?.content, "\(id)")
            #expect(kept.text == (page["text"]?.arrayValue ?? []).compactMap(\.content), "\(id)")
        }
        // The screen reader's page is VoiceOver's, not TalkBack's.
        let screenReader = try #require(manifest.topic("screen-reader"))
        #expect(screenReader.title.contains("VoiceOver"), "\(screenReader.title)")
        #expect(manifest.topic("no-such-topic") == nil)
    }

    @Test func theWelcomeAndTheStingAreThere() throws {
        let welcome = try #require(manifest.welcome)
        #expect(welcome.id == "welcome")
        #expect(!welcome.text.isEmpty)
        #expect(welcome.hasClips)
        // It plays the listening sound as an example: a clip with no words.
        let example = welcome.steps.contains { step in
            guard case .play(let clip) = step else { return false }
            return clip.sfx && clip.path.hasPrefix("earcons/")
        }
        #expect(example)
        if let sting = manifest.sting {
            let file = folder.appendingPathComponent(sting.file)
            #expect(FileManager.default.fileExists(atPath: file.path), "\(sting.file) is missing")
            #expect((2.5...3.8).contains(sting.seconds), "\(sting.seconds)")
            #expect(sting.voiceAt < sting.voiceEnd && sting.voiceEnd < sting.seconds)
        }
    }

    /// The listening sounds and the success sound: one for each AppCue, as long as its file is.
    @Test func theEarconsLengthsAreTheirFiles() throws {
        #expect(Set(manifest.earcons.keys) == Set(AppCue.allCases.map(\.rawValue)))
        for cue in AppCue.allCases {
            let wav = try Data(contentsOf: folder.appendingPathComponent("earcons/\(cue.rawValue).wav"))
            let seconds = try #require(Self.wavSeconds(wav), "\(cue.rawValue).wav isn't 16-bit mono PCM")
            let listed = try #require(manifest.earcons[cue.rawValue])
            #expect(abs(seconds - listed) < 0.001, "\(cue.rawValue): \(seconds) s, app.json says \(listed)")
        }
    }

    @Test func everyParagraphIsReadByItsClipAndEveryClipIsInTheFolder() throws {
        let pages = (manifest.welcome.map { [$0] } ?? []) + manifest.help
        for page in pages {
            let clips = page.steps.compactMap { step -> Clip? in
                guard case .play(let clip) = step else { return nil }
                return clip
            }
            #expect(clips.count == page.clipParagraph.count, "\(page.id): a paragraph for each clip")
            // Each paragraph shown has the one clip that reads it, in order.
            #expect(page.clipParagraph.filter { $0 >= 0 } == Array(page.text.indices), "\(page.id)")
            for (i, clip) in clips.enumerated() {
                let file = folder.appendingPathComponent(clip.path + ".m4a")
                #expect(FileManager.default.fileExists(atPath: file.path),
                        "\(page.id): \(clip.path) isn't in content/app")
                guard i < page.clipParagraph.count else { continue }
                let paragraph = page.clipParagraph[i]
                if paragraph < 0 {
                    // An earcon, as an example: no words.
                    #expect(clip.sfx, "\(page.id): \(clip.path)")
                    #expect(clip.lines.isEmpty, "\(page.id): \(clip.path)")
                    continue
                }
                guard paragraph < page.text.count else {
                    Issue.record("\(page.id): clip \(i) reads paragraph \(paragraph) of \(page.text.count)")
                    continue
                }
                // The words shown are the words spoken.
                #expect(page.text[paragraph] == clip.lines.map(\.text).joined(separator: " "), "\(page.id)")
                for line in clip.lines {
                    guard let words = line.words else { continue }
                    let count = line.text.split(whereSeparator: \.isWhitespace).count
                    #expect(words.count == count, "\(page.id): a time for each word")
                    #expect(words == words.sorted(), "\(page.id): word times out of order")
                }
            }
            for link in page.links {
                #expect(!link.label.trimmingCharacters(in: .whitespaces).isEmpty, "\(page.id)")
                #expect(link.url.hasPrefix("https://") || link.url.hasPrefix("mailto:"), "\(link.url)")
            }
        }
    }

    @Test func pagesForTheOtherAppAreLeftOut() throws {
        let m = try AppManifest.parse("""
            {"format": 1, "earcons": {},
             "welcome": {"title": "Welcome", "text": ["Hi."], "clipParagraph": [], "steps": []},
             "help": [
              {"id": "a", "title": "Both", "text": [], "clipParagraph": [], "steps": []},
              {"id": "b", "platform": "ios", "title": "iPhone", "text": [], "clipParagraph": [], "steps": []},
              {"id": "b", "platform": "android", "title": "Android", "text": [], "clipParagraph": [], "steps": []},
              {"id": "c", "platform": "watch", "title": "Elsewhere", "text": [], "clipParagraph": [], "steps": []}
             ]}
            """)
        #expect(m.help.map(\.id) == ["a", "b"])
        #expect(m.help.map(\.title) == ["Both", "iPhone"])
        // No sting picked yet: the intro goes without one.
        #expect(m.sting == nil)
        #expect(m.help.first?.summary == "")
        #expect(m.welcome?.hasClips == false)
        // The same file, as Android reads it.
        let android = try AppManifest.parse("""
            {"help": [{"id": "a", "title": "Both"}, {"id": "b", "platform": "ios", "title": "iPhone"},
               {"id": "b", "platform": "android", "title": "Android"}]}
            """, platform: "android")
        #expect(android.help.map(\.title) == ["Both", "Android"])
    }

    @Test func stepsAreReadAsTheMapsHaveThem() throws {
        let m = try AppManifest.parse("""
            {"help": [{"id": "x", "title": "X", "text": ["One two."], "clipParagraph": [0, -1],
              "steps": [
               {"bed": "music/soft", "volume": 0.25, "dur": 4},
               {"play": "tts/one-two", "dur": 1.5,
                "lines": [{"at": 0, "len": 1.4, "who": "HOST", "text": "One two.", "w": [0, 0.5]}]},
               {"pause": 0.3},
               {"play": "earcons/listen-start-demo", "dur": 0.145, "lines": [], "sfx": true},
               {"say": "a kind of step this app doesn't know"}
              ]}]}
            """)
        let page = try #require(m.topic("x"))
        #expect(page.steps.count == 4)
        #expect(page.steps.first == .bed(path: "music/soft", volume: 0.25, dur: 4))
        guard page.steps.count == 4, case .play(let clip) = page.steps[1], case .play(let earcon) = page.steps[3] else {
            Issue.record("not the steps written: \(page.steps)")
            return
        }
        #expect(clip.path == "tts/one-two")
        #expect(clip.lines.first?.words == [0, 0.5])
        #expect(page.steps[2] == .pause(0.3))
        #expect(earcon.sfx)
        #expect(page.clipLines == [clip.lines, []])
        // A page without its title can't be read.
        #expect(throws: AppManifestError.self) { try AppManifest.parse(#"{"help": [{"id": "x"}]}"#) }
    }

    /// A help page's platform, if it says one.
    private static func platform(_ page: JSONObject) -> String? {
        if case .string(let p) = page["platform"] { return p }
        return nil
    }

    /**
     * A WAV of 16-bit PCM in one channel: its length in seconds, the RIFF chunks walked as Earcons.kt's Wav walks them
     * (any that aren't the format or the sound let go); nil for anything else.
     */
    static func wavSeconds(_ data: Data) -> Double? {
        let b = [UInt8](data)
        func tag(_ at: Int) -> String { String(decoding: b[at..<at + 4], as: UTF8.self) }
        func u16(_ at: Int) -> Int { Int(b[at]) | Int(b[at + 1]) << 8 }
        func u32(_ at: Int) -> Int { u16(at) | u16(at + 2) << 16 }
        guard b.count >= 12, tag(0) == "RIFF", tag(8) == "WAVE" else { return nil }
        var rate = 0
        var at = 12
        while at + 8 <= b.count {
            let size = u32(at + 4)
            let body = at + 8
            switch tag(at) {
            case "fmt ":
                guard body + 16 <= b.count, u16(body) == 1, u16(body + 2) == 1, u16(body + 14) == 16 else { return nil }
                rate = u32(body + 4)
            case "data":
                guard rate > 0 else { return nil }
                return Double(min(size, b.count - body) / 2) / Double(rate)
            default:
                break
            }
            // Chunks are padded to an even length.
            at = body + size + (size & 1)
        }
        return nil
    }
}
