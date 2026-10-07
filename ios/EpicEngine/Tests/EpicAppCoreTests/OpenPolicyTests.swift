// OpenPolicy.swift: GameController.kt's open (a chapter end comes back; any other end starts again with the keep vars),
// L11, and D7's hook.

import Foundation
import Testing

@testable import EpicAppCore

struct OpenPolicyTests {
    private static func say(_ text: String) -> String {
        #"[{ "play": "\#(text)", "dur": 1.0, "lines": [{ "at": 0, "len": 1, "who": "H", "text": "\#(text)" }] }]"#
    }

    /// A free map whose chapter 1 ends locked (its next chapter is in a pack), with "level" kept between plays.
    private static let free = """
        {
          "format": 1, "id": "t", "title": "T", "start": "a",
          "vars": { "level": 1, "tries": 0 },
          "keep": ["level"],
          "who": { "H": "" },
          "nodes": {
            "a": { "set": { "tries": "+1" }, "say": \(say("a")), "ask": { "answers": [
              { "words": ["win"], "set": { "level": "+1" }, "go": "won" },
              { "words": ["lose"], "go": "lost" },
              { "words": ["chapter"], "set": { "level": "+1" }, "go": "free-end" }
            ] } },
            "won": { "say": \(say("won")),
                     "end": { "kind": "chapter", "title": "Chapter 1", "next": "b", "locked": "t-pack" } },
            "lost": { "say": \(say("lost")), "end": { "kind": "gameover", "title": "Lost", "retry": "a" } },
            "free-end": { "say": \(say("free")), "end": { "kind": "chapter", "title": "A free chapter", "next": "a" } }
          }
        }
        """

    /// Its pack: chapter 2, and its own version of chapter 1's end, unlocked.
    private static let pack = """
        {
          "format": 1, "game": "t", "id": "t-pack", "version": 1, "title": "P", "product": "p",
          "nodes": {
            "won": { "say": \(say("won")), "end": { "kind": "chapter", "title": "Chapter 1", "next": "b" } },
            "b": { "say": \(say("b")), "ask": { "answers": [{ "any": true, "go": "a" }] } }
          }
        }
        """

    private func saveAfter(_ answer: String, _ map: GameMap) throws -> Saved {
        let s = Session(map)
        _ = try s.start()
        _ = try s.answer(answer)
        return s.save()
    }

    /// Opening a game whose save is at an end it can't go on from starts it again with the map's keep variables, as
    /// PLAY AGAIN's restart() does.
    @Test func anEndedSaveStartsAgainKeepingKeepVars() throws {
        // fixed: D15, an ended save played start(), which dropped the keep variables (Alien Customs went back to level 1)
        let map = try GameMap.parse(Self.free)
        let saved = try saveAfter("win", map)
        #expect(saved.ended)
        #expect(saved.vars["level"] == 2.0)

        let game = Session(map)
        let o = try OpenPolicy.android.open(game, saved: saved) { Session(map) }
        #expect(o.game === game)
        #expect(!o.welcomeBack)
        #expect(!o.clearSave)
        #expect(o.turn.node == "a")
        #expect(o.turn.end == nil)
        #expect(o.turn.ask != nil)
        #expect(game.vars["level"] == 2.0)
        #expect(game.vars["tries"] == 1.0)

        let again = Session(map)
        try again.restore(saved)
        _ = try again.restart()
        #expect(again.vars == game.vars)

        // A game over the same way.
        let lost = try saveAfter("lose", map)
        let o2 = try OpenPolicy.android.open(Session(map), saved: lost) { Session(map) }
        #expect(o2.turn.node == "a")
        #expect(o2.game.save().vars["level"] == 1.0)
    }

    /// A chapter end whose next chapter is in the map comes back, NEXT CHAPTER showing, with "Welcome back!".
    @Test func aChapterEndComesBack() throws {
        // fixed: a chapter end started the game afresh, so chapter 2 was never offered again
        let map = try GameMap.parse(Self.free)
        let saved = try saveAfter("chapter", map)
        let game = Session(map)
        let o = try OpenPolicy.android.open(game, saved: saved) { Session(map) }
        #expect(o.welcomeBack)
        #expect(o.turn.steps.isEmpty)
        #expect(o.turn.node == "free-end")
        #expect(o.turn.end.map { $0.canGoOn(in: game) } == true)
        #expect(game.vars["level"] == 2.0)
    }

    @Test func aSaveAtAQuestionIsPickedUp() throws {
        let map = try GameMap.parse(Self.free)
        let game = Session(map)
        let saved = Saved(node: "a", vars: ["level": 3.0, "tries": 4.0], ended: false)
        let o = try OpenPolicy.android.open(game, saved: saved) { Session(map) }
        #expect(o.welcomeBack)
        #expect(!o.clearSave)
        #expect(o.turn.node == "a")
        #expect(o.turn.steps == (try GameMap.parse(Self.free)).nodes["a"]?.say)
        #expect(game.vars["level"] == 3.0)
        #expect(game.vars["tries"] == 4.0)
    }

