// MapsTest.kt: every map, on its own and with its packs, loads, and a bot reaches every node and every end.

import Foundation
import Testing

@testable import EpicEngine

/**
 * Every map in games/, on its own and with its packs (games/<id>/packs/): loads, and a bot that tries every answer
 * in every state reaches every node and every end.
 *
 * Unlike MapsTest.kt, the bot is deterministic: the ended states it explores carry on with a seeded XorWowRandom
 * (Kotlin's are unseeded, MapsTest.kt:109). Its printed stats aren't compared with Kotlin's; the fixtures' map walks
 * are the parity check.
 *
 * The bot needs its full counts (EPIC_SLOW=1) to reach every node: Pirate Quest's empty pouch and The Werewolf's
 * numbered guesses are deep. The quick loop plays fewer states and walks, and checks only that every turn asks, ends
 * or quits and that nothing fails.
 */
struct MapsTests {
    /// The free map's name, and "<name> + packs" for the game with all its packs merged in, sorted by folder.
    static func variants() -> [String] {
        guard let root = TestRepo.root else { return [] }
        let games = root.appendingPathComponent("games")
        return gameDirs(games).flatMap { dir in
            [dir.lastPathComponent] + (packFiles(dir).isEmpty ? [] : ["\(dir.lastPathComponent) + packs"])
        }
    }

    private static func gameDirs(_ games: URL) -> [URL] {
        let all = (try? FileManager.default.contentsOfDirectory(at: games, includingPropertiesForKeys: nil)) ?? []
        return all.filter { isFile($0.appendingPathComponent("map.json")) }
            .sorted { Kt.utf16Less($0.lastPathComponent, $1.lastPathComponent) }
    }

    private static func packFiles(_ dir: URL) -> [URL] {
        let all = (try? FileManager.default.contentsOfDirectory(
            at: dir.appendingPathComponent("packs"), includingPropertiesForKeys: nil)) ?? []
        return all.filter { $0.pathExtension == "json" }.sorted { Kt.utf16Less($0.lastPathComponent, $1.lastPathComponent) }
    }

    private static func isFile(_ url: URL) -> Bool {
        var dir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &dir) && !dir.boolValue
    }

    /// A variant's map: the free map, or with " + packs" the game with its packs merged in.
    private static func load(_ name: String) throws -> GameMap {
        let games = try TestRepo.games()
        let id = name.removingSuffix(" + packs")
        let dir = games.appendingPathComponent(id)
        let map = dir.appendingPathComponent("map.json")
        return try GameMap.load(map, packs: id == name ? [] : packFiles(dir))
    }

    /// Each game's free map, and the game with all its packs merged in, by a name for the messages.
    private func named() throws -> [(String, GameMap)] {
        let games = try TestRepo.games()
        try #require(!Self.gameDirs(games).isEmpty, "no maps in \(games.path)")
        return try Self.variants().map { ($0, try Self.load($0)) }
    }

    private func maps() throws -> [GameMap] { try named().map(\.1) }

    /// Kotlin loops over the maps in one test; here each map is a case of its own, so they run side by side.
    @Test(.tags(.slow), arguments: MapsTests.variants())
    func botReachesEveryNodeAndEnd(_ name: String) throws {
        let map = try Self.load(name)
        let bot = Bot(map)
        let slow = TestRepo.slow
        try bot.explore(limit: slow ? Bot.limit(map) : Bot.limit(map) / 40)
        try bot.walk(XorWowRandom(seed: 7), slow ? 3000 : 200)
        if slow {
            let never = Set(map.nodes.keys).subtracting(bot.visited)
            #expect(never.isEmpty, "\(name): never reached \(never.sorted())")
            let ends = Set(map.nodes.values.filter { $0.end != nil }.map(\.id))
            #expect(ends.subtracting(bot.ends) == [], "\(name): ends never reached")
        }
        print(
            "\(name): \(bot.states) states\(bot.capped ? " (capped)" : "") and \(bot.walks) random walks, "
                + "\(bot.turns) turns, \(bot.visited.count) nodes, \(bot.ends.count) ends, \(bot.quits) ways out"
                + (slow ? "" : " (fewer than EPIC_SLOW=1 plays, so not every node is checked)"))
    }

    @Test func yesAndNoButtonsAlwaysAnswer() throws {
        for map in try maps() {
            for n in map.nodes.values {
                guard let ask = n.ask else { continue }
                let vars = map.vars.merging(["tries": 0.0])
                let results = try ask.buttons.map { ($0.label, try Matcher.match(map, ask, vars, $0.value)) }
                if ask.buttons.map(\.value) == ["yes", "no"] {
                    for (label, r) in results {
                        #expect(r.index != nil, "\(map.id) \(n.id): the \(label) button isn't understood (\(r.how))")
                    }
                } else if !ask.buttons.isEmpty {
                    #expect(results.contains { $0.1.index != nil }, "\(map.id) \(n.id): no button is understood")
                }
            }
        }
    }

    @Test func okayAndNotNowAnswerAsYesAndNoDo() throws {
        // fixed: "okay", "ok" and "not now" weren't understood in Alien Customs, Pirate Quest, The Werewolf and others
        for map in try maps() {
            for n in map.nodes.values {
                guard let ask = n.ask else { continue }
                let isYes = { (a: Answer) in if case .yes = a.match { true } else { false } }
                let isNo = { (a: Answer) in if case .no = a.match { true } else { false } }
                guard ask.answers.contains(where: isYes), ask.answers.contains(where: isNo) else { continue }
                let vars = map.vars.merging(["tries": 0.0])
                func action(_ said: String) throws -> Go? {
                    try Matcher.match(map, ask, vars, said).index.flatMap { ask.answers[$0].go }
                }
                for (said, like) in [("okay", "yes"), ("ok", "yes"), ("not now", "no")] {
                    #expect(try action(said) == action(like), "\(map.id) \(n.id): \"\(said)\"")
                }
            }
        }
    }

    @Test func noPatternHasAControlCharacter() throws {
        // fixed: Signal Decoders had 54 patterns with a backspace where "\b" was meant, so they never matched
        for map in try maps() {
            for n in map.nodes.values {
                for a in n.ask?.answers ?? [] {
                    guard case .re(let re) = a.match else { continue }
                    #expect(
                        !re.pattern.unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x7f },
                        "\(map.id) \(n.id): a control character in \(re.pattern)")
                }
            }
        }
    }

    @Test func aSignalDecodersAnswerWithAgainInItIsATry() throws {
        // fixed: "esos again" played the puzzle again (its catcher never matched) instead of counting a try
        let map = try TestRepo.load("signal-decoders")
        let s = Session(map)
        try s.restore(Saved(node: "ai-p1", vars: map.vars, ended: false))
        let t = try s.answer("esos again")
        #expect(s.vars["tries"] == 1.0)
        #expect(t.node == "ai-p1-hint")
        _ = try s.answer("say that again")
        #expect(s.vars["tries"] == 1.0, "a plain repeat isn't a try")
    }
}

