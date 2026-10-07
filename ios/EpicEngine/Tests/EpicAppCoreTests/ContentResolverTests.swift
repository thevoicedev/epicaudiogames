// ContentResolver.swift: AudioPlayer.kt's uri, packs first, names matched exactly (the Mac's file system ignores case).

import Foundation
import Testing

@testable import EpicAppCore

struct ContentResolverTests {
    private let scratch: Scratch

    init() throws {
        scratch = try Scratch()
        for path in [
            "Content/noodle-rush/voice/Hello.m4a", "Content/noodle-rush/voice/Hello.mp3",
            "Content/noodle-rush/voice/bye.mp3", "Content/noodle-rush/voice/song.opus", "Content/noodle-rush/intro.m4a",
            "Content/noodle-rush/cover.jpg",
            "Content/noodle-rush/voice/odd.wav", "Content/other/voice/elsewhere.m4a",
            "packs/p1/voice/bye.opus", "packs/p2/voice/bye.m4a", "packs/p2/voice/new.mp3", "packs/p2/Intro.m4a",
        ] {
            try scratch.write(path)
        }
    }

    private func resolver(_ packs: [String] = [], game: String = "noodle-rush") -> ContentResolver {
        ContentResolver(
            gameId: game, content: scratch.folder("Content"), packs: packs.map { scratch.folder("packs/\($0)") })
    }

    private func relative(_ url: URL?) -> String? {
        guard let url else { return nil }
        let base = scratch.url.standardizedFileURL.path + "/"
        let path = url.standardizedFileURL.path
        return path.hasPrefix(base) ? String(path.dropFirst(base.count)) : path
    }

    @Test func findsTheGamesOwnContent() {
        let r = resolver()
        #expect(relative(r.url("voice/Hello")) == "Content/noodle-rush/voice/Hello.m4a")     // .m4a before .mp3
        #expect(relative(r.url("voice/bye")) == "Content/noodle-rush/voice/bye.mp3")
        #expect(relative(r.url("voice/song")) == "Content/noodle-rush/voice/song.opus")
        #expect(relative(r.url("intro")) == "Content/noodle-rush/intro.m4a")
        #expect(r.url("voice/odd") == nil)
        #expect(r.url("voice/nothing") == nil)
        #expect(r.url("voice/elsewhere") == nil)
        #expect(relative(r.bundled("cover.jpg")) == "Content/noodle-rush/cover.jpg")
    }

    /// On the phone, "voice/hello" isn't "voice/Hello.m4a"; the Mac would open it, so the listing decides.
    @Test func namesMatchExactly() {
        let r = resolver(["p2"])
        #expect(r.url("voice/hello") == nil)
        #expect(r.url("Voice/Hello") == nil)
        #expect(r.url("VOICE/bye") == nil)
        #expect(r.url("intro") != nil)
        #expect(relative(r.url("Intro")) == "packs/p2/Intro.m4a")
        #expect(r.url("INTRO") == nil)
        #expect(r.bundled("Cover.jpg") == nil)
        #expect(resolver(game: "Noodle-Rush").url("intro") == nil)
    }

    /// Kotlin compares names unit by unit: "é" written one way isn't "é" written the other.
    @Test func namesMatchUnitByUnit() throws {
        try scratch.write("Content/noodle-rush/voice/caf\u{E9}.m4a")
        let voice = scratch.folder("Content/noodle-rush/voice")
        let listed = try FileManager.default.contentsOfDirectory(atPath: voice.path)
        let stored = try #require(listed.first { $0.hasPrefix("caf") })
        let name = String(stored.dropLast(".m4a".count))
        let other = name.unicodeScalars.count == 4 ? "cafe\u{301}" : "caf\u{E9}"
        let r = resolver()
        #expect(r.url("voice/\(name)") != nil)
        #expect(r.url("voice/\(other)") == nil)
    }

    /// Packs come first, in the catalog's order, each tried with every extension before the next.
    @Test func packsComeFirstInOrder() {
        #expect(relative(resolver(["p1", "p2"]).url("voice/bye")) == "packs/p1/voice/bye.opus")
        #expect(relative(resolver(["p2", "p1"]).url("voice/bye")) == "packs/p2/voice/bye.m4a")
        #expect(relative(resolver(["p1", "p2"]).url("voice/new")) == "packs/p2/voice/new.mp3")
        #expect(relative(resolver(["p1", "p2"]).url("voice/Hello")) == "Content/noodle-rush/voice/Hello.m4a")
        #expect(resolver(["p1"]).url("voice/new") == nil)
        #expect(relative(resolver(["missing", "p2"]).url("voice/new")) == "packs/p2/voice/new.mp3")
    }

    /// Folders are listed once, for as long as the game is open (a new game makes a new resolver).
    @Test func listingsAreReadOnce() throws {
        let r = resolver()
        #expect(r.url("voice/later") == nil)
        try scratch.write("Content/noodle-rush/voice/later.m4a")
        #expect(r.url("voice/later") == nil)
        #expect(resolver().url("voice/later") != nil)
    }

    @Test func oddPaths() {
        let r = resolver()
        #expect(relative(r.url("voice//Hello")) == "Content/noodle-rush/voice/Hello.m4a")
        #expect(relative(r.url("./intro")) == "Content/noodle-rush/intro.m4a")
        #expect(r.url("../other/voice/elsewhere") == nil)
        #expect(r.url("voice/") == nil)
        #expect(r.url("") == nil)
    }

    @Test func extensionsCanBeChosen() {
        let r = ContentResolver(gameId: "noodle-rush", content: scratch.folder("Content"), packs: [],
                                extensions: [".mp3", ".m4a"])
        #expect(relative(r.url("voice/Hello")) == "Content/noodle-rush/voice/Hello.mp3")
    }
}
