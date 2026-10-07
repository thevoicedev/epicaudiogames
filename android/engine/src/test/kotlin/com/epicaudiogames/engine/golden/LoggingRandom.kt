package com.epicaudiogames.engine.golden

import kotlin.random.Random

/**
 * A Random that hands every call on to [inner] and logs it, at the outermost call only, as README section 7.2 writes
 * draws: ["nextInt", r], ["nextInt", until, r], ["nextInt", from, until, r], ["nextBits", bitCount, r],
 * ["nextDouble", d], ["nextBoolean", b]. The engine must make no other kind of call: the fixtures can't replay it.
 */
class LoggingRandom(private val inner: Random) : Random() {
    private val log = mutableListOf<List<Any>>()

    /** The draws since the last call, and a fresh log. */
    fun take(): List<List<Any>> = log.toList().also { log.clear() }

    override fun nextBits(bitCount: Int): Int = inner.nextBits(bitCount).also { log += listOf("nextBits", bitCount, it) }

    override fun nextInt(): Int = inner.nextInt().also { log += listOf("nextInt", it) }

    override fun nextInt(until: Int): Int = inner.nextInt(until).also { log += listOf("nextInt", until, it) }

    override fun nextInt(from: Int, until: Int): Int = inner.nextInt(from, until).also { log += listOf("nextInt", from, until, it) }

    override fun nextDouble(): Double = inner.nextDouble().also { log += listOf("nextDouble", it) }

    override fun nextBoolean(): Boolean = inner.nextBoolean().also { log += listOf("nextBoolean", it) }

    override fun nextLong(): Long = unsupported("nextLong()")
    override fun nextLong(until: Long): Long = unsupported("nextLong(until)")
    override fun nextLong(from: Long, until: Long): Long = unsupported("nextLong(from, until)")
    override fun nextDouble(until: Double): Double = unsupported("nextDouble(until)")
    override fun nextDouble(from: Double, until: Double): Double = unsupported("nextDouble(from, until)")
    override fun nextFloat(): Float = unsupported("nextFloat()")
    override fun nextBytes(array: ByteArray, fromIndex: Int, toIndex: Int): ByteArray = unsupported("nextBytes")
    override fun nextBytes(array: ByteArray): ByteArray = unsupported("nextBytes")
    override fun nextBytes(size: Int): ByteArray = unsupported("nextBytes")

    private fun unsupported(call: String): Nothing =
        throw UnsupportedOperationException("Random.$call isn't in the fixture format (fixtures/engine/README.md, 7.2)")
}

/** A Session's chooser, `rng.nextInt(n)`, logging each call as [n, r]. */
class LoggingChooser(private val rng: Random) : (Int) -> Int {
    private val log = mutableListOf<List<Int>>()

    fun take(): List<List<Int>> = log.toList().also { log.clear() }

    override fun invoke(n: Int): Int = rng.nextInt(n).also { log += listOf(n, it) }
}
