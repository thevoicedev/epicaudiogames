// Expr.kt: a small expression on the game's variables, for conditions and computed values.

/**
 * A small expression on the game's variables, for conditions (`nose >= 40 && !won`) and computed values
 * (`streak * 10`, `max(best, streak)`, `streak % 4 == 3`, `a > b ? a : b`).
 *
 * Numbers, "text", true and false; variables (a missing one is 0 in sums, "" in text, false in tests);
 * + - * / %, comparisons, && || !, `cond ? a : b`, parentheses, and max(a, b), min(a, b), floor(a).
 * Two expressions are equal when their text is.
 */
public final class Expr: Sendable, Hashable, CustomStringConvertible {
    public let source: String
    private let root: ExprNode

    private init(source: String, root: ExprNode) {
        self.source = source
        self.root = root
    }

    public static func parse(_ source: String) throws -> Expr {
        var parser = ExprParser(source)
        return Expr(source: source, root: try parser.parse())
    }

    /// The value, or nil for a missing variable.
    public func eval(_ vars: VarStore) -> Value? { root.eval(vars) }

    public func test(_ vars: VarStore) -> Bool { Expr.truthy(eval(vars)) }

    /// The variables it reads.
    public var names: Set<String> { Set(orderedNames) }

    /// The variables it reads, in the order Kotlin's set holds them (first use first).
    public var orderedNames: [String] {
        var out: [String] = []
        root.collect(into: &out)
        return out.uniqued()
    }

    public static func == (a: Expr, b: Expr) -> Bool { Kt.utf16Equal(a.source, b.source) }
    public func hash(into hasher: inout Hasher) { hasher.combine(source) }
    public var description: String { source }

    // ----- Kotlin's value rules -----

    /// True for true, a non-zero number (NaN too) or non-empty text.
    public static func truthy(_ v: Value?) -> Bool {
        switch v {
        case nil: false
        case .bool(let b): b
        case .number(let d): d != 0
        case .string(let s): !s.isEmpty
        }
    }

    /// A value as a number: true is 1, text is read as Kotlin reads a Double (else 0), missing is 0.
    public static func num(_ v: Value?) -> Double {
        switch v {
        case .number(let d): d
        case .bool(let b): b ? 1 : 0
        case .string(let s): Kt.toDoubleOrNull(s) ?? 0
        case nil: 0
        }
    }

    /// A value as text: whole numbers without ".0" (through Kotlin's saturating toLong), others as Java writes them.
    static func text(_ v: Value?) -> String {
        switch v {
        case nil: ""
        case .number(let d): d == d.rounded(.down) ? String(Kt.saturatingLong(d)) : Kt.doubleString(d)
        case .bool(let b): b ? "true" : "false"
        case .string(let s): s
        }
    }

    /// `==`: "1" isn't 1, true is 1, and missing is "", false and 0.
    static func same(_ x: Value?, _ y: Value?) -> Bool {
        if x?.numberValue != nil || y?.numberValue != nil {
            return x?.stringValue == nil && y?.stringValue == nil && num(x) == num(y)
        }
        guard let x else { return y == nil || y == .string("") || y == .bool(false) }
        guard let y else { return x == .string("") || x == .bool(false) }
        return x == y
    }

    /// A value as a `by` key: whole numbers without ".0".
    public static func key(_ v: Value?) -> String { text(v) }
}

