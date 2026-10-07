// GameMap.kt's MapParser: a map's JSON into a GameMap, with the same checks, in the same order, and the same messages.

/// Reads the merged map JSON. Every read happens in the Kotlin parser's order, so the first fault found is the same.
struct MapParser {
    let root: JSONObject

    func map() throws -> GameMap {
        let format = try root["format"].map { try $0.primitiveContent() }
        if format != "1" {
            throw MapError("format \(describe(root["format"])): only format 1 is supported")
        }
        let words = try root["words"].map { try $0.jsonObject() }
        func list(_ name: String) throws -> [Phrase] {
            try phrases(words?[name] ?? .array(GameMap.defaultWords[name]!.map { .string($0) }), name)
        }
        var nodes = LinkedMap<Node>()
        for (id, n) in try obj(root, "nodes") { nodes[id] = try node(id, try n.jsonObject()) }
        let id = try str(root, "id")
        let title = try str(root, "title")
        let start = try str(root, "start")
        let vars = try root["vars"]?.objectValue?.mapValues { k, v in try value(v, "vars.\(k)") } ?? VarStore()
        let keep = try root["keep"]?.arrayValue?.map { try $0.primitiveContent() }.uniqued() ?? []
        let r = root["repeat"]?.content ?? "reprompt"
        let repeatSays: Bool
        switch r {
        case "say": repeatSays = true
        case "reprompt": repeatSays = false
        default: throw MapError("repeat: \(r) isn't say or reprompt")
        }
        let who = try root["who"]?.objectValue?.mapValues { try $0.primitiveContent() } ?? LinkedMap<String>()
        let yes = try list("yes")
        let no = try list("no")
        let again = try list("repeat")
        let mixed = try words?["mixed"]?.objectValue.map { m in
            func of(_ name: String) throws -> [String] {
                try m[name]?.arrayValue?.map { SpokenText.normalise(try $0.primitiveContent()) } ?? []
            }
            return Mixed(yes: try of("yes"), no: try of("no"), filler: try of("filler"))
        }
        let symbols = try root["symbols"]?.objectValue?.mapValues { table in
            try table.jsonObject().mapValues { ws in try ws.jsonArray().map { SpokenText.normalise(try $0.primitiveContent()) } }
        } ?? LinkedMap<LinkedMap<[String]>>()
        return GameMap(
            id: id, title: title, start: start, vars: vars, keep: keep, repeatSays: repeatSays, who: who,
            words: WordLists(yes: yes, no: no, repeat: again, mixed: mixed), symbols: symbols, nodes: nodes
        )
    }

    func node(_ id: String, _ n: JSONObject) throws -> Node {
        let redirect = try n["redirect"]?.arrayValue?.map { try goCase(try $0.jsonObject(), "\(id) redirect") } ?? []
        let set = try sets(n["set"], id)
        let say = try steps(n["say"], id)
        let ask = try n["ask"]?.objectValue.map { try self.ask($0, id) }
        let go = try n["go"].map { try self.go($0, "\(id) go") }
        let end = try n["end"]?.objectValue.map { e in
            End(
                kind: try str(e, "kind"), title: try str(e, "title"), next: optStr(e, "next"),
                retry: optStr(e, "retry"), locked: optStr(e, "locked")
            )
        }
        if [ask != nil, go != nil, end != nil].filter({ $0 }).count != 1 {
            throw MapError("\(id): needs exactly one of ask, go and end")
        }
        return Node(id: id, redirect: redirect, set: set, say: say, ask: ask, go: go, end: end)
    }

    func ask(_ a: JSONObject, _ id: String) throws -> Ask {
        let reprompt = try steps(a["reprompt"], "\(id) reprompt")
        guard let answerList = a["answers"]?.arrayValue else { throw MapError("\(id): a question without answers") }
        let answers = try answerList.enumerated().map { i, ans in
            try answer(try ans.jsonObject(), "\(id) answer \(i + 1)")
        }
        let otherwise = try a["else"].map { e -> Else in
            if let o = e.objectValue {
                return Else(
                    say: try steps(o["say"], "\(id) else"), set: try sets(o["set"], "\(id) else"),
                    go: try o["go"].map { try go($0, "\(id) else") }
                )
            }
            return Else(say: [], set: SetList(), go: try go(e, "\(id) else"))
        }
        let buttons = try a["buttons"]?.arrayValue?.map { b -> AnswerButton in
            let o = try b.jsonObject()
            return AnswerButton(label: try str(o, "label"), value: try optStr(o, "value") ?? str(o, "label"))
        } ?? []
        return Ask(reprompt: reprompt, answers: answers, otherwise: otherwise, buttons: buttons)
    }

