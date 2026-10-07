// AudioPlayer.kt's media sources (ProgressiveMediaSource over .m4a, .mp3 and .opus): a clip's file, decoded.

import AVFoundation
import os

/**
 * The one PCM format the app decodes every clip to and plays on every player node: 48 kHz, 32-bit float, mono.
 *
 * 48 kHz: Don's Opus lines decode at 48 kHz (Opus always does) and iPhones play at 48 kHz, so the other clips (24 kHz
 * speech, 32 kHz mixes, 44.1 kHz recordings) are converted up once, here, not in the mixer. Mono: tools/content.py
 * encodes every clip mono (-ac 1), and stereo would double the memory for nothing; a stereo file is mixed down.
 */
nonisolated enum ClipFormat {
    static let sampleRate = 48_000.0
    static let pcm = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
    static let bytesPerFrame = MemoryLayout<Float>.size

    /// Seconds as whole frames.
    static func frames(_ seconds: Double) -> Int64 { Int64((seconds * sampleRate).rounded()) }
}

/// A clip's file as the app plays it: what to read of it, and how long it is at 48 kHz.
nonisolated struct ClipSource: Hashable, Sendable {
    let url: URL
    /// The file's own sample rate.
    let fileRate: Double
    /// Frames (at the file's rate) skipped at the start: an MP3's encoder delay.
    let skip: Int64
    /// Frames (at the file's rate) to play, after [skip] and before an MP3's padding.
    let fileFrames: Int64
    /// The clip's length at 48 kHz: what TurnTimeline lays out, and exactly what reading it gives.
    let frames: Int64

    var seconds: Double { Double(frames) / ClipFormat.sampleRate }
    var bytes: Int { Int(frames) * ClipFormat.bytesPerFrame }
}

nonisolated enum ClipDecoderError: Error {
    case notAudio(URL)
    case noBuffer
    case conversion(URL, String)
}

/**
 * Opens and decodes clips with AVAudioFile (AAC .m4a, MP3, Ogg Opus: the iOS 26 simulator reads all three) into
 * [ClipFormat]. Lengths match what ExoPlayer plays: AVAudioFile already drops AAC priming (the MP4 edit list) and
 * Opus pre-skip; an MP3's LAME encoder delay and padding, which ExoPlayer drops (its Xing frame) and AVAudioFile
 * keeps, are dropped here.
 */
nonisolated enum ClipDecoder {
    static let log = Logger(subsystem: "com.epicaudiogames.app", category: "audio")

    /// A clip that can't be opened or decoded plays as nothing, or as silence (L5); the log says why.
    static func failed(_ url: URL, _ error: Error) {
        log.error("can't decode \(url.lastPathComponent, privacy: .public): \(error, privacy: .public)")
    }

    /// The clip at [url]: its length and what to read. Throws when it isn't audio AVAudioFile can read.
    static func open(_ url: URL) throws -> ClipSource {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let rate = file.processingFormat.sampleRate
        guard rate > 0, file.processingFormat.channelCount > 0 else { throw ClipDecoderError.notAudio(url) }
        var skip: Int64 = 0
        var frames = file.length
        if url.pathExtension.lowercased() == "mp3", let gapless = Mp3Gapless.read(url),
           gapless.applies(to: file.length) {
            skip = gapless.delay
            frames = file.length - gapless.delay - gapless.padding
        }
        return ClipSource(url: url, fileRate: rate, skip: skip, fileFrames: max(frames, 0),
                          frames: outputFrames(max(frames, 0), rate: rate))
    }

    /// [frames] at [rate] as frames at 48 kHz, rounded to the nearest.
    static func outputFrames(_ frames: Int64, rate: Double) -> Int64 {
        if rate == ClipFormat.sampleRate { return frames }
        if rate == rate.rounded(), rate <= 1_000_000 {
            let r = Int64(rate)
            return (frames * 48_000 + r / 2) / r
        }
        return Int64((Double(frames) * ClipFormat.sampleRate / rate).rounded())
    }

    /// The whole clip, [source].frames long.
    static func decode(_ source: ClipSource) throws -> AVAudioPCMBuffer {
        let stream = try ClipStream(source)
        guard let buffer = try stream.read(AVAudioFrameCount(clamping: max(source.frames, 1))) else {
            throw ClipDecoderError.noBuffer
        }
        return buffer
    }
}