/**
 * Explores the states (node and variables, decks aside) with every kind of answer and the first random branches,
 * up to a limit; then random walks reach what that missed (questions drawn from big decks, long streaks).
 */
private final class Bot {
    static let branches = 4

    /// Kotlin's explore() limit: minOf(60_000, 2_000_000 / maxOf(1, map.vars.size)).
    static func limit(_ map: GameMap) -> Int { Swift.min(60_000, 2_000_000 / Swift.max(1, map.vars.count)) }

    let map: GameMap
    var visited = Set<String>()
    var ends = Set<String>()
    var quits = 0
    var states = 0
    var turns = 0
    var walks = 0
    var capped = false

    init(_ map: GameMap) { self.map = map }

    private func check(_ t: Turn) throws {
        turns += 1
        visited.formUnion(t.visited)
        if t.quit { quits += 1 }
        if t.end != nil { ends.insert(t.node) }
        try #require(t.quit || t.end != nil || t.ask != nil, "\(map.id): a turn at \(t.node) neither asks, ends nor quits")
    }

    func explore(limit: Int) throws {
        // States are kept as a 64-bit hash of the node and variables (decks aside), and queued only when new, so
        // a big map's frontier fits in memory; a hash collision only skips a state.
        var seen = Set<Int64>()
        var queue: [Saved] = []
        var head = 0
        func record(_ s: Session, _ t: Turn) throws {
            try check(t)
            if t.quit { return }
            let state = s.save()
            if seen.count >= limit {
                capped = true
                return
            }
            if seen.insert(hash(state)).inserted { queue.append(state) }
        }
        for choose in choosers() {
            let s = Session(map, choose: choose)
            try record(s, s.start())
        }
        while head < queue.count {
            let state = queue[head]
            head += 1
            states += 1
            if state.ended {
                let end = try #require(try map.node(state.node).end)
                // Kotlin carries on with an unseeded Session(map); a XorWowRandom seeded from the state's hash makes
                // the run the same every time.
                let random = XorWowRandom(longSeed: hash(state))
                let s = Session(map) { n in try random.nextInt(until: n) }
                try s.restore(state)
                try record(s, hasNext(end) ? s.nextChapter() : playAgain(s, end))
                continue
            }
            for input in try inputs(try #require(try map.node(state.node).ask)) {
                for choose in choosers() {
                    let s = Session(map, choose: choose)
                    try s.restore(state)
                    try record(s, input.map { try s.answer($0) } ?? s.silence())
                }
            }
            // Let the done part of the queue go.
            if head > 4096 && head * 2 > queue.count {
                queue.removeFirst(head)
                head = 0
            }
        }
    }