    func answer(_ a: JSONObject, _ where_: String) throws -> Answer {
        func flag(_ name: String) -> Bool { a[name]?.booleanOrNull == true }
        let extra = try a["words"].map { try phrases($0, where_) } ?? []
        var matches: [Match] = []
        if flag("yes") { matches.append(.yes(extra: extra)) }
        if flag("no") { matches.append(.no(extra: extra)) }
        if !flag("yes") && !flag("no") && a["words"] != nil { matches.append(.words(extra)) }
        if flag("repeat") { matches.append(.repeat) }
        let least = try a["least"]?.content.map { try int($0) }
        if let seq = optStr(a, "seq") {
            guard let table = optStr(a, "symbols") else { throw MapError("\(where_): seq without symbols") }
            matches.append(.seq(seq: seq, table: table, exact: flag("exact"), spelled: flag("spelled"), least: least))
        }
        if let digits = optStr(a, "digits") { matches.append(.digits(digits: digits, exact: flag("exact"), least: least)) }
        if let re = optStr(a, "re") { matches.append(.re(try RegexBox(re))) }
        if flag("any") { matches.append(.anyText) }
        if matches.count != 1 { throw MapError("\(where_): needs exactly one way to match") }
        return Answer(
            match: matches[0],
            go: try a["go"].map { try go($0, where_) },
            set: try sets(a["set"], where_),
            whenCond: try optStr(a, "when").map { try Condition.parse($0) },
            opposite: try a["opposite"]?.content.map { try int($0) },
            rank: try a["rank"]?.content.map { try int($0) } ?? 0
        )
    }

    func go(_ e: JSON, _ where_: String) throws -> Go {
        if case .string(let s) = e { return .to(s) }
        if let o = e.objectValue {
            if let random = o["random"] { return .random(try random.jsonArray().map { try go($0, where_) }) }
            if let cases = o["if"] {
                let list = try cases.jsonArray().map { try goCase(try $0.jsonObject(), where_) }
                guard let otherwise = o["else"] else { throw MapError("\(where_): an if without an else") }
                return .if(list, otherwise: try go(otherwise, where_))
            }
            if o.contains("restart") { return .restart(try str(o, "restart")) }
            if let draw = o["draw"] {
                let nodes = try draw.jsonArray().map { try $0.primitiveContent() }
                guard let deck = optStr(o, "deck") else { throw MapError("\(where_): a draw without a deck") }
                return .draw(nodes: nodes, deck: deck)
            }
            if optStr(o, "end") == "quit" { return .quit }
            if optStr(o, "end") == "leave" { return .leave }
        }
        throw MapError("\(where_): can't read the go \(e.kotlinxDescription)")
    }

    func goCase(_ c: JSONObject, _ where_: String) throws -> GoCase {
        let cond = try Condition.parse(try str(c, "when"))
        guard let target = c["go"] else { throw MapError("\(where_): a case without a go") }
        return GoCase(cond, try go(target, where_))
    }

    func steps(_ e: JSON?, _ where_: String) throws -> [Step] {
        try e?.arrayValue?.map { try step(try $0.jsonObject(), where_) } ?? []
    }

    func step(_ o: JSONObject, _ where_: String) throws -> Step {
        if let cond = optStr(o, "when") {
            let c = try Condition.parse(cond)
            return .when(c, [try step(o.removing("when"), where_)])
        }
        if o.contains("play") {
            let path = try str(o, "play")
            let dur = try num(o, "dur")
            let lines = try o["lines"]?.arrayValue?.map { l -> Line in
                let lo = try l.jsonObject()
                let at = try num(lo, "at")
                let len = lo["len"]?.doubleOrNull ?? 0
                let who = try str(lo, "who")
                let text = try str(lo, "text")
                let words = try lo["w"]?.arrayValue?.map { w -> Double in
                    let c = try w.primitiveContent()
                    guard let d = Kt.toDoubleOrNull(c) else { throw MapError.other("For input string: \"\(c)\"") }
                    return d
                }
                return Line(at: at, len: len, who: who, text: text, words: words, more: lo["more"]?.booleanOrNull == true)
            } ?? []
            return .play(Clip(path: path, dur: dur, lines: lines, sfx: o["sfx"]?.booleanOrNull == true))
        }
        if o.contains("bed") {
            var path: String?
            if case .string(let s) = o["bed"] { path = s }
            return .bed(path: path, volume: o["volume"]?.doubleOrNull ?? 1, dur: o["dur"]?.doubleOrNull ?? 0)
        }
        if let pick = o["pick"] { return .pick(try pick.jsonArray().map { try steps($0, "\(where_) pick") }) }
        if o.contains("by") {
            let variable = try str(o, "by")
            let cases = try o["cases"]?.objectValue?.mapValues { try steps($0, "\(where_) by") } ?? LinkedMap<[Step]>()
            return .by(variable: variable, cases: cases, otherwise: try steps(o["else"], "\(where_) by else"))
        }
        if o.contains("num") { return .num(try str(o, "num")) }
        if o.contains("pause") { return .pause(try num(o, "pause")) }
        throw MapError("\(where_): unknown step \(JSON.object(o).kotlinxDescription)")
    }