    @Test func noSaveStarts() throws {
        let map = try GameMap.parse(Self.free)
        let o = try OpenPolicy.android.open(Session(map), saved: nil) { Session(map) }
        #expect(o.turn.node == "a")
        #expect(!o.welcomeBack)
        #expect(!o.clearSave)
    }

    /// L11: a save that can't be opened (Kotlin would crash) is cleared, and a fresh game starts. (Nuclear War now
    /// starts afresh itself from a save it can't read, so a game that throws stands in for it.)
    @Test func aSaveThatCantBeOpenedStartsAFreshGame() throws {
        let map = try GameMap.parse(Self.free)
        let saved = Saved(node: "a", vars: ["level": 3.0], ended: false)
        let fresh = Session(map)
        let o = try OpenPolicy.android.open(Unopenable(map), saved: saved) { fresh }
        #expect(o.clearSave)
        #expect(!o.welcomeBack)
        #expect(o.game === fresh)
        #expect(o.turn == (try Session(map).start()))
        #expect(fresh.vars["level"] == 1.0)
        // With no save to blame, or when the fresh game fails too, the error is the caller's (L1).
        #expect(throws: PlayError.self) { try OpenPolicy.android.open(Broken(), saved: nil) { Broken() } }
        #expect(throws: PlayError.self) { try OpenPolicy.android.open(Broken(), saved: saved) { Broken() } }
    }

    /// Nuclear War at an end always starts afresh (its settings kept), under either policy: its resume of an ended
    /// save would ask "can you repeat that?" with no buttons.
    @Test func nuclearWarAtAnEndStartsAfresh() throws {
        let played = NuclearWar(audio: .placeholder(), random: XorWowRandom(seed: 3))
        _ = try played.start()
        let s = played.save()
        let ended = Saved(node: s.node, vars: s.vars, ended: true)
        for policy in [OpenPolicy.android, .unlocking(ends: [s.node])] {
            let game = NuclearWar(audio: .placeholder(), random: XorWowRandom(seed: 11))
            let o = try policy.open(game, saved: ended) { NuclearWar(audio: .placeholder()) }
            #expect(!o.welcomeBack)
            #expect(!o.clearSave)
            #expect(o.game === game)
            let reference = NuclearWar(audio: .placeholder(), random: XorWowRandom(seed: 11))
            #expect(o.turn == (try reference.open(ended)))
            #expect(o.turn.ask?.buttons.isEmpty == false)
        }
    }

    /// D7's hook: with the pack installed, a save at the free map's locked chapter end opens at that end, so NEXT
    /// CHAPTER shows; without the pack, or at a game over, the game starts again.
    @Test func unlockingOpensAnUnlockedChapterEnd() throws {
        let free = try GameMap.parse(Self.free)
        let full = try GameMap.parse(Self.free, packs: [Self.pack])
        let ends = OpenPolicy.lockedChapterEnds(free)
        #expect(ends == ["won"])
        #expect(OpenPolicy.lockedChapterEnds(full).isEmpty)        // the pack's own end isn't locked
        let saved = try saveAfter("win", free)
        let policy = OpenPolicy.unlocking(ends: ends)

        let game = Session(full)
        let o = try policy.open(game, saved: saved) { Session(full) }
        #expect(o.welcomeBack)            // as Android's open says, now that the end comes back there too
        #expect(!o.clearSave)
        #expect(o.turn.steps.isEmpty)
        #expect(o.turn.node == "won")
        let end = try #require(o.turn.end)
        #expect(end.title == "Chapter 1")
        #expect(end.canGoOn(in: game))
        #expect(game.vars["level"] == 2.0)
        #expect(try game.nextChapter().node == "b")

        // fixed: Android's open (and so D7's other cases) started a chapter end afresh; it comes back there now
        #expect(try OpenPolicy.android.open(Session(full), saved: saved) { Session(full) }.turn.node == "won")
        #expect(try policy.open(Session(free), saved: saved) { Session(free) }.turn.node == "a")
        let freeChapter = try saveAfter("chapter", full)
        #expect(freeChapter.ended)
        #expect(try policy.open(Session(full), saved: freeChapter) { Session(full) }.turn.node == "free-end")
        let lost = try saveAfter("lose", full)
        let atLost = OpenPolicy.unlocking(ends: ["lost"])
        #expect(try atLost.open(Session(full), saved: lost) { Session(full) }.turn.node == "a")
    }

