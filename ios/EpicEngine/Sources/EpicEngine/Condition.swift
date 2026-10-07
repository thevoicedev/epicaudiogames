// Condition.kt: a condition on the game's variables, true when its expression's value is.

/**
 * A condition on the game's variables: any [Expr] (`nana`, `!nana`, `tries >= 2`, `choice == "hide"`,
 * `streak > best && streak >= 2`), true when its value is (a non-zero number, non-empty text, true).
 * Two conditions are equal when their text is.
 */
public struct Condition: Hashable, Sendable, CustomStringConvertible {
    private let expr: Expr

    public static func parse(_ source: String) throws -> Condition { Condition(expr: try Expr.parse(source)) }

    public var source: String { expr.source }

    public func test(_ vars: VarStore) -> Bool { expr.test(vars) }

    /// The variables the condition reads.
    public var names: Set<String> { expr.names }

    public var orderedNames: [String] { expr.orderedNames }

    public var description: String { source }

    public static func truthy(_ v: Value?) -> Bool { Expr.truthy(v) }
}