    func sets(_ e: JSON?, _ where_: String) throws -> SetList {
        try e?.objectValue?.mapValues { name, v in try setValue(v, "\(where_) set \(name)") } ?? SetList()
    }

    func setValue(_ v: JSON, _ where_: String) throws -> SetValue {
        guard v.isPrimitive else { throw MapError("\(where_): not a value") }
        if case .string(let s) = v {
            if s.utf16.first == 0x3D { return .calc(try Expr.parse(String(s.unicodeScalars.dropFirst()))) }
            if MapParser.isAdd(s) { return .add(Kt.toDoubleOrNull(s)!) }
            if let (from, to) = MapParser.rand(s) { return .rand(from: try int32(from), to: try int32(to)) }
        }
        return .assign(try value(v, where_))
    }

    func value(_ v: JSON, _ where_: String) throws -> Value {
        guard v.isPrimitive else { throw MapError("\(where_): not a value") }
        if case .string(let s) = v { return .string(s) }
        if let b = v.booleanOrNull { return .bool(b) }
        if let d = v.doubleOrNull { return .number(d) }
        throw MapError("\(where_): can't read \(v.kotlinxDescription)")
    }

    func phrases(_ e: JSON, _ where_: String) throws -> [Phrase] {
        guard let list = e.arrayValue else { throw MapError("\(where_): expected a list of phrases") }
        return try list.map { item in
            let raw = try item.primitiveContent()
            let exact = raw.utf16.first == 0x3D
            return Phrase(SpokenText.normalise(exact ? String(raw.unicodeScalars.dropFirst()) : raw), exact)
        }.filter { !$0.text.isEmpty }
    }

    // ----- JsonObject helpers -----

    func str(_ o: JSONObject, _ key: String) throws -> String {
        guard let c = o[key]?.content else {
            throw MapError("missing \"\(key)\" in \(Kt.takePrinted(JSON.object(o).kotlinxDescription, 120))")
        }
        return c
    }

    func optStr(_ o: JSONObject, _ key: String) -> String? {
        if case .string(let s) = o[key] { return s }
        return nil
    }

    func num(_ o: JSONObject, _ key: String) throws -> Double {
        guard let d = o[key]?.doubleOrNull else {
            throw MapError("missing number \"\(key)\" in \(Kt.takePrinted(JSON.object(o).kotlinxDescription, 120))")
        }
        return d
    }

    func obj(_ o: JSONObject, _ key: String) throws -> JSONObject {
        guard let v = o[key]?.objectValue else { throw MapError("missing \"\(key)\"") }
        return v
    }

    func describe(_ e: JSON?) -> String { e?.kotlinxDescription ?? "null" }

    /// Kotlin's String.toInt(), which throws NumberFormatException.
    func int(_ s: String) throws -> Int { Int(try int32(s)) }

    func int32(_ s: String) throws -> Int32 {
        guard let i = Kt.int32OrNull(s) else { throw MapError.other("For input string: \"\(s)\"") }
        return i
    }

    // ----- ADD and RAND -----

    /// `[+-]\d+(\.\d+)?`, the whole text: "+1", "-5", "+0.5".
    static func isAdd(_ s: String) -> Bool {
        let u = Array(s.utf16)
        guard let first = u.first, first == 0x2B || first == 0x2D else { return false }
        var i = 1
        let digits = { (from: Int) -> Int in
            var j = from
            while j < u.count && u[j] >= 0x30 && u[j] <= 0x39 { j += 1 }
            return j
        }
        let afterWhole = digits(i)
        guard afterWhole > i else { return false }
        i = afterWhole
        if i == u.count { return true }
        guard u[i] == 0x2E else { return false }
        let afterFraction = digits(i + 1)
        return afterFraction > i + 1 && afterFraction == u.count
    }

    /// `rand\(\s*(-?\d+)\s*,\s*(-?\d+)\s*\)`, the whole text: its two numbers' text.
    static func rand(_ s: String) -> (String, String)? {
        let u = Array(s.utf16)
        var i = 0
        func skipSpace() {
            while i < u.count && [0x20, 0x09, 0x0A, 0x0B, 0x0C, 0x0D].contains(u[i]) { i += 1 }
        }
        func expect(_ c: UInt16) -> Bool {
            guard i < u.count, u[i] == c else { return false }
            i += 1
            return true
        }
        func number() -> String? {
            let start = i
            if i < u.count && u[i] == 0x2D { i += 1 }
            let digitsStart = i
            while i < u.count && u[i] >= 0x30 && u[i] <= 0x39 { i += 1 }
            guard i > digitsStart else { return nil }
            return String(decoding: u[start..<i], as: UTF16.self)
        }
        for c in "rand(".utf16 where !expect(c) { return nil }
        skipSpace()
        guard let from = number() else { return nil }
        skipSpace()
        guard expect(0x2C) else { return nil }
        skipSpace()
        guard let to = number() else { return nil }
        skipSpace()
        guard expect(0x29), i == u.count else { return nil }
        return (from, to)
    }
}