    /// D7: which policy a game opens with, from the list or after a pack is installed.
    @Test func openingFollowsD7() throws {
        let pack = PackInfo(id: "t-pack", game: "t", title: "P", description: "", product: "p", version: 1, size: 1,
                            sha256: "")
        let other = PackInfo(id: "o-pack", game: "o", title: "O", description: "", product: "o", version: 1, size: 1,
                             sha256: "")
        let game = GameInfo(id: "t", title: "T", blurb: "", free: "", packs: [pack])
        let plain = GameInfo(id: "n", title: "N", blurb: "", free: "", packs: [])
        #expect(OpenPolicy.opening(game, lockedEnds: ["won"]) == .unlocking(ends: ["won"]))
        #expect(OpenPolicy.opening(game, installedPack: pack, lockedEnds: ["won"]) == .unlocking(ends: ["won"]))
        #expect(OpenPolicy.opening(game, installedPack: other, lockedEnds: ["won"]) == .android)
        #expect(OpenPolicy.opening(plain, installedPack: pack, lockedEnds: []) == .android)
        #expect(OpenPolicy.opening(plain, lockedEnds: []) == .android)
    }

    /// D7 on the real maps: Frootopia's two story 1 endings and Alien Customs' level 5 open at their end once the
    /// pack is in; The Werewolf's win isn't a chapter end, so it starts afresh as on Android.
    @Test func theRealLockedEndsOpenThereWithTheirPack() throws {
        let games = try AppTestRepo.games()
        for (id, end, next) in [("frootopia", "fr-55", "fr2-0"), ("frootopia", "fr-54", "fr2-0"),
                                ("alien-customs", "L4_win", "L5_intro")] {
            let info = try AppTestRepo.game(id)
            let free = try GameMap.parse(data: Data(contentsOf: games.appendingPathComponent("\(id)/map.json")))
            let packs = try info.packs.map {
                try Data(contentsOf: games.appendingPathComponent("\(id)/packs/\($0.id).json"))
            }
            let full = try GameMap.parse(data: Data(contentsOf: games.appendingPathComponent("\(id)/map.json")),
                                         packs: packs)
            let ends = OpenPolicy.lockedChapterEnds(free)
            #expect(ends.contains(end), "\(id): \(ends)")
            let saved = Saved(node: end, vars: [:], ended: true)
            let game = Session(full)
            let o = try OpenPolicy.opening(info, lockedEnds: ends).open(game, saved: saved) { Session(full) }
            #expect(o.turn.end?.next == next)
            #expect(o.turn.end.map { $0.canGoOn(in: game) } == true)
            // Without the pack, Android's open: afresh.
            let o2 = try OpenPolicy.opening(info, lockedEnds: ends).open(Session(free), saved: saved) { Session(free) }
            #expect(o2.turn.end == nil)
        }
        let wolf = try GameMap.parse(data: Data(contentsOf: games.appendingPathComponent("the-werewolf/map.json")))
        #expect(OpenPolicy.lockedChapterEnds(wolf).isEmpty)
    }

    @Test func canGoOn() throws {
        let full = Session(try GameMap.parse(Self.free, packs: [Self.pack]))
        let free = Session(try GameMap.parse(Self.free))
        let chapter = End(kind: "chapter", title: "C", next: "b", retry: nil, locked: nil)
        #expect(chapter.canGoOn(in: full))
        #expect(!chapter.canGoOn(in: free))
        #expect(!End(kind: "chapter", title: "C", next: nil, retry: nil, locked: nil).canGoOn(in: full))
        #expect(!End(kind: "gameover", title: "G", next: "b", retry: "a", locked: nil).canGoOn(in: full))
        #expect(!chapter.canGoOn(in: NuclearWar(audio: .placeholder())))
    }
}

/// A map game whose saves can't be opened.
private final class Unopenable: Play {
    let inner: Session
    init(_ map: GameMap) { inner = Session(map) }
    var who: LinkedMap<String> { inner.who }
    var ask: Ask? { inner.ask }
    func start() throws -> Turn { try inner.start() }
    func canResume(_ saved: Saved) -> Bool { true }
    func resume(_ saved: Saved) throws -> Turn { throw PlayError("unreadable") }
    func answer(_ said: String) throws -> Turn { try inner.answer(said) }
    func silence() throws -> Turn { try inner.silence() }
    func restart(at: String?) throws -> Turn { try inner.restart(at: at) }
    func nextChapter() throws -> Turn { try inner.nextChapter() }
    func hasChapter(_ next: String) -> Bool { inner.hasChapter(next) }
    func save() -> Saved { inner.save() }
    func understands(_ said: String) throws -> Bool { try inner.understands(said) }
}

/// A game that can't be played at all.
private final class Broken: Play {
    var who: LinkedMap<String> { [:] }
    var ask: Ask? { nil }
    func start() throws -> Turn { throw PlayError("broken") }
    func canResume(_ saved: Saved) -> Bool { true }
    func resume(_ saved: Saved) throws -> Turn { throw PlayError("broken") }
    func answer(_ said: String) throws -> Turn { throw PlayError("broken") }
    func silence() throws -> Turn { throw PlayError("broken") }
    func restart(at: String?) throws -> Turn { throw PlayError("broken") }
    func nextChapter() throws -> Turn { throw PlayError("broken") }
    func hasChapter(_ next: String) -> Bool { false }
    func save() -> Saved { Saved(node: "", vars: [:], ended: false) }
    func understands(_ said: String) throws -> Bool { false }
}
