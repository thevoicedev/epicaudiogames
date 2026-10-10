// AppAudio.swift as the build has it: its pages and their clips (Android's AppAudioTest, the parts with no sound: the
// sounds themselves are the Audio Lab's and the phone's to check, as playing them here would change the audio session
// under the other suites' turns).

import EpicAppCore
import Foundation
import Testing
@testable import EpicAudioGames

@MainActor
struct AppAudioTests {
    /// The build's help pages (iOS's own, VoiceOver's page among them) and every clip they and the welcome play.
    @Test(.enabled(if: contentPresent, "no content was bundled"))
    func theBuildHasThisAppsPagesAndTheirClips() throws {
        let audio = AppAudio(settings: AppSettings(), content: BundledClips.content)
        let manifest = try #require(audio.manifest, "no Content/app/app.json in the build")
        #expect(manifest.topic("screen-reader")?.title == "Using VoiceOver")
        for page in manifest.help {
            #expect(audio.hasClip(.help(page.id)), "\(page.id)")
        }
        #expect(audio.hasClip(.welcome))
        #expect(audio.hasClip(.sample))
        #expect(!audio.hasClip(.help("no-such-topic")))
        #expect(audio.clipPlaying == nil)
        #expect(audio.highlight == nil)
        // Settings › Music volume's sample is the Werewolf's village music, there whenever the build has that game.
        if let content = BundledClips.content,
           FileManager.default.fileExists(atPath: content.appendingPathComponent(AppAudio.musicSampleGame).path) {
            #expect(audio.musicSample != nil, "no \(AppAudio.musicSamplePath) for Settings' music sample")
        }
    }

    /// With no content (a build without it, or the tests' silent model): nothing to read, no sting, no sample, and
    /// nothing breaks.
    @Test func withNoContentThereIsNothingToPlay() {
        let audio = AppAudio(settings: AppSettings(), content: nil)
        #expect(audio.manifest == nil)
        #expect(!audio.hasClip(.welcome))
        #expect(!audio.hasClip(.sample))
        audio.play(.welcome)
        audio.previewVoiceSpeed()
        #expect(audio.clipPlaying == nil)
        // Settings' samples of the sting and of the music (AppAudioTest's settingsSamples… on Android, with sound).
        audio.previewIntro()
        audio.previewMusic()
        #expect(audio.musicSample == nil)
        #expect(!audio.previewing)
        AppAudio.introPlayed = false
        #expect(!audio.playIntro(onDone: {}))
        #expect(!audio.introPlaying)
        audio.stopAll()
    }
}
