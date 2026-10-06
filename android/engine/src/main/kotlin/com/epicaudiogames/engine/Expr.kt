package com.epicaudiogames.engine

import kotlin.math.floor

/**
 * A small expression on the game's variables, for conditions (`nose >= 40 && !won`) and computed values
 * (`streak * 10`, `max(best, streak)`, `streak % 4 == 3`, `a > b ? a : b`).
 *
 * Numbers, "text", true and false; variables (a missing one is 0 in sums, "" in text, false in tests);
 * + - * / %, comparisons, && || !, `cond ? a : b`, parentheses, and max(a, b), min(a, b), floor(a).
 */
class Expr private constructor(val source: String, private val root: Node) {
    fun eval(vars: Map<String, Any>): Any? = root.eval(vars)

    fun test(vars: Map<String, Any>): Boolean = truthy(eval(vars))

    /** The variables it reads. */
    val names: Set<String> get() = mutableSetOf<String>().also { root.collect(it) }

    override fun equals(other: Any?) = other is Expr && other.source == source
    override fun hashCode() = source.hashCode()
    override fun toString() = source

    private sealed interface Node {
        fun eval(vars: Map<String, Any>): Any?
        fun collect(into: MutableSet<String>) = Unit
    }

    private class Lit(val value: Any) : Node {
        override fun eval(vars: Map<String, Any>) = value
    }

    private class Var(val name: String) : Node {
        override fun eval(vars: Map<String, Any>) = vars[name]
        override fun collect(into: MutableSet<String>) {
            into += name
        }
    }

    private class Unary(val op: String, val a: Node) : Node {
        override fun eval(vars: Map<String, Any>): Any = when (op) {
            "!" -> !truthy(a.eval(vars))
            else -> -num(a.eval(vars))
        }
        override fun collect(into: MutableSet<String>) = a.collect(into)
    }

    private class Binary(val op: String, val a: Node, val b: Node) : Node {
        override fun eval(vars: Map<String, Any>): Any? {
            if (op == "&&") return truthy(a.eval(vars)) && truthy(b.eval(vars))
            if (op == "||") return truthy(a.eval(vars)) || truthy(b.eval(vars))
            val x = a.eval(vars)
            val y = b.eval(vars)
            return when (op) {
                "+" -> if (x is String || y is String) text(x) + text(y) else num(x) + num(y)
                "-" -> num(x) - num(y)
                "*" -> num(x) * num(y)
                "/" -> num(x) / num(y)
                "%" -> num(x).mod(num(y))
                "==" -> same(x, y)
                "!=" -> !same(x, y)
                else -> {
                    val c = if (x is String && y is String) x.compareTo(y).toDouble() else num(x) - num(y)
                    when (op) {
                        "<" -> c < 0
                        "<=" -> c <= 0
                        ">" -> c > 0
                        else -> c >= 0
                    }
                }
            }
        }
        override fun collect(into: MutableSet<String>) {
            a.collect(into)
            b.collect(into)
        }
    }

    private class Ternary(val cond: Node, val a: Node, val b: Node) : Node {
        override fun eval(vars: Map<String, Any>) = if (truthy(cond.eval(vars))) a.eval(vars) else b.eval(vars)
        override fun collect(into: MutableSet<String>) {
            cond.collect(into)
            a.collect(into)
            b.collect(into)
        }
    }

    private class Call(val name: String, val args: List<Node>) : Node {
        override fun eval(vars: Map<String, Any>): Any {
            val v = args.map { num(it.eval(vars)) }
            return when (name) {
                "max" -> v.max()
                "min" -> v.min()
                else -> floor(v[0])
            }
        }
        override fun collect(into: MutableSet<String>) = args.forEach { it.collect(into) }
    }

    private class Parser(val src: String) {
        private val tokens = TOKEN.findAll(src).map { it.value }.filter { it.isNotBlank() }.toList()
        private var i = 0

