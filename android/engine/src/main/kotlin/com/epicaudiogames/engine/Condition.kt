package com.epicaudiogames.engine

/**
 * A condition on the game's variables: `nana`, `!nana`, `tries >= 2`, `choice == "hide"`, joined with `&&` and `||`
 * (`&&` binds tighter). Two conditions are equal when their text is.
 */
class Condition private constructor(val source: String, private val alternatives: List<List<Atom>>) {
    fun test(vars: Map<String, Any>): Boolean = alternatives.any { all -> all.all { it.test(vars) } }

    /** The variables the condition reads. */
    val names: Set<String> get() = alternatives.flatten().map { it.name }.toSet()

    override fun equals(other: Any?) = other is Condition && other.source == source
    override fun hashCode() = source.hashCode()
    override fun toString() = source

    private class Atom(val not: Boolean, val name: String, val op: String?, val value: Any?) {
        fun test(vars: Map<String, Any>): Boolean {
            val v = vars[name]
            if (op == null) return truthy(v) != not
            if (v is Number && value is Number) {
                val c = v.toDouble().compareTo(value.toDouble())
                return when (op) {
                    "==" -> c == 0
                    "!=" -> c != 0
                    "<" -> c < 0
                    "<=" -> c <= 0
                    ">" -> c > 0
                    else -> c >= 0
                }
            }
            return when (op) {
                "==" -> v == value
                "!=" -> v != value
                else -> {
                    val c = (v?.toString() ?: "").compareTo(value?.toString() ?: "")
                    when (op) {
                        "<" -> c < 0
                        "<=" -> c <= 0
                        ">" -> c > 0
                        else -> c >= 0
                    }
                }
            }
        }
    }

    companion object {
        private val ATOM =
            Regex("""\s*(!?)\s*([A-Za-z_]\w*)\s*(?:(==|!=|<=|>=|<|>)\s*("[^"]*"|-?\d+(?:\.\d+)?|true|false))?\s*""")

        fun parse(source: String): Condition {
            val alternatives = source.split("||").map { alt ->
                alt.split("&&").map { part ->
                    val m = ATOM.matchEntire(part) ?: throw MapException("can't read the condition \"$source\"")
                    val (not, name, op, literal) = m.destructured
                    if (not.isNotEmpty() && op.isNotEmpty()) throw MapException("can't read the condition \"$source\"")
                    Atom(not.isNotEmpty(), name, op.ifEmpty { null }, literal.ifEmpty { null }?.let(::literal))
                }
            }
            return Condition(source, alternatives)
        }

        private fun literal(s: String): Any = when {
            s.startsWith("\"") -> s.substring(1, s.length - 1)
            s == "true" -> true
            s == "false" -> false
            else -> s.toDouble()
        }

        fun truthy(v: Any?): Boolean = when (v) {
            null -> false
            is Boolean -> v
            is Number -> v.toDouble() != 0.0
            is String -> v.isNotEmpty()
            else -> true
        }
    }
}