/**
 * Reads a clip from its start in [ClipFormat], a chunk at a time, so a long clip (a 2-minute mix or music bed) is
 * decoded as it plays rather than all at once. Gives exactly [ClipSource.frames] frames: the converter's last few
 * are padded with silence or cut to make the length TurnTimeline used. Used by one owner at a time (unchecked
 * Sendable only because AVAudioConverter's input block is @Sendable; it runs inside [read]).
 */
nonisolated final class ClipStream: @unchecked Sendable {
    let source: ClipSource
    /// Frames given so far.
    private(set) var position: Int64 = 0
    private let file: AVAudioFile
    private let converter: AVAudioConverter?
    private let input: AVAudioPCMBuffer
    /// File frames still to read (the MP3 padding is never read).
    private var fileLeft: Int64
    private var drained = false
    private var readError: Error?

    init(_ source: ClipSource) throws {
        self.source = source
        file = try AVAudioFile(forReading: source.url, commonFormat: .pcmFormatFloat32, interleaved: false)
        if source.skip > 0 { file.framePosition = source.skip }
        fileLeft = source.fileFrames
        let format = file.processingFormat
        if format.sampleRate == ClipFormat.sampleRate && format.channelCount == 1 {
            converter = nil
        } else {
            guard let c = AVAudioConverter(from: format, to: ClipFormat.pcm) else {
                throw ClipDecoderError.conversion(source.url, "\(format)")
            }
            c.sampleRateConverterQuality = AVAudioQuality.max.rawValue
            c.downmix = true
            converter = c
        }
        guard let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_384) else {
            throw ClipDecoderError.noBuffer
        }
        input = b
    }

    var isAtEnd: Bool { position >= source.frames }

    /// The next [count] frames (fewer at the end); nil once the whole clip has been read.
    func read(_ count: AVAudioFrameCount) throws -> AVAudioPCMBuffer? {
        let n = AVAudioFrameCount(clamping: min(Int64(count), source.frames - position))
        guard n > 0 else { return nil }
        guard let out = AVAudioPCMBuffer(pcmFormat: ClipFormat.pcm, frameCapacity: n) else {
            throw ClipDecoderError.noBuffer
        }
        if let converter {
            try convert(converter, into: out)
        } else {
            try readDirect(into: out)
        }
        // Whatever the decoder gave, exactly n frames: silence after its end.
        if out.frameLength < n {
            let have = Int(out.frameLength)
            out.floatChannelData![0].advanced(by: have).update(repeating: 0, count: Int(n) - have)
            out.frameLength = n
        }
        position += Int64(n)
        return out
    }

    /// Reads the file's frames, at 48 kHz mono already. AVAudioFile can give fewer than asked (14336 of 14400), so
    /// it reads until the buffer is full or the file ends.
    private func readDirect(into out: AVAudioPCMBuffer) throws {
        let to = out.floatChannelData![0]
        while out.frameLength < out.frameCapacity {
            let want = min(Int64(out.frameCapacity - out.frameLength), Int64(input.frameCapacity), fileLeft,
                           max(file.length - file.framePosition, 0))
            guard want > 0 else { return }
            try file.read(into: input, frameCount: AVAudioFrameCount(want))
            let got = input.frameLength
            guard got > 0 else { return }
            to.advanced(by: Int(out.frameLength)).update(from: input.floatChannelData![0], count: Int(got))
            out.frameLength += got
            fileLeft -= Int64(got)
        }
    }

    private func convert(_ converter: AVAudioConverter, into out: AVAudioPCMBuffer) throws {
        guard !drained else { return }
        readError = nil
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { [self] packets, status in
            let want = min(Int64(packets), Int64(input.frameCapacity), fileLeft,
                           max(file.length - file.framePosition, 0))
            guard want > 0 else {
                status.pointee = .endOfStream
                return nil
            }
            do {
                try file.read(into: input, frameCount: AVAudioFrameCount(want))
            } catch {
                readError = error
                status.pointee = .endOfStream
                return nil
            }
            guard input.frameLength > 0 else {
                status.pointee = .endOfStream
                return nil
            }
            fileLeft -= Int64(input.frameLength)
            status.pointee = .haveData
            return input
        }
        if let readError { throw readError }
        switch status {
        case .error: throw error ?? ClipDecoderError.conversion(source.url, "failed")
        case .endOfStream: drained = true
        default: break
        }
    }
}

