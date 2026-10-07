// No Kotlin counterpart (ExoPlayer decodes on Android): every codec the content uses decodes to the length it plays.

import AVFoundation
import EpicAppCore
import Foundation
import Testing
@testable import EpicAudioGames

/**
 * The clips decode to the lengths the turns are laid out with. A 0.3 s clip in each codec and rate the content uses
 * (made by ffmpeg as tools/content.py makes them: a quiet 300 Hz tone with a click at 0.1 s) must come out exactly
 * 0.3 s at 48 kHz with the click where it was, as ExoPlayer plays them (gapless). Then every clip of the bundled
 * content (placeholders until content/ is copied in) must decode within 0.12 s of its map's "dur", as
 * tools/validate.py checks the files.
 */
struct DecodeTests {
    /// ffmpeg 8.1.1: libmp3lame, aac with -movflags +faststart, libopus -application audio; mono, -fflags +bitexact.
    static let clips: [String: String] = [
        "click24000.mp3": """
        SUQzBAAAAAAACgAAAAAAAAAAAAD/84TAAAAAAAAAAAAASW5mbwAAAA8AAAAPAAADkABDQ0NDQ0NQUFBQUFBQXl5eXl5ea2tra2tra3l5eXl5
        eXmGhoaGhoaUlJSUlJSUoaGhoaGhoa+vr6+vr7y8vLy8vLzKysrKysrK19fX19fX5eXl5eXl5fLy8vLy8vL///////8AAAAATGF2ZiBsYW1l
        AAAAAAAAAAAAAAAAJANgAAAAAAAAA5Bpqt0pAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/8yTEAAcQSnAAw9JBVOu9d6p1hyz5fY7cA4CnH2OM
        NisnRo2wAAAABVVAtyWxCEL/8yTEBgcYJr2gCFgDEPQH3RqYKCgkFBQUFCgo4KCQUFBQWEqRPItcvQBnz2YMOMT/8yTEDAhgSjQAz7Qh9Nyc
        NAwuQOTSxTTOTGGFg4Im7lfBWiOPG4Ia47gVCpisdmf/8yTEDQkwRkxhXAACnqmPa8ZeAxCEiJAGKgIgAeSnp7dvV/eu/D8tUIs2CRpcQQD/
        8yTECwiANqwBmBAAkb+V6PuR+79F39CHGP+aMhgCO/+kMASBaCCCCCCCAABzPFf/8yTEDArQLumVhxAAG0Mkj9ID5oP+CYEP+XBMSH/rBMSB
        f+CYkC4jb/qFxWrcpjP/8yTEAwYIPmAB2wADZL7GEiRnOAfTMhgypUHD4YBNei3zVWhI0A4XMeBjQx05hWP/8yTEDQoYThwA37YhITLTP7se
        oxtwnTcbk3afM+VguIpuN3gibpLCyhsBKZI9bCD/8yTEBwhoQkgYzzIidBFKAL7zOM+MCiEFDlOBSo1eTX+Gv//+mz9Fd1xmSpJA5U7/8yTE
        CAfQQjQAz7Ih9ow1BxTbkEYGhSDGyObg6F0hmsxqlK6VuQ2yhOcECGfeYzT/8yTECwdgQkAAz3QhHHwSrmKwZGUOHBFAa2wSL2MwNYAppTEn
        RWCC0TENIPds8wf/8yTEEAawPlBAxzAjgJlILuJqdWXWRnWGoxYg0GgEAgcxWGz35KAQjZGEAFpEORj/8yTEGAaAOlwhXAADcft1Mi2jQUCg
        YAAAUyyRokMerZnVUgDBBcW/cJzXA0+xnwb/8yTEIQwIiqJZmTgAgUB2v5cgTf4JgQ/8HD4Jqgx4AWCwamQgiSpCpDEVk9kFYG7/8yTEEwdQ
        LbjRyRABPTcnmzed//k90WpMQU1FMy4xMDCqqqqqqqqqqqqqqqqqqqo=
        """,
        "click44100.mp3": """
        SUQzBAAAAAAACgAAAAAAAAAAAAD/+0DAAAAAAAAAAAAAAAAAAAAAAABJbmZvAAAADwAAAA0AAAYEAC8vLy8vLy9AQEBAQEBAQFJSUlJSUlJS
        Y2NjY2NjY3V1dXV1dXV1hoaGhoaGhoaXl5eXl5eXqampqampqam6urq6urq6usvLy8vLy8vd3d3d3d3d3e7u7u7u7u7u/////////wAAAABM
        YXZmIGxhbWUAAAAAAAAAAAAAAAAkBJIAAAAAAAAGBJ/NRBMAAAAAAP/7EMQAAEP8D0+jJYA4j4Vmgc0wSQAASm5IAAAAAwGGwcAIWFgAHh54
        ekAAARgHh4eHpAAQtJBMYJCgNhR9CJkAaYKxQIiEIxOMj5cuXLmXagoKChQUFBRVAAAI3GGFkAEwwMCAcYs0//sSxAeCBKAXJa70wnCTA2KJ
        32BG4cMBgDgTXQ74AIJhnyXp/2/6en0f6TDoBM0SB8xABo2B2w3qASDBpABDaBx0wGsPvKM//7P//p9Hb6WAAAAA4pxPjiDB5gUUyJ9QhOnS
        CKzCuQII//sQxAyCBVAa+m3/gGCpg2K1j2AO4cIyiHmPAkYEDRYCKCJ9fb7QJBW40wAYjm3BgYAzmJa9mbBgYZgmgRG4KV0CzUZl2Pk/b2ej
        t/2ezt8mAAAAGAAAoABijZi4BgQBrmGnz6aLQw7/+xLEC4IFSBsPrXsAYKUDZDa8AAZgXgtGD4yRebzubCr3p/////s6QMAKAIAAWrMAkC0w
        aQgTAyQ9CBQwAAaYEICJcdS9w3fh/vs/0f//+R6aJomCQXkyCn3Lhty4aeBgcvOAEKhvIfD/+xDEC4AHUPFiGNEAAIyCq/eeAAYigID+dyEM
        BARS/kAwMWAAAVHSn8QBnOIIxlKUwYC/7/5QEBpE2AAG1tAADaX1hHyU0ZHcvqiH//EXEp3g1BqVOlQCoGlA1Ta6mOuLkwuMGSMzuf/7EsQG
        AgW4HPQOf4BAmoMidY9gDIRj+iQqIxB4CjPSigDbQzeMzDI7FBQKAtkWur/X9///36gOABgKAAaVHLpgfg4GLVCobnIahgwATncSA17o7DUt
        PdX/+////Uo0qyjTFpMEHDzDEf/7EMQFggSUGvgOf2BgqINh9Z90Bru/A1ZEagMFYBzzc9YxxrBhUJEgcfCQys5IEYjcSAAAqQ5+AA2DCF7C
        O+mOMGRdAgQBUCS/i6Gbwi/5L09Pt7PT/kuiCh4NLz8wawOsMgX7Cjnb//sSxAeDxZQa9g5/gEC6A56Bz/AIBoQwo8HNOEOI0yizNBkMdDYx
        aFwMHFY09v////9AdCTlafMK0CSDMa5kY/CYQuMP1BJTzSYNwm80MZjHhIMPiswEClh99f+r///7tdU4RdPjXjB7//sQxAOCBLga+g3/gGCb
        guO0/3QGAMcyMsxROqoBSzCxwEIBi00aATIgeMFCARhNDs8PtAuGg0EAAOUAHGAoBSYW6BZ+8LZhOAhelp1FcpQ55P29n+329n/8mgBY2AET
        QugwAgQTBhX/+xLEBoMEWBkcbHugMIsDY42PbAaROPiHMCwQR5dKhvztp3///X/q9X+uyiOABSkhQQgjmAgvWeHIiAUR3Zg7cvnL/P+jo9n+
        js/0+SoAAADAagWQASVeANBUxGvk+COwMBF3v4AyaB//+xDEDYLEiBclrvDCcHQC5FD+vA72ejo//o6PT/oIoC2OAwHAUyAg07bCEMCwQMyF
        GxvAc9no7f/6OioAAACgaDRsAMGS5Eio76iB0BxECqCPKRC2OA32ezt/2f7fT2ehgKSW22yMxP/7EsQWAESYFx+t+eIxCIsptYSZJ2MxmUBa
        A+t/2Xu+rtdAYMWujBMEwNgYBAEAQBAUCgkIJ32IEAQABADAYDAZMmTTHfmHh4AAAH//wBAfZCCGmGBBsc0cqrGBgZfkvagBS+TCVMsZd//7
        EMQMg8dIRyYMbMGoAAA0gAAABDOnKd5/gCRn0cSJEiJEiRIkSJEGfFBQUKCgoK/8goKBQVVMQU1FMy4xMDBVVVVVVVVVVVVVVVVVVVVVVVVV
        VVVVVVVVVVVVVVVVVVVVVVVVVVVV
        """,
        "click24000.m4a": """
        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
        """,
        "click44100.m4a": """
        AAAAHGZ0eXBNNEEgAAACAE00QSBpc29taXNvMgAAAw5tb292AAAAbG12aGQAAAAAAAAAAAAAAAAAAAPoAAABLAABAAABAAAAAAAAAAAAAAAA
        AQAAAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACAAACXXRyYWsAAABcdGtoZAAA
        AAMAAAAAAAAAAAAAAAEAAAAAAAABLAAAAAAAAAAAAAAAAQEAAAAAAQAAAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAA
        AAAAACRlZHRzAAAAHGVsc3QAAAAAAAAAAQAAASwAAAQAAAEAAAAAAdVtZGlhAAAAIG1kaGQAAAAAAAAAAAAAAAAAAKxEAAA3rlXEAAAAAAAt
        aGRscgAAAAAAAAAAc291bgAAAAAAAAAAAAAAAFNvdW5kSGFuZGxlcgAAAAGAbWluZgAAABBzbWhkAAAAAAAAAAAAAAAkZGluZgAAABxkcmVm
        AAAAAAAAAAEAAAAMdXJsIAAAAAEAAAFEc3RibAAAAGpzdHNkAAAAAAAAAAEAAABabXA0YQAAAAAAAAABAAAAAAAAAAAAAQAQAAAAAKxEAAAA
        AAA2ZXNkcwAAAAADgICAJQABAASAgIAXQBUAAAAAAG6CAABuggWAgIAFEghW5QAGgICAAQIAAAAgc3R0cwAAAAAAAAACAAAADQAABAAAAAAB
        AAADrgAAABxzdHNjAAAAAAAAAAEAAAABAAAADgAAAAEAAABMc3RzegAAAAAAAAAAAAAADgAAAGMAAABOAAAAUwAAAFcAAABiAAAASwAAAGMA
        AABGAAAAYwAAAEAAAABSAAAARwAAADwAAABOAAAAFHN0Y28AAAAAAAAAAQAAAzoAAAAac2dwZAEAAAByb2xsAAAAAgAAAAH//wAAABxzYmdw
        AAAAAHJvbGwAAAABAAAADgAAAAEAAAA9dWR0YQAAADVtZXRhAAAAAAAAACFoZGxyAAAAAAAAAABtZGlyYXBwbAAAAAAAAAAAAAAAAAhpbHN0
        AAAACGZyZWUAAAR/bWRhdAEoLykJPQkJvnb2q+Zd3IkkkkkjskHVuq4raZ7afP9gamp1sZNGTQMDAwMDAwMDAwMDAwMDAxsGNym5ZZZZZZZZ
        ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZYoooooiiiiiiiii4ADeLCzoUmH/9z5/n/5rI8zki5JcDSXbt1AyaVnXJ6jjSoigWHMmg2NBUzNt36T9
        J+k/SXnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnuADmLKzk5hEJv/+76/2/+98qkiRck9p4CMrBpbPJvv53Henson5XKU2sUKXnnnnnnnnn
        nnnnnnnnnnnnnnnnnrLrLrLrLrLrLrLrLnnnnnnnnnnuASZPKYjdKrv9vv9+tePOlLq5lxLjntYYvO877Hi/1/2zFYUWBQ4Hs+LNm25YQjRo
        0aGAI/n/x8/AAABiMPDz8AAAKtDw9uwAAFOHh63AABVoeHrsAABXATCRsojxRHiyl1WUupPv1rXGv/rnUqU1/cIK/2z461r/9+h+dh8LqeYa
        khBDzoedD+ZB/Pzh/P+Yfz/n+I/fnqpXvpGw/Y/A3h7dQavzDXr/P2KS6LllREpPZMLRUJCQkrwBNu8RpL0pBePf7fv9e3t3PavOSLlpLbtr
        fA4qCgtfRWijo0FBQWwKCtFW+/voGT4bGf30B/4zB330A/xmCfeEP/GYJd9/cH+PgcABAi6Trx//d/b/P/6ff8bJIiSSSkQLbtua222xYGBg
        YGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGRugYGBgYGBgYGRu3bt27wBAC6TGleP/7v7fz/+
        X19KhJEiSHMiC0XbXW22sWBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGB8APwuk69//7n8fv/+X18XUiEkktUiBHHb
        XW2tcYGBgYGBgYGBgYGBgcoGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGBgYGByy8AP4ukxpX
        v//F/b9//z+vjVEkSRJI50QY424rWteMsssssssssssssspmWUDMyyyyyyygYGZlAwMDAwMDAwMD4AEALhOPX/4f9v3//L6+NVJIS4kipAll
        txWta8ZZZZZZZZZZZZZZZQMDAwMDAwMzKBgYGBgYGBgYGBgYGBgYGByyyyyyyyyyyyyyyyyyyyyyyy8BAi2Lbx/f/+L9//y+PjikiRJJcqQI
        okIMYxkRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRcAEaLwsaZX/H/T9//vriXOEkaWuRupEHGI6DUUdU8Xc9
        r6Z6otLKJ1RE9RXPFE8s06ItLKJ6osWLPPF3cAFMLwsaEhaIgpz9vxxxd3LuS5JEkbly5wOb13ZI6Od6L5T0fR7llnXuecy8zVHO5FzT0c70
        U09EDyIp10PMinUqiBiCnWZ4FRueRFOujg==
        """,
        "click48000.opus": """
        T2dnUwACAAAAAAAAAAAAAAAAAAAAAAIotXIBE09wdXNIZWFkAQE4AYC7AAAAAABPZ2dTAAAAAAAAAAAAAAAAAAABAAAASZW+VAEuT3B1c1Rh
        Z3MGAAAAZmZtcGVnAQAAABQAAABlbmNvZGVyPUxhdmMgbGlib3B1c09nZ1MABHg5AAAAAAAAAAAAAAIAAABV3bSiEDYnNC4qFRosLy8oJx8i
        LRBIgPWhp/47gugDks9RiplBH3vuQxDts/QbTsfX3yZaNWMp/YNTgStMH/PcOH9LDAgUhsw0DjZIn2bB5mIDb5Qu9l6pzhV/2/GhARcgu6qp
        rCKut6SiqyWnf44iB0VImQz3gR4PyG64t3fMVoBqvyhTTDhUDnL7y5U/PD4H//V8yBDBPoJ6nymTiXrTiOJcP/xASJkM94KpaRlDOgst/25d
        4uZUhO6buI8aeLBBy1t3xWuDuAdTCinWMwWas/ugeEiZDPeBHg/QQUXi8wkF3XMo0hcfRfF5cnbsz2/gp9mnJ8w83CpfFcl7L0i5+CyiSsDf
        yZN+4j9czUTKC5uXcEivlsFMjD5YvVyCp+SH+prG9drGflH2DXaASJttuO6hhB9b0OixzWFOG34/oSrZTdSgG0zxQ2jKkeEDeULq1bXfbZcs
        80BImTdJxXxHt9YdUhH/maisKLZ4Hz62vTri2DIlYoAJuFrOhpEZ75LIBv9VIX6+4EiZDPeBHg/QAvXnvjTxpdcmPOy2QTuchBpCv5Rps9Ad
        +pDFuvX/IsC9+vDQBkCASJkOkEEKoRCxhjF+7JcQBch+ISWc+jyal+wOslP/qnpMIqY1MoLFwEiZT0vHe550o7shbOdG9Fnib+EBVC9kTUb8
        Ka7CU3ovrcUyrrUZdEiZT0vHe56oDkK3UpZ5N6S+Fyl1GTlHRmgZQ5Z1oa5ImU9Lx3uYOscf5WDt/TZ+ceeSVfs1OouwALezv2uImlfDSJlP
        S8d7nnSLiAZEESpTBeIlcZp2pBHB3247FIANCEs8gAG2rQw3hjjhWtFwSAVSraPLK4tkMz8Ozphm4A==
        """,
    ]