private indirect enum ExprNode: Sendable {
    case lit(Value)
    case variable(String)
    case not(ExprNode)
    case negate(ExprNode)
    case binary(String, ExprNode, ExprNode)
    case ternary(ExprNode, ExprNode, ExprNode)
    case call(String, [ExprNode])

    func eval(_ vars: VarStore) -> Value? {
        switch self {
        case .lit(let v):
            return v
        case .variable(let name):
            return vars[name]
        case .not(let a):
            return .bool(!Expr.truthy(a.eval(vars)))
        case .negate(let a):
            return .number(-Expr.num(a.eval(vars)))
        case .binary(let op, let a, let b):
            if op == "&&" { return .bool(Expr.truthy(a.eval(vars)) && Expr.truthy(b.eval(vars))) }
            if op == "||" { return .bool(Expr.truthy(a.eval(vars)) || Expr.truthy(b.eval(vars))) }
            let x = a.eval(vars)
            let y = b.eval(vars)
            switch op {
            case "+":
                if x?.stringValue != nil || y?.stringValue != nil { return .string(Expr.text(x) + Expr.text(y)) }
                return .number(Expr.num(x) + Expr.num(y))
            case "-": return .number(Expr.num(x) - Expr.num(y))
            case "*": return .number(Expr.num(x) * Expr.num(y))
            case "/": return .number(Expr.num(x) / Expr.num(y))
            case "%": return .number(Kt.floorMod(Expr.num(x), Expr.num(y)))
            case "==": return .bool(Expr.same(x, y))
            case "!=": return .bool(!Expr.same(x, y))
            default:
                let c: Double
                if case .string(let s)? = x, case .string(let t)? = y {
                    c = Double(Kt.compare(s, t))
                } else {
                    c = Expr.num(x) - Expr.num(y)
                }
                switch op {
                case "<": return .bool(c < 0)
                case "<=": return .bool(c <= 0)
                case ">": return .bool(c > 0)
                default: return .bool(c >= 0)
                }
            }
        case .ternary(let cond, let a, let b):
            return Expr.truthy(cond.eval(vars)) ? a.eval(vars) : b.eval(vars)
        case .call(let name, let args):
            let v = args.map { Expr.num($0.eval(vars)) }
            switch name {
            // Kotlin's List<Double>.max()/min(): Math.max/min from the first.
            case "max": return .number(v.dropFirst().reduce(v[0], Kt.max))
            case "min": return .number(v.dropFirst().reduce(v[0], Kt.min))
            default: return .number(v[0].rounded(.down))
            }
        }
    }

    func collect(into out: inout [String]) {
        switch self {
        case .lit: break
        case .variable(let name): out.append(name)
        case .not(let a), .negate(let a): a.collect(into: &out)
        case .binary(_, let a, let b):
            a.collect(into: &out)
            b.collect(into: &out)
        case .ternary(let c, let a, let b):
            c.collect(into: &out)
            a.collect(into: &out)
            b.collect(into: &out)
        case .call(_, let args):
            for a in args { a.collect(into: &out) }
        }
    }
}

/// Expr.kt's Parser. The tokens are what Kotlin's TOKEN regex finds:
/// `"[^"]*"|\d+(?:\.\d+)?|[A-Za-z_]\w*|&&|\|\||==|!=|<=|>=|[-+*/%<>!?:(),]|\s+`, tried in that order at each place,
/// with anything no token matches skipped (and, unless it's whitespace, "unexpected characters").
private struct ExprParser {
    let src: String
    let tokens: [String]
    let skippedText: Bool
    var i = 0

