// Session.kt: one play of a map game.

/**
 * One play of a game. Start it with [start] (or [resume]), then pass each answer to [answer], or call [silence]
 * when the player says nothing. [choose] picks the index for a random go, pick or rand (tests use it to try every
 * branch); by default it's a Kotlin XorWowRandom seeded from the system. It is always asked first, and what it returns
 * is then kept in range, as Kotlin's `choose(n).coerceIn(0, n - 1)` does: a random choice among nothing fails after
 * the call, with coerceIn's message (a PlayError for Kotlin's IllegalArgumentException).
 */
public final class Session: Play {
    public let map: GameMap
    private let choose: (Int) throws -> Int

    public private(set) var node: String
    public var vars: VarStore
    public private(set) var end: End?
    public private(set) var quit = false
    /// Left with the place kept (`{ "end": "leave" }`): the game is at the question it left from.
    public private(set) var keep = false
    private var asked: String?

    public init(_ map: GameMap, choose: @escaping (Int) throws -> Int = Session.randomChooser()) {
        self.map = map
        self.choose = choose
        node = map.start
        vars = map.vars
    }

    /// Kotlin's `Random.nextInt(n)`, from a XorWowRandom seeded from the system.
    public static func randomChooser() -> (Int) throws -> Int {
        let random = XorWowRandom()
        return { n in try random.nextInt(until: n) }
    }

    public var who: LinkedMap<String> { map.who }

    /// The question waiting for an answer, if there is one.
    public var ask: Ask? { end == nil && !quit ? map.nodes[node]?.ask : nil }

    public func start() throws -> Turn {
        end = nil
        quit = false
        keep = false
        vars.removeAll()
        vars.putAll(map.vars)
        return try play(.to(map.start))
    }

    /**
     * Whether a save can be picked up again: it waits at a question, or it is at a chapter's end whose next chapter
     * is in this map (the end screen comes back, with NEXT CHAPTER).
     */
    public func canResume(_ saved: Saved) -> Bool {
        guard let n = map.nodes[saved.node] else { return false }
        if !saved.ended { return n.ask != nil }
        guard let e = n.end, e.kind == "chapter", let next = e.next else { return false }
        return hasChapter(next)
    }

    /**
     * The game from a save: picked up again where it can be. Any other save (a game over or a last end, a plain quit,
     * a place no longer in the map) starts again with its "keep" variables, as PLAY AGAIN does.
     */
    public func open(_ saved: Saved?) throws -> Turn {
        guard let saved else { return try start() }
        if canResume(saved) { return try resume(saved) }
        vars.removeAll()
        vars.putAll(map.vars)
        for k in map.keep {
            if let v = saved.vars[k] { vars[k] = v }
        }
        return try restart()
    }

    /**
     * Back at a saved place: the end screen, or the node's say again and its question. A question whose node says
     * nothing itself (the turn before it did the talking) plays its reprompt.
     */
    public func resume(_ saved: Saved) throws -> Turn {
        guard let n = map.nodes[saved.node], n.ask != nil || n.end != nil else { return try start() }
        try restore(saved)
        if saved.ended { return turn([], []) }
        var again = try resolve(n.say)
        if again.isEmpty { again = try resolve(n.ask?.reprompt ?? []) }
        return turn(again, [n.id])
    }

    /// Puts the game at a saved place without playing anything.
    public func restore(_ saved: Saved) throws {
        let n = try map.node(saved.node)
        node = saved.node
        vars.removeAll()
        vars.putAll(map.vars)
        vars.putAll(saved.vars)
        end = saved.ended ? n.end : nil
        quit = false
        keep = false
    }

    /// A plain quit saves as ended: it isn't picked up again, but its "keep" variables carry over ([open]).
    public func save() -> Saved { Saved(node: node, vars: vars, ended: end != nil || (quit && !keep)) }

    public func answer(_ said: String) throws -> Turn {
        guard let ask else { throw PlayError("the game isn't waiting for an answer (at \(node))") }
        asked = node
        let result = try Matcher.match(map, ask, vars, said)
        let heard = Heard(said: said, answer: result.index, how: result.how)
        var out: [Step] = []
        var visited: [String] = []
        if let index = result.index {
            guard ask.answers.indices.contains(index) else {
                throw PlayError("Index \(index) out of bounds for length \(ask.answers.count)")
            }
            let a = ask.answers[index]
            try apply(a.set)
            if let go = a.go { try run(go, &out, &visited, 0) } else { try otherwise(ask, &out, &visited) }
        } else if result.repeat {
            out += try resolve(map.repeatSays ? map.node(node).say : ask.reprompt)
        } else {
            try otherwise(ask, &out, &visited)
        }
        return turn(out, visited, heard)
    }

    /// The player said nothing: the reprompt, and the same question again.
    public func silence() throws -> Turn {
        guard let ask else { throw PlayError("the game isn't waiting for an answer (at \(node))") }
        return turn(try resolve(ask.reprompt), [])
    }

    /// Starts again, at [at] (or the start), with the starting variables except the map's "keep".
    public func restart(at: String?) throws -> Turn { try play(.restart(at ?? map.start)) }

    /// Whether a chapter end's next chapter is in this map.
    public func hasChapter(_ next: String) -> Bool { map.nodes.contains(next) }

    public func understands(_ said: String) throws -> Bool {
        guard let a = ask else { return false }
        let r = try Matcher.match(map, a, vars, said)
        return r.index != nil || r.repeat || r.aside
    }

