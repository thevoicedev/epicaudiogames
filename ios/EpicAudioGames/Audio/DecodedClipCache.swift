// AudioPlayer.kt has no counterpart (ExoPlayer decodes as it plays): clips decoded once, kept while they fit.

import AVFoundation

/// A clip decoded whole, in [ClipFormat]. Never changed after decoding, so it can be shared and played anywhere.
nonisolated final class DecodedClip: @unchecked Sendable {
    let source: ClipSource
    let buffer: AVAudioPCMBuffer

    init(source: ClipSource, buffer: AVAudioPCMBuffer) {
        self.source = source
        self.buffer = buffer
    }
}

/**
 * Opens clips and decodes the short ones whole, keeping the most recently used while they fit in [budget] bytes
 * (about 40 MB: some 3½ minutes of audio at 48 kHz). A turn's next lines, Nuclear War's numbers and the games'
 * jingles come back often. Clips longer than [wholeLimit] are streamed in chunks as they play instead (ClipStream).
 * Clips' lengths are kept for as long as the app runs (a few bytes each).
 */
actor DecodedClipCache {
    nonisolated static let shared = DecodedClipCache()

    /// The longest clip decoded whole: 4 s.
    nonisolated static let wholeLimit = ClipFormat.frames(4)

    let budget: Int
    private var sources: [URL: ClipSource?] = [:]
    private var clips: [URL: (clip: DecodedClip, used: UInt64)] = [:]
    private var tick: UInt64 = 0
    private(set) var bytes = 0

    init(budget: Int = 40_000_000) {
        self.budget = budget
    }

    /// The clip at [url], opened; nil when it can't be (L5: the turn plays on without it).
    func source(_ url: URL) -> ClipSource? {
        if let known = sources[url] { return known }
        var opened: ClipSource?
        do {
            opened = try ClipDecoder.open(url)
        } catch {
            ClipDecoder.failed(url, error)
        }
        sources[url] = opened
        return opened
    }

    /// The whole clip, decoded (kept for next time if it is short).
    func clip(_ source: ClipSource) throws -> DecodedClip {
        tick += 1
        if let kept = clips[source.url], kept.clip.source == source {
            clips[source.url]?.used = tick
            return kept.clip
        }
        let clip = DecodedClip(source: source, buffer: try ClipDecoder.decode(source))
        guard source.frames <= Self.wholeLimit, source.bytes <= budget else { return clip }
        if let old = clips[source.url] { bytes -= old.clip.source.bytes }
        clips[source.url] = (clip, tick)
        bytes += source.bytes
        while bytes > budget, let oldest = clips.min(by: { $0.value.used < $1.value.used }) {
            clips[oldest.key] = nil
            bytes -= oldest.value.clip.source.bytes
        }
        return clip
    }

    /// Whether the clip is decoded and kept.
    func holds(_ url: URL) -> Bool { clips[url] != nil }

    /// Lets every decoded clip go (memory warnings).
    func empty() {
        clips.removeAll()
        bytes = 0
    }

    /// Forgets the clips in a folder and below (a pack installed again, updated or deleted: its files changed).
    func forget(under folder: URL) {
        let prefix = folder.standardizedFileURL.path + "/"
        func inside(_ url: URL) -> Bool { url.standardizedFileURL.path.hasPrefix(prefix) }
        for url in sources.keys where inside(url) { sources[url] = nil }
        for (url, kept) in clips where inside(url) {
            clips[url] = nil
            bytes -= kept.clip.source.bytes
        }
    }
}
