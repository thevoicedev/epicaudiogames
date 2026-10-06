package com.epicaudiogames.engine

/**
 * A condition on the game's variables: any [Expr] (`nana`, `!nana`, `tries >= 2`, `choice == "hide"`,
 * `streak > best && streak >= 2`), true when its value is (a non-zero number, non-empty text, true).
 * Two conditions are equal when their text is.
 */
class Condition private constructor(private val expr: Expr) {
    val source: String get() = expr.source

    fun test(vars: Map<String, Any>): Boolean = expr.test(vars)

    /** The variables the condition reads. */
    val names: Set<String> get() = expr.names

    override fun equals(other: Any?) = other is Condition && other.source == source
    override fun hashCode() = source.hashCode()
    override fun toString() = source

    companion object {
        fun parse(source: String) = Condition(Expr.parse(source))

        fun truthy(v: Any?): Boolean = Expr.truthy(v)
    }
}