    /**
     * Plays [count] games from the start with random answers and random draws. Three answers in four are ones
     * the question takes (the rest: silence, nonsense or "repeat"), so a game gets deep into a long story; and in
     * every other game, half the time the bot says what it said last, as players do ("next" through all the
     * villagers).
     */
    func walk(_ rng: XorWowRandom, _ count: Int, turnsEach: Int = 80) throws {
        for game in 0..<count {
            walks += 1
            let s = Session(map) { n in try rng.nextInt(until: n) }
            var t = try s.start()
            var last: String? = nil
            try check(t)
            for _ in 0..<turnsEach {
                if t.quit { break }
                if let end = t.end {
                    t = try hasNext(end) ? s.nextChapter() : playAgain(s, end)
                } else {
                    let options = try inputs(try #require(t.ask))
                    let taken = options.count > 3 ? Array(options.dropFirst(3)) : options  // silence, nonsense, repeat first
                    let said: String?
                    if game % 2 == 1, options.contains(where: { $0 == last }), try rng.nextBoolean() {
                        said = last
                    } else if try rng.nextInt(until: 4) > 0 {
                        said = taken[try rng.nextInt(until: taken.count)]
                    } else {
                        said = options[try rng.nextInt(until: options.count)]
                    }
                    last = said
                    t = try said.map { try s.answer($0) } ?? s.silence()
                }
                try check(t)
            }
        }
    }

    /**
     * The random choices tried from each state: the first few options every time, and the lowest and highest in
     * turn (so a dice game can be lost again and again, as in Pirate Quest's empty coin pouch).
     */
    private func choosers() -> [(Int) throws -> Int] {
        var i = 0
        var out: [(Int) throws -> Int] = (0..<Bot.branches).map { k in { n in k % n } }
        out.append { n in
            defer { i += 1 }
            return i % 2 == 0 ? 0 : n - 1
        }
        return out
    }

    /// Kotlin's `end.next in map.nodes`.
    private func hasNext(_ end: End) -> Bool { end.kind == "chapter" && end.next.map { map.nodes.contains($0) } == true }

    /// The sorted order of the last variables hashed, decks aside (most states have the same names in the same order).
    private var sortedKeys: [String] = []
    private var sortedOrder: [Int] = []

    /// A 64-bit FNV-1a hash of a state: its node, whether it has ended, and its variables (decks aside), as
    /// "name=value;" in name order with Kotlin's toString for the value ("1.0").
    private func hash(_ s: Saved) -> Int64 {
        var h: Int64 = -3750763034362895579                      // 0xcbf29ce484222325
        func mix<S: Sequence>(_ units: S) where S.Element == UInt16 {
            for u in units { h = (h ^ Int64(u)) &* 1099511628211 }
        }
        mix(s.node.utf16)
        mix((s.ended ? "|ended|" : "|").utf16)
        let keys = s.vars.keys
        if keys != sortedKeys {
            sortedKeys = keys
            sortedOrder = keys.indices.filter { !keys[$0].hasPrefix("deck_") }
                .sorted { Kt.utf16Less(keys[$0], keys[$1]) }
        }
        for i in sortedOrder {
            mix(keys[i].utf16)
            mix(CollectionOfOne(UInt16(0x3D)))                   // =
            mix(text(s.vars.values[i]).utf16)
            mix(CollectionOfOne(UInt16(0x3B)))                   // ;
        }
        return h
    }

    /// Kotlin's toString of a variable, with whole numbers below 10^7 written directly ("12.0", as Java does).
    private func text(_ v: Value) -> String {
        if case .number(let d) = v, d.rounded(.towardZero) == d, Swift.abs(d) < 1e7, !(d == 0 && d.sign == .minus) {
            return "\(Int64(d)).0"
        }
        return v.kotlinString
    }

    /// The end screen's "play again" (or "try again" at a game over with a retry point).
    private func playAgain(_ s: Session, _ end: End) throws -> Turn {
        if end.kind == "gameover", let retry = end.retry { return try s.restart(at: retry) }
        return try s.restart()
    }

    /// One answer of each kind the question takes, its buttons, nonsense, "repeat" and silence (nil).
    func inputs(_ ask: Ask) throws -> [String?] {
        let repeatWord = try #require(map.words.repeat.first).text
        var out: [String?] = [nil, "zzz", repeatWord]
        out += ask.buttons.map(\.value)
        for a in ask.answers {
            switch a.match {
            case .yes: out.append("yes")
            case .no: out.append("no")
            case .words(let phrases): out.append(try #require(phrases.first).text)
            case .repeat: out.append(repeatWord)
            case .seq(let seq, let table, _, _, _):
                let words = try seq.utf16.map { c in
                    try #require(map.symbols[table]?[String(decoding: [c], as: UTF16.self)]?.first)
                }
                out.append(words.joined(separator: " "))
            case .digits(let digits, _, _):
                out.append(digits.utf16.map { String(decoding: [$0], as: UTF16.self) }.joined(separator: " "))
            case .re: continue
            case .anyText: out.append("something else entirely")
            }
        }
        return out.filter { $0 == nil || !Kt.trim($0!).isEmpty }.uniqued()
    }
}