    /// After a chapter's end: its next chapter, with the variables kept.
    public func nextChapter() throws -> Turn {
        guard let e = end else { throw PlayError("not at an end") }
        guard let next = e.next else { throw PlayError("\(e.title): no next chapter") }
        if !map.nodes.contains(next) { throw PlayError("\(next) isn't in this map (pack \(e.locked ?? "null"))") }
        end = nil
        return try play(.to(next))
    }

    private func play(_ go: Go) throws -> Turn {
        var out: [Step] = []
        var visited: [String] = []
        try run(go, &out, &visited, 0)
        return turn(out, visited)
    }

    private func turn(_ steps: [Step], _ visited: [String], _ heard: Heard? = nil) -> Turn {
        Turn(steps: steps, ask: ask, end: end, quit: quit, node: node, visited: visited, heard: heard, keep: keep)
    }

    private func otherwise(_ ask: Ask, _ out: inout [Step], _ visited: inout [String]) throws {
        guard let e = ask.otherwise else {
            out += try resolve(ask.reprompt)
            return
        }
        try apply(e.set)
        if let go = e.go {
            try run(go, &out, &visited, 0)
        } else {
            out += try resolve(e.say.isEmpty ? ask.reprompt : e.say)
        }
    }

    /// An index below [n] from [choose], kept in range: Kotlin's `choose(n).coerceIn(0, n - 1)`.
    private func pick(_ n: Int) throws -> Int { try choose(n).clamped(0, n - 1) }

    /**
     * Kotlin's run and enter call each other in tail position (a random or if go, a redirect, a node's go); here
     * they take turns in a loop with the same hop counts, so a long chain of gos reaches the hop limit's MapError
     * instead of running out of a thread's stack first.
     */
    private func run(_ go: Go, _ out: inout [Step], _ visited: inout [String], _ hops: Int) throws {
        var next: (go: Go, hops: Int)? = (go, hops)
        while let n = next {
            next = try step(n.go, &out, &visited, n.hops)
        }
    }

    /// One go of [run]: the go to run next and its hop count, or nil when the turn's gos are done.
    private func step(
        _ go: Go, _ out: inout [Step], _ visited: inout [String], _ hops: Int
    ) throws -> (go: Go, hops: Int)? {
        if hops > 500 { throw MapError("the game went round in a loop at \(node)") }
        switch go {
        case .to(let id):
            return try enter(id, &out, &visited, hops)
        case .random(let targets):
            return (targets[try pick(targets.count)], hops + 1)
        case .if(let cases, let otherwise):
            return (cases.first(where: { $0.cond.test(vars) })?.go ?? otherwise, hops + 1)
        case .restart(let id):
            let kept = map.keep.compactMap { k in vars[k].map { (k, $0) } }
            vars.removeAll()
            vars.putAll(map.vars)
            for (k, v) in kept { vars[k] = v }
            end = nil
            quit = false
            keep = false
            return try enter(id, &out, &visited, hops)
        case .quit:
            quit = true
            return nil
        case .leave:
            quit = true
            keep = true
            if let asked { node = asked }
            return nil
        case .draw(let nodes, let deck):
            let name = "deck_\(deck)"
            // Kotlin's Set<String>: a node is drawn when its exact text is.
            let drawnList = Kt.split(vars[name]?.stringValue ?? "", ",").filter { !$0.isEmpty }.uniqued()
            let drawn = Set(drawnList.map(ExactKey.init))
            let left = nodes.filter { !drawn.contains(ExactKey($0)) }
            let from = left.isEmpty ? nodes : left
            let kept = left.isEmpty ? [] : drawnList
            let pick = from[try pick(from.count)]
            vars[name] = .string((kept + [pick]).uniqued().joined(separator: ","))
            return try enter(pick, &out, &visited, hops + 1)
        }
    }

    /// The steps as they play now: [Step.when], [Step.pick] and [Step.by] resolved with the current variables.
    public func resolve(_ steps: [Step]) throws -> [Step] {
        var out: [Step] = []
        for s in steps {
            switch s {
            case .when(let cond, let inner):
                if cond.test(vars) { out += try resolve(inner) }
            case .pick(let options):
                if !options.isEmpty { out += try resolve(options[try pick(options.count)]) }
            case .by(let variable, let cases, let otherwise):
                out += try resolve(cases[Expr.key(vars[variable])] ?? otherwise)
            default:
                out.append(s)
            }
        }
        return out
    }

    /// Enters a node; returns its redirect's or its own go, for [run] to run next.
    private func enter(
        _ id: String, _ out: inout [Step], _ visited: inout [String], _ hops: Int
    ) throws -> (go: Go, hops: Int)? {
        let n = try map.node(id)
        if let r = n.redirect.first(where: { $0.cond.test(vars) }) { return (r.go, hops + 1) }
        node = id
        visited.append(id)
        try apply(n.set)
        out += try resolve(n.say)
        if let go = n.go { return (go, hops + 1) }
        if let e = n.end { end = e }
        return nil
    }

    private func apply(_ set: SetList) throws {
        for (name, v) in set {
            switch v {
            case .assign(let value):
                vars[name] = value
            case .add(let amount):
                vars[name] = .number((vars[name]?.numberValue ?? 0) + amount)
            case .rand(let from, let to):
                // Kotlin's Int arithmetic, which wraps, and its choose(n).coerceIn(0, to - from).
                let span = to &- from
                let r = try choose(Int(span &+ 1)).clamped(0, Int(span))
                vars[name] = .number(Double(from &+ Int32(r)))
            case .calc(let expr):
                vars[name] = expr.eval(vars) ?? .number(0)
            }
        }
    }
}
