// Earcons.kt's sounds, read once each (its read and Wav.pcm16Mono): the app's short sounds, decoded for the game's
// audio graph.

import AVFoundation
import EpicAppCore
import os

/**
 * The app's short sounds (AppCue: content/app/earcons/<name>.wav, picked with tools/app_audio.py; docs/DESIGN.md ›
 * Sounds, haptics and the microphone), each decoded once, as it's first wanted, with ClipDecoder into the games' own
 * format ([ClipFormat]: 48 kHz mono), for the game's AudioGraph to play on its cue node. A sound the build doesn't have
 * (content without app/) is nil: the mic then opens without it. Android reads the same files as Earcons.kt.
 *
 * Nonisolated and locked: TurnPlayer asks for them on the main actor, and the app decodes them ahead of the first game
 * away from it ([preload]).
 */
nonisolated final class CueBank: @unchecked Sendable {
    /// The app's own, in its content (bundle_content.sh copies content/app/ to Content/app/).
    static let shared = CueBank(
        folder: Bundle.main.url(forResource: "Content", withExtension: nil)?
            .appendingPathComponent("\(AppManifest.folder)/earcons", isDirectory: true))

    /// Where the sounds are (<name>.wav); nil for a build with no content.
    let folder: URL?
    /// Each sound decoded so far: nil for one the build doesn't have, or that can't be read.
    private let decoded = OSAllocatedUnfairLock<[AppCue: DecodedClip?]>(initialState: [:])

    init(folder: URL?) {
        self.folder = folder
    }

    /// The file of [cue] in this build, if it has it.
    func url(_ cue: AppCue) -> URL? {
        guard let file = folder?.appendingPathComponent("\(cue.rawValue).wav", isDirectory: false),
              FileManager.default.fileExists(atPath: file.path) else { return nil }
        return file
    }

    /// [cue] decoded (once, then kept); nil when the build hasn't it or it can't be read.
    func clip(_ cue: AppCue) -> DecodedClip? {
        if let known = decoded.withLock({ $0[cue] }) { return known }
        let clip = decode(cue)
        decoded.withLock { $0[cue] = .some(clip) }
        return clip
    }

    private func decode(_ cue: AppCue) -> DecodedClip? {
        guard let url = url(cue) else {
            ClipDecoder.log.error("no \(cue.rawValue, privacy: .public).wav in this build")
            return nil
        }
        do {
            let source = try ClipDecoder.open(url)
            return DecodedClip(source: source, buffer: try ClipDecoder.decode(source))
        } catch {
            ClipDecoder.failed(url, error)
            return nil
        }
    }

    /// Every sound decoded now, so the first listen doesn't wait for it (AppModel, as the app starts).
    func preload() {
        for cue in AppCue.allCases { _ = clip(cue) }
    }
}
