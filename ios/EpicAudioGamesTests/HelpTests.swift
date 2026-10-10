// HelpScreenTest.kt's Listen and Pause (HelpView.swift's ListenAction, which the button and Magic Tap share), and the
// page's word being read marked (PageParagraphs: the transcript's highlight on a help paragraph). The screens
// themselves are HelpUITests'.

import EpicAppCore
import SwiftUI
import Testing
@testable import EpicAudioGames

@MainActor
struct HelpTests {
    /// Listen reads the page; while it does it's Pause, which stops it.
    @Test func listenReadsThePageAndPauseStopsIt() {
        let audio = FakePageAudio()
        let moment = Moment()
        let listen = ListenAction(clip: .help("voice"), audio: audio, waiting: moment.binding, voiceOver: false)
        #expect(listen.available)
        #expect(!listen.reading)
        listen.toggle()
        #expect(audio.played == [.help("voice")])
        #expect(listen.reading)
        listen.toggle()
        #expect(audio.clipPlaying == nil)
        #expect(!listen.reading)
    }

    /// With VoiceOver on, Listen is Pause at once (VoiceOver hears that), and the voice comes a moment later
    /// (docs/DESIGN.md › Help: 400 ms); Pause in that moment means nothing is read.
    @Test func withVoiceOverTheVoiceWaitsForItsMoment() async throws {
        let audio = FakePageAudio()
        let moment = Moment()
        let listen = ListenAction(clip: .help("voice"), audio: audio, waiting: moment.binding, voiceOver: true)
        let tapped = ContinuousClock.now
        listen.toggle()
        #expect(listen.reading)
        #expect(audio.played.isEmpty)
        // Waited for, not slept through: a busy machine runs the moment late (never early).
        #expect(await until { !audio.played.isEmpty })
        #expect(ContinuousClock.now - tapped >= A11y.listenDelay)
        #expect(audio.played == [.help("voice")])
        #expect(moment.task == nil)
        audio.stopClip()
        listen.toggle()
        listen.toggle()
        #expect(!listen.reading)
        try await Task.sleep(for: A11y.listenDelay + .milliseconds(300))
        #expect(audio.played == [.help("voice")], "read after Pause")
    }

    /// A build without the clip has no Listen; a page going stops a Listen still waiting to start.
    @Test func withoutTheClipThereIsNoListenAndAPageGoingStopsTheWait() async throws {
        let audio = FakePageAudio()
        audio.clips = false
        #expect(!ListenAction(clip: .welcome, audio: audio, waiting: Moment().binding, voiceOver: false).available)
        audio.clips = true
        let moment = Moment()
        let listen = ListenAction(clip: .welcome, audio: audio, waiting: moment.binding, voiceOver: true)
        listen.toggle()
        listen.cancel()
        #expect(moment.task == nil)
        try await Task.sleep(for: A11y.listenDelay + .milliseconds(300))
        #expect(audio.played.isEmpty)
    }

    /// The voice ten characters into a paragraph: that word, and only that one, marked (HelpScreenTest.kt's).
    @Test func theWordBeingReadIsMarked() {
        let paragraph = "Say “repeat” to hear it again, or “stop” to pause the game."
        let text = transcriptText(paragraph, saidChars: 10, highlight: true, wholeLine: true, colors: .dark)
        #expect(String(text.characters) == paragraph)
        let marked = text.runs.filter { $0.attributes[Background.self] != nil }
            .map { String(text[$0.range].characters) }
        #expect(marked == [Transcript.currentWord(paragraph, saidChars: 10).word])
        #expect(marked == ["“repeat”"])
        #expect(PageParagraphs.anchor(2) == "paragraph-2")
    }

    private typealias Background = AttributeScopes.SwiftUIAttributes.BackgroundColorAttribute

    private func until(_ timeout: Duration = .seconds(5), _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            if ContinuousClock.now > deadline { return false }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return true
    }
}

/// A stand-in for the app's audio: what a page asks of it, and what it was asked to read (Android's FakePageAudio).
@MainActor
final class FakePageAudio: PageAudio {
    var clipPlaying: AppClip?
    var highlight: HelpHighlight?
    /// Whether the build has the clips.
    var clips = true
    private(set) var played: [AppClip] = []

    func hasClip(_ clip: AppClip) -> Bool { clips }

    func play(_ clip: AppClip) {
        played.append(clip)
        clipPlaying = clip
    }

    func stopClip() {
        clipPlaying = nil
    }
}

/// Listen's moment, kept as a page keeps it (its @State), for ListenAction's binding.
@MainActor
private final class Moment {
    var task: Task<Void, Never>?

    var binding: Binding<Task<Void, Never>?> {
        Binding(get: { self.task }, set: { self.task = $0 })
    }
}