    static let clipFrames: Int64 = 14_400     // 0.3 s at 48 kHz
    static let clickFrame = 4_800             // 0.1 s

    @Test(arguments: ["click24000.mp3", "click44100.mp3", "click24000.m4a", "click44100.m4a", "click48000.opus"])
    func aClipDecodesToItsLengthWithItsClickInPlace(_ name: String) throws {
        let folder = try AudioScratch()
        let url = try folder.write(name, base64: #require(Self.clips[name]))
        let source = try ClipDecoder.open(url)
        #expect(source.frames == Self.clipFrames, "\(name): \(source)")
        let buffer = try ClipDecoder.decode(source)
        #expect(Int64(buffer.frameLength) == Self.clipFrames)
        let samples = Self.samples(buffer)
        let click = samples.indices.max { abs(samples[$0]) < abs(samples[$1]) }!
        // Within a millisecond (lossy codecs move a click's peak by a sample or two).
        #expect(abs(click - Self.clickFrame) <= 48, "\(name): the click is at \(click), not \(Self.clickFrame)")
        #expect(samples.contains { abs($0) > 0.02 }, "\(name): silent")
    }

    /// AVAudioFile keeps an MP3's LAME encoder delay and padding (iOS 26.3: 576 frames late, and longer); ExoPlayer
    /// drops them, and so does ClipDecoder.
    @Test func mp3GaplessInfoIsReadAsExoPlayerReadsIt() throws {
        let folder = try AudioScratch()
        let mp3 = try folder.write("click24000.mp3", base64: #require(Self.clips["click24000.mp3"]))
        let gapless = try #require(Mp3Gapless.read(mp3))
        #expect(gapless == Mp3Gapless(delay: 576, padding: 864, mpegFrames: 15, samplesPerFrame: 576))
        let file = try AVAudioFile(forReading: mp3)
        #expect(gapless.applies(to: file.length) == (file.length == 15 * 576))
        let mpeg1 = try folder.write("click44100.mp3", base64: #require(Self.clips["click44100.mp3"]))
        #expect(Mp3Gapless.read(mpeg1) == Mp3Gapless(delay: 576, padding: 1170, mpegFrames: 13, samplesPerFrame: 1152))
        // Not an MP3's first frame: nothing.
        #expect(Mp3Gapless.parse(frame: [0x49, 0x44, 0x33, 4, 0, 0]) == nil)
        // A length that is already trimmed isn't trimmed again.
        #expect(!gapless.applies(to: 7_200))
    }

    /// A long clip is decoded in chunks as it plays: the chunks join into exactly the clip decoded whole.
    @Test(arguments: ["click24000.m4a", "click44100.mp3", "click48000.opus"])
    func chunksJoinIntoTheWholeClip(_ name: String) throws {
        let folder = try AudioScratch()
        let source = try ClipDecoder.open(folder.write(name, base64: #require(Self.clips[name])))
        let whole = try ClipDecoder.decode(source)
        let stream = try ClipStream(source)
        var joined: [Float] = []
        while let chunk = try stream.read(997) {
            joined += Self.samples(chunk)
        }
        #expect(stream.isAtEnd)
        let expected = Self.samples(whole)
        #expect(joined.count == expected.count)
        let worst = zip(joined, expected).map { abs($0 - $1) }.max() ?? 0
        #expect(worst < 1e-6, "\(name): chunks differ from the whole clip by \(worst)")
    }

    /// A 48 kHz clip is read as it is (no converter), to its very last frame: AVAudioFile hands over fewer frames
    /// than asked at times (14336 of 14400), and the rest must be read, not left silent.
    @Test func a48kHzClipIsReadToItsLastFrame() throws {
        let content = try LevelClips()
        try content.clip("dc", level: 0.5, frames: 14_400)
        let source = try ClipDecoder.open(#require(content.resolver.url("dc")))
        #expect(source.frames == 14_400)
        #expect(Self.samples(try ClipDecoder.decode(source)).allSatisfy { $0 == 0.5 })
        let stream = try ClipStream(source)
        var frames = 0
        while let chunk = try stream.read(5_000) {
            #expect(Self.samples(chunk).allSatisfy { $0 == 0.5 })
            frames += Int(chunk.frameLength)
        }
        #expect(frames == 14_400)
    }

    static func samples(_ buffer: AVAudioPCMBuffer) -> [Float] {
        Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
    }

    @Test func outputLengthsRoundToTheNearestFrame() {
        #expect(ClipDecoder.outputFrames(7_200, rate: 24_000) == 14_400)
        #expect(ClipDecoder.outputFrames(13_230, rate: 44_100) == 14_400)
        #expect(ClipDecoder.outputFrames(1, rate: 44_100) == 1)           // 1.088
        #expect(ClipDecoder.outputFrames(859_024, rate: 44_100) == 934_992) // 934_991.8
        #expect(ClipDecoder.outputFrames(123, rate: 48_000) == 123)
    }

    @Test func aFileThatIsntAudioDoesntOpen() throws {
        let folder = try AudioScratch()
        let url = folder.url.appendingPathComponent("broken.m4a")
        try Data("not audio".utf8).write(to: url)
        #expect(throws: (any Error).self) { try ClipDecoder.open(url) }
    }

    /// Every clip the bundled maps and Nuclear War play: its file opens, and its length is within 0.12 s of "dur".
    /// A sample of them is decoded in full, to exactly that length.
    @Test(.enabled(if: BundledClips.content != nil, "no content was bundled"))
    func bundledClipsDecodeWithinTheirDur() async throws {
        let content = try #require(BundledClips.content)
        var checked = 0
        var worst: [String: (seconds: Double, path: String)] = [:]
        var failures: [String] = []
        for (game, clips) in try BundledClips.clips() {
            let resolver = ContentResolver(gameId: game, content: content, packs: [])
            for (i, clip) in clips.enumerated() {
                guard let url = resolver.url(clip.path) else { continue }  // a pack's own clip
                let source: ClipSource
                do {
                    source = try ClipDecoder.open(url)
                } catch {
                    failures.append("\(game)/\(clip.path): \(error)")
                    continue
                }
                checked += 1
                let off = source.seconds - clip.dur
                let codec = "\(url.pathExtension) \(Int(source.fileRate)) Hz"
                if worst[codec].map({ abs(off) > abs($0.seconds) }) ?? true {
                    worst[codec] = (off, "\(game)/\(clip.path)")
                }
                if abs(off) > 0.12 {
                    failures.append("\(game)/\(clip.path): \(source.seconds) s, dur \(clip.dur)")
                }
                if i % 40 == 0 {
                    let buffer = try ClipDecoder.decode(source)
                    #expect(Int64(buffer.frameLength) == source.frames, "\(game)/\(clip.path)")
                    #expect(Self.samples(buffer).contains { abs($0) > 0.001 }, "\(game)/\(clip.path): silent")
                }
            }
        }
        for (codec, w) in worst.sorted(by: { $0.key < $1.key }) {
            print(String(format: "DecodeTests: %@: worst %+.4f s against dur (%@)", codec, w.seconds, w.path))
        }
        #expect(checked > 1_000, "only \(checked) clips checked")
        #expect(failures.isEmpty, "\(failures.count) clips: \(failures.prefix(10).joined(separator: "; "))")
    }
}

/// The game content the app bundled (Content/<id>/, Games/<id>/), and the clips its maps play with their "dur".
enum BundledClips {
    static let content = Bundle.main.url(forResource: "Content", withExtension: nil)
    static let games = Bundle.main.url(forResource: "Games", withExtension: nil)

    struct Timed {
        let path: String
        let dur: Double
    }

    /// Each game's clips (paths without extensions, as the maps give them), in catalog order; each path once.
    static func clips() throws -> [(String, [Timed])] {
        guard let games else { return [] }
        let catalog = try JSONParser.parse(Data(contentsOf: games.appendingPathComponent("catalog.json")))
        var out: [(String, [Timed])] = []
        for g in catalog["games"]?.arrayValue ?? [] {
            guard let id = g["id"]?.content else { continue }
            var clips: [Timed] = []
            if id == NuclearWar.id {
                let json = try JSONParser.parse(Data(contentsOf: games.appendingPathComponent("\(id)/clips.json")))
                for key in ["voice", "clips", "mixes"] {
                    for (_, v) in json[key]?.objectValue ?? JSONObject() {
                        if let p = v["play"]?.content { clips.append(Timed(path: p, dur: v["dur"]?.doubleOrNull ?? 0)) }
                    }
                }
            } else {
                let map = try GameMap.load(games.appendingPathComponent("\(id)/map.json"))
                for (_, node) in map.nodes {
                    collect(node.say, into: &clips)
                    if let ask = node.ask {
                        collect(ask.reprompt, into: &clips)
                        if let e = ask.otherwise { collect(e.say, into: &clips) }
                    }
                }
            }
            var seen = Set<String>()
            out.append((id, clips.filter { $0.dur > 0 && seen.insert($0.path).inserted }))
        }
        return out
    }

    static func collect(_ steps: [Step], into out: inout [Timed]) {
        for s in steps {
            switch s {
            case .play(let c): out.append(Timed(path: c.path, dur: c.dur))
            case .bed(let p?, _, let dur): out.append(Timed(path: p, dur: dur))
            case .when(_, let inner): collect(inner, into: &out)
            case .pick(let options): for o in options { collect(o, into: &out) }
            case .by(_, let cases, let otherwise):
                for (_, c) in cases { collect(c, into: &out) }
                collect(otherwise, into: &out)
            default: break
            }
        }
    }
}

/// A folder of a test's own, deleted when the test is done with it.
final class AudioScratch {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("audio-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    func write(_ name: String, base64: String) throws -> URL {
        let data = try #require(Data(base64Encoded: base64, options: .ignoreUnknownCharacters))
        let file = url.appendingPathComponent(name)
        try data.write(to: file)
        return file
    }
}