    init(_ src: String) {
        self.src = src
        let u = Array(src.utf16)
        var tokens: [String] = []
        var skippedText = false
        var p = 0
        func isDigit(_ c: UInt16) -> Bool { c >= 0x30 && c <= 0x39 }
        func isLetter(_ c: UInt16) -> Bool { (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c == 0x5F }
        func isSpace(_ c: UInt16) -> Bool { c == 0x20 || (c >= 0x09 && c <= 0x0D) }
        func token(_ from: Int, _ to: Int) { tokens.append(String(decoding: u[from..<to], as: UTF16.self)) }
        while p < u.count {
            let c = u[p]
            if c == 0x22, let close = u[(p + 1)...].firstIndex(of: 0x22) {
                token(p, close + 1)
                p = close + 1
            } else if isDigit(c) {
                var q = p + 1
                while q < u.count && isDigit(u[q]) { q += 1 }
                if q + 1 < u.count && u[q] == 0x2E && isDigit(u[q + 1]) {
                    q += 2
                    while q < u.count && isDigit(u[q]) { q += 1 }
                }
                token(p, q)
                p = q
            } else if isLetter(c) {
                var q = p + 1
                while q < u.count && (isLetter(u[q]) || isDigit(u[q])) { q += 1 }
                token(p, q)
                p = q
            } else if p + 1 < u.count, ["&&", "||", "==", "!=", "<=", ">="].contains(where: {
                Array($0.utf16) == [c, u[p + 1]]
            }) {
                token(p, p + 2)
                p += 2
            } else if Array("-+*/%<>!?:(),".utf16).contains(c) {
                token(p, p + 1)
                p += 1
            } else if isSpace(c) {
                // Whitespace runs are tokens too, then dropped as blank.
                while p < u.count && isSpace(u[p]) { p += 1 }
            } else {
                if !Kt.isWhitespace(c) { skippedText = true }
                p += 1
            }
        }
        self.tokens = tokens
        self.skippedText = skippedText
    }

    mutating func parse() throws -> ExprNode {
        if skippedText { throw fail("unexpected characters") }
        let n = try ternary()
        if i < tokens.count { throw fail("unexpected \"\(tokens[i])\"") }
        return n
    }

    private func peek() -> String? { i < tokens.count ? tokens[i] : nil }

    private mutating func next() throws -> String {
        guard i < tokens.count else {
            i += 1
            throw fail("it ends too soon")
        }
        defer { i += 1 }
        return tokens[i]
    }

    private mutating func expect(_ t: String) throws {
        if try next() != t { throw fail("expected \"\(t)\"") }
    }

    private func fail(_ why: String) -> MapError { MapError("can't read \"\(src)\": \(why)") }

    private mutating func ternary() throws -> ExprNode {
        let c = try or()
        if peek() != "?" { return c }
        _ = try next()
        let a = try ternary()
        try expect(":")
        return .ternary(c, a, try ternary())
    }

    private mutating func or() throws -> ExprNode {
        var n = try and()
        while peek() == "||" {
            _ = try next()
            n = .binary("||", n, try and())
        }
        return n
    }

    private mutating func and() throws -> ExprNode {
        var n = try cmp()
        while peek() == "&&" {
            _ = try next()
            n = .binary("&&", n, try cmp())
        }
        return n
    }

    private mutating func cmp() throws -> ExprNode {
        let n = try add()
        if let op = peek(), ["==", "!=", "<=", ">=", "<", ">"].contains(op) {
            _ = try next()
            return .binary(op, n, try add())
        }
        return n
    }

    private mutating func add() throws -> ExprNode {
        var n = try mul()
        while peek() == "+" || peek() == "-" {
            let op = try next()
            n = .binary(op, n, try mul())
        }
        return n
    }

    private mutating func mul() throws -> ExprNode {
        var n = try unary()
        while peek() == "*" || peek() == "/" || peek() == "%" {
            let op = try next()
            n = .binary(op, n, try unary())
        }
        return n
    }

    private mutating func unary() throws -> ExprNode {
        switch peek() {
        case "!":
            _ = try next()
            return .not(try unary())
        case "-":
            _ = try next()
            return .negate(try unary())
        default:
            return try primary()
        }
    }

    private mutating func primary() throws -> ExprNode {
        let t = try next()
        let first = t.utf16.first!
        if t == "(" {
            let n = try ternary()
            try expect(")")
            return n
        }
        if first == 0x22 { return .lit(.string(String(decoding: Array(t.utf16).dropFirst().dropLast(), as: UTF16.self))) }
        if t == "true" { return .lit(.bool(true)) }
        if t == "false" { return .lit(.bool(false)) }
        if first >= 0x30 && first <= 0x39 { return .lit(.number(Double(t)!)) }
        if (first >= 0x41 && first <= 0x5A) || (first >= 0x61 && first <= 0x7A) || first == 0x5F {
            guard peek() == "(" else { return .variable(t) }
            if !["max", "min", "floor"].contains(t) { throw fail("unknown function \"\(t)\"") }
            _ = try next()
            var args = [try ternary()]
            while peek() == "," {
                _ = try next()
                args.append(try ternary())
            }
            try expect(")")
            return .call(t, args)
        }
        throw fail("unexpected \"\(t)\"")
    }
}
