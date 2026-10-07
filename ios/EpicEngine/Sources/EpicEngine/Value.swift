// The engine's variable values: the Boolean, Double or String a Kotlin Map<String, Any> holds (GameMap.kt, Session.kt).

/**
 * A variable's value. Numbers are always Doubles, as JSON numbers are in the Kotlin engine. Equality is Kotlin's
 * boxed equality: a Double equals itself bit for bit (NaN equals NaN, 0.0 doesn't equal -0.0), and text compares
 * UTF-16 unit by unit.
 */
public enum Value: Sendable {
    case bool(Bool)
    case number(Double)
    case string(String)

    /// Kotlin's toString: "true", Java's Double.toString ("1.0"), or the text itself.
    public var kotlinString: String {
        switch self {
        case .bool(let b): b ? "true" : "false"
        case .number(let d): Kt.doubleString(d)
        case .string(let s): s
        }
    }

    public var boolValue: Bool? { if case .bool(let b) = self { b } else { nil } }
    public var numberValue: Double? { if case .number(let d) = self { d } else { nil } }
    public var stringValue: String? { if case .string(let s) = self { s } else { nil } }
}

extension Value: Hashable {
    public static func == (a: Value, b: Value) -> Bool {
        switch (a, b) {
        case let (.bool(x), .bool(y)): x == y
        case let (.number(x), .number(y)): x.bitPattern == y.bitPattern || (x.isNaN && y.isNaN)
        case let (.string(x), .string(y)): Kt.utf16Equal(x, y)
        default: false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .bool(let b):
            hasher.combine(0)
            hasher.combine(b)
        case .number(let d):
            hasher.combine(1)
            hasher.combine(d.isNaN ? Double.nan.bitPattern : d.bitPattern)
        case .string(let s):
            hasher.combine(2)
            hasher.combine(s)
        }
    }
}

extension Value: CustomStringConvertible {
    public var description: String { kotlinString }
}

extension Value: ExpressibleByBooleanLiteral, ExpressibleByFloatLiteral, ExpressibleByIntegerLiteral,
    ExpressibleByStringLiteral {
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(floatLiteral value: Double) { self = .number(value) }
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
    public init(stringLiteral value: String) { self = .string(value) }
}

/// A game's variables, in the order they were first set (Kotlin's LinkedHashMap).
public typealias VarStore = LinkedMap<Value>

extension LinkedMap where V == EpicEngine.Value {
    /// Kotlin's Map.toString: "{n=1.0, mode=x}".
    public var kotlinDescription: String {
        "{" + map { "\($0.key)=\($0.value.kotlinString)" }.joined(separator: ", ") + "}"
    }
}