        fun parse(): Node {
            if (TOKEN.findAll(src).joinToString("") { it.value }.filter { !it.isWhitespace() } != src.filter { !it.isWhitespace() }) {
                fail("unexpected characters")
            }
            val n = ternary()
            if (i < tokens.size) fail("unexpected \"${tokens[i]}\"")
            return n
        }

        private fun peek() = tokens.getOrNull(i)
        private fun next() = tokens.getOrNull(i++) ?: fail("it ends too soon")
        private fun expect(t: String) {
            if (next() != t) fail("expected \"$t\"")
        }
        private fun fail(why: String): Nothing = throw MapException("can't read \"$src\": $why")

        private fun ternary(): Node {
            val c = or()
            if (peek() != "?") return c
            next()
            val a = ternary()
            expect(":")
            return Ternary(c, a, ternary())
        }

        private fun or(): Node {
            var n = and()
            while (peek() == "||") { next(); n = Binary("||", n, and()) }
            return n
        }

        private fun and(): Node {
            var n = cmp()
            while (peek() == "&&") { next(); n = Binary("&&", n, cmp()) }
            return n
        }

        private fun cmp(): Node {
            val n = add()
            val op = peek()
            if (op in listOf("==", "!=", "<=", ">=", "<", ">")) {
                next()
                return Binary(op!!, n, add())
            }
            return n
        }

        private fun add(): Node {
            var n = mul()
            while (peek() == "+" || peek() == "-") n = Binary(next(), n, mul())
            return n
        }

        private fun mul(): Node {
            var n = unary()
            while (peek() == "*" || peek() == "/" || peek() == "%") n = Binary(next(), n, unary())
            return n
        }

        private fun unary(): Node = when (peek()) {
            "!" -> { next(); Unary("!", unary()) }
            "-" -> { next(); Unary("-", unary()) }
            else -> primary()
        }

        private fun primary(): Node {
            val t = next()
            return when {
                t == "(" -> ternary().also { expect(")") }
                t.startsWith("\"") -> Lit(t.substring(1, t.length - 1))
                t == "true" -> Lit(true)
                t == "false" -> Lit(false)
                t[0].isDigit() -> Lit(t.toDouble())
                t[0].isLetter() || t[0] == '_' -> if (peek() == "(") {
                    if (t !in setOf("max", "min", "floor")) fail("unknown function \"$t\"")
                    next()
                    val args = mutableListOf(ternary())
                    while (peek() == ",") { next(); args += ternary() }
                    expect(")")
                    Call(t, args)
                } else {
                    Var(t)
                }
                else -> fail("unexpected \"$t\"")
            }
        }
    }

    companion object {
        private val TOKEN = Regex(""""[^"]*"|\d+(?:\.\d+)?|[A-Za-z_]\w*|&&|\|\||==|!=|<=|>=|[-+*/%<>!?:(),]|\s+""")

        fun parse(source: String) = Expr(source, Parser(source).parse())

        fun truthy(v: Any?): Boolean = when (v) {
            null -> false
            is Boolean -> v
            is Number -> v.toDouble() != 0.0
            is String -> v.isNotEmpty()
            else -> true
        }

        fun num(v: Any?): Double = when (v) {
            is Number -> v.toDouble()
            is Boolean -> if (v) 1.0 else 0.0
            is String -> v.toDoubleOrNull() ?: 0.0
            else -> 0.0
        }

        private fun text(v: Any?): String = when (v) {
            null -> ""
            is Double -> if (v == floor(v)) v.toLong().toString() else v.toString()
            else -> v.toString()
        }

        private fun same(x: Any?, y: Any?): Boolean = when {
            x is Number || y is Number -> x !is String && y !is String && num(x) == num(y)
            x == null -> y == null || y == "" || y == false
            y == null -> x == "" || x == false
            else -> x == y
        }

        /** A value as a `by` key: whole numbers without ".0". */
        fun key(v: Any?): String = text(v)
    }
}
