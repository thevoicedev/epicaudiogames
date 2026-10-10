package com.epicaudiogames.app

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.io.File
import kotlin.math.abs

/**
 * The earcons as the app reads them ([Wav.pcm16Mono], for Earcons' tracks): the committed ones in content/app/earcons
 * (what tools/app_audio.py makes: 16-bit mono, 48 kHz, starting at once and ending at silence), and WAVs with the
 * extra chunks a sound editor adds, which are stepped over.
 */
class WavTest {
    private val earcons = File(System.getProperty("content.dir") ?: "../../content", "app/earcons")

    @Test
    fun theCommittedEarconsRead() {
        // Their lengths as docs/DESIGN.md and tools/app_audio.py have them: start about 150 ms, stop a little
        // shorter, success about a quarter of a second.
        val lengths = mapOf(
            Earcon.LISTEN_START to 140L..150L,
            Earcon.LISTEN_STOP to 110L..125L,
            Earcon.SUCCESS to 220L..250L,
        )
        for (earcon in Earcon.entries) {
            val file = File(earcons, "${earcon.file}.wav")
            assertTrue("$file is missing", file.isFile)
            val pcm = Wav.pcm16Mono(file.readBytes())
            assertNotNull("${earcon.file} isn't a 16-bit mono WAV", pcm)
            pcm!!
            assertEquals(earcon.file, 48_000, pcm.rate)
            assertTrue("${earcon.file} is ${pcm.millis} ms", pcm.millis in lengths.getValue(earcon))
            // It starts at once (no silence before it, so it's heard as the mic opens) and fades to nothing.
            val firstSound = pcm.samples.indexOfFirst { it.toInt() != 0 }
            assertTrue("${earcon.file} starts after $firstSound samples", firstSound in 0..48)
            assertEquals("${earcon.file} ends at silence", 0, pcm.samples.last().toInt())
            // Loud enough to hear, never clipped: its peak at about -3 dBFS.
            val peak = pcm.samples.maxOf { abs(it.toInt()) }
            assertTrue("${earcon.file} peaks at $peak", peak in 16_000..23_300)
        }
    }

    @Test
    fun extraChunksAreSteppedOver() {
        val samples = shortArrayOf(0, 100, -100, 32767, -32768, 1)
        val plain = wav(samples)
        val extra = wav(
            samples,
            before = listOf(chunk("LIST", "INFOISFT".toByteArray() + ByteArray(7))),      // an odd size: padded
            between = listOf(chunk("fact", ByteArray(4)), chunk("JUNK", ByteArray(28))),
        )
        assertArrayEquals(samples, Wav.pcm16Mono(plain)!!.samples)
        val read = Wav.pcm16Mono(extra)
        assertNotNull(read)
        assertArrayEquals(samples, read!!.samples)
        assertEquals(48_000, read.rate)
    }

    @Test
    fun theCommittedEarconsReadTheSameWithChunksAdded() {
        val bytes = File(earcons, "listen-start.wav").readBytes()
        val pcm = Wav.pcm16Mono(bytes)!!
        val padded = wav(pcm.samples, rate = pcm.rate, before = listOf(chunk("LIST", ByteArray(26))),
            between = listOf(chunk("cue ", ByteArray(5))))
        assertArrayEquals(pcm.samples, Wav.pcm16Mono(padded)!!.samples)
    }

    @Test
    fun theExtensibleFormatWithPcmInsideReads() {
        val samples = shortArrayOf(5, -5, 7)
        val bytes = wav(samples, fmt = extensibleFmt(subFormat = 1))
        assertArrayEquals(samples, Wav.pcm16Mono(bytes)!!.samples)
        // Float inside: not a sound the tracks take.
        assertNull(Wav.pcm16Mono(wav(samples, fmt = extensibleFmt(subFormat = 3))))
    }

    @Test
    fun aSoundThatClaimsMoreThanItHasIsReadAsFarAsItGoes() {
        val samples = shortArrayOf(1, 2, 3, 4)
        val whole = wav(samples)
        // The last sample and a half cut off (the half sample goes too); the header still says four.
        val cut = whole.copyOf(whole.size - 3)
        assertArrayEquals(shortArrayOf(1, 2), Wav.pcm16Mono(cut)!!.samples)
    }

    @Test
    fun otherFormatsAreNotRead() {
        val samples = shortArrayOf(1, 2)
        assertNull("stereo", Wav.pcm16Mono(wav(samples, fmt = fmt(channels = 2))))
        assertNull("8-bit", Wav.pcm16Mono(wav(samples, fmt = fmt(bits = 8))))
        assertNull("float", Wav.pcm16Mono(wav(samples, fmt = fmt(codec = 3, bits = 32))))
        assertNull("no format", Wav.pcm16Mono(riff(chunk("data", le16(1) + le16(2)))))
        assertNull("the sound before its format", Wav.pcm16Mono(riff(chunk("data", le16(1)), fmt())))
        assertNull("not a WAV", Wav.pcm16Mono("RIFX\u0000\u0000\u0000\u0000WAVE".toByteArray()))
        assertNull("too short", Wav.pcm16Mono(ByteArray(8)))
        assertNull("no sound", Wav.pcm16Mono(riff(fmt())))
    }

    // ----- Making WAVs -----

    private fun wav(
        samples: ShortArray,
        rate: Int = 48_000,
        fmt: ByteArray = fmt(rate = rate),
        before: List<ByteArray> = emptyList(),
        between: List<ByteArray> = emptyList(),
    ): ByteArray {
        val data = ByteArrayOutputStream()
        for (s in samples) data.write(le16(s.toInt()))
        return riff(*(before + listOf(fmt) + between + listOf(chunk("data", data.toByteArray()))).toTypedArray())
    }

    private fun riff(vararg chunks: ByteArray): ByteArray {
        val body = chunks.fold("WAVE".toByteArray()) { all, c -> all + c }
        return "RIFF".toByteArray() + le32(body.size) + body
    }

    /** A chunk, padded to an even length as RIFF has it. */
    private fun chunk(id: String, body: ByteArray): ByteArray =
        id.toByteArray() + le32(body.size) + body + (if (body.size % 2 == 1) byteArrayOf(0) else byteArrayOf())

    private fun fmt(codec: Int = 1, channels: Int = 1, rate: Int = 48_000, bits: Int = 16): ByteArray {
        val align = channels * bits / 8
        return chunk("fmt ", le16(codec) + le16(channels) + le32(rate) + le32(rate * align) + le16(align) + le16(bits))
    }

    /** WAVE_FORMAT_EXTENSIBLE, 16-bit mono, with [subFormat] as its GUID's first two bytes (1 PCM, 3 float). */
    private fun extensibleFmt(subFormat: Int): ByteArray {
        val guidRest = byteArrayOf(0, 0, 0, 0, 0x10, 0, 0x80.toByte(), 0, 0, 0xAA.toByte(), 0, 0x38, 0x9B.toByte(), 0x71)
        return chunk(
            "fmt ",
            le16(0xFFFE) + le16(1) + le32(48_000) + le32(96_000) + le16(2) + le16(16) +
                le16(22) + le16(16) + le32(4) + le16(subFormat) + guidRest,
        )
    }

    private fun le16(v: Int) = byteArrayOf(v.toByte(), (v shr 8).toByte())

    private fun le32(v: Int) = byteArrayOf(v.toByte(), (v shr 8).toByte(), (v shr 16).toByte(), (v shr 24).toByte())
}