/**
 * An MP3's gapless information: the encoder delay and padding in the LAME extension of its Xing/Info frame, read as
 * ExoPlayer's Mp3Extractor reads them (24 bits, 21 bytes after the Xing fields).
 */
nonisolated struct Mp3Gapless: Equatable {
    let delay: Int64
    let padding: Int64
    /// The audio frames the Xing frame counts, if it says, and the samples in each.
    let mpegFrames: Int64?
    let samplesPerFrame: Int64

    /**
     * Whether AVAudioFile's [length] still has the delay and padding in it: it counts every MPEG frame's samples
     * (as on iOS 26). If a version already trims them, its length is shorter and nothing more is cut.
     */
    func applies(to length: Int64) -> Bool {
        guard delay > 0 || padding > 0, delay + padding < length else { return false }
        if let mpegFrames { return length == mpegFrames * samplesPerFrame }
        return true
    }

    static func read(_ url: URL) -> Mp3Gapless? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard var head = try? handle.read(upToCount: 10) else { return nil }
        var offset: UInt64 = 0
        // ID3v2 tags come first: skip them (their size is four 7-bit bytes, plus a footer if flagged).
        while head.count == 10, head.starts(with: [0x49, 0x44, 0x33]) {
            let tag = [UInt8](head)
            let size = tag[6...9].reduce(UInt64(0)) { $0 << 7 | UInt64($1 & 0x7f) }
            offset += 10 + size + (tag[5] & 0x10 != 0 ? 10 : 0)
            guard (try? handle.seek(toOffset: offset)) != nil, let next = try? handle.read(upToCount: 10) else {
                return nil
            }
            head = next
        }
        guard (try? handle.seek(toOffset: offset)) != nil, let frame = try? handle.read(upToCount: 2048) else {
            return nil
        }
        return parse(frame: [UInt8](frame))
    }

    /// The gapless information in the first MPEG audio frame ([bytes] starts with its header), if it has any.
    static func parse(frame bytes: [UInt8]) -> Mp3Gapless? {
        guard bytes.count >= 4, bytes[0] == 0xff, bytes[1] & 0xe0 == 0xe0 else { return nil }
        let version = (bytes[1] >> 3) & 3       // 3: MPEG 1, 2: MPEG 2, 0: MPEG 2.5
        let layer = (bytes[1] >> 1) & 3         // 1: Layer III
        guard version != 1, layer == 1 else { return nil }
        let mono = (bytes[3] >> 6) & 3 == 3
        let sideInfo = version == 3 ? (mono ? 17 : 32) : (mono ? 9 : 17)
        var i = 4 + sideInfo
        guard bytes.count >= i + 8 else { return nil }
        let tag = String(decoding: bytes[i..<i + 4], as: UTF8.self)
        guard tag == "Xing" || tag == "Info" else { return nil }
        func int32(_ at: Int) -> Int64 {
            Int64(bytes[at]) << 24 | Int64(bytes[at + 1]) << 16 | Int64(bytes[at + 2]) << 8 | Int64(bytes[at + 3])
        }
        let flags = int32(i + 4)
        i += 8
        var frames: Int64?
        if flags & 1 != 0 {
            guard bytes.count >= i + 4 else { return nil }
            frames = int32(i)
            i += 4
        }
        if flags & 2 != 0 { i += 4 }
        if flags & 4 != 0 { i += 100 }
        if flags & 8 != 0 { i += 4 }
        // The LAME extension: 9 bytes of encoder name, 12 more, then the delay and padding (12 bits each).
        guard bytes.count >= i + 24 else { return nil }
        let v = Int64(bytes[i + 21]) << 16 | Int64(bytes[i + 22]) << 8 | Int64(bytes[i + 23])
        return Mp3Gapless(delay: v >> 12, padding: v & 0xfff, mpegFrames: frames,
                          samplesPerFrame: version == 3 ? 1152 : 576)
    }
}
