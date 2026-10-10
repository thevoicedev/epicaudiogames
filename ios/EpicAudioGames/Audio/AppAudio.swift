// AppAudio.kt: the app's own sounds outside a game's turns (the intro's sting, the welcome and help read aloud, the
// success sound, Settings' samples).

import AVFoundation
import EpicAppCore
import Observation
import os
import UIKit

/// What [AppAudio] reads aloud: the welcome, a help page, or Settings' sample of the voice speed. Android's AppClip.
nonisolated enum AppClip: Hashable, Sendable {
    case welcome
    /// The help page [id] ("voice").
    case help(String)
    /// Settings › Sound and voice › Play a sample: the welcome's first line, at the voice speed chosen.
    case sample
}

/**
 * What a page read aloud needs of the app's audio (the Help tab's Listen, onboarding's welcome): [AppAudio], or a
 * test's stand-in. Android's PageAudio.
 */
@MainActor
protocol PageAudio: AnyObject {
    /// The clip being read aloud, if one is.
    var clipPlaying: AppClip? { get }

    /// Where the voice is in the page being read: the paragraph, and how much of it has been said.
    var highlight: HelpHighlight? { get }

    /// Whether [clip] can be read aloud in this build.
    func hasClip(_ clip: AppClip) -> Bool

    /// Reads [clip] aloud from its start (whatever was being read stops).
    func play(_ clip: AppClip)

    /// Stops reading aloud.
    func stopClip()
}

/**
 * The app's own sounds, outside a game's turns (docs/DESIGN.md › Sounds, haptics and the microphone; Help; Intro): the
 * intro's sting, the welcome and the help pages read aloud with the word being read marked, the success sound, and
 * Settings' samples. The screens call these (model.appAudio); a game playing has its own (GameController). Android's
 * AppAudio.kt.
 *
 * - The sting plays once per process, with an AVAudioPlayer in the ambient session (it keeps to the silent switch,
 *   mixes with other apps' audio and never stops it), and not at all while another app's audio plays
 *   (secondaryAudioShouldBeSilencedHint) or with the app in the background. [playIntro], [skipIntro], [introPlaying].
 * - The welcome and the help play through a TurnPlayer of their own, as the game "app" (Content/app/), at the voice
 *   speed, in the spoken session (.playback, .spokenAudio): another app's audio stops for them and comes back after,
 *   and a call or the headphones taken out stops them. With a game open (its help), they play in the game's session
 *   instead. [play], [stopClip], [clipPlaying], [highlight].
 * - The short sounds play on the game's cue node with a game open, else with an AVAudioPlayer in the ambient session.
 *   [playSuccess], [previewCue].
 * - Settings' samples of the sting and of the music at its volume ([previewIntro], [previewMusic]): the sting in the
 *   ambient session, as the intro has it; the music in the spoken session, as a page read aloud has it. One sound at
 *   a time with a page being read: each stops the other.
 * - Before a game opens, everything stops, and the session is let go for the game's ([stopAll]).
 */
@Observable
final class AppAudio: PageAudio {
    static let log = Logger(subsystem: "com.epicaudiogames.app", category: "app-audio")
    /// The sting plays on the process's first intro only (Debug's Audio Lab sets it back).
    static var introPlayed = false
    /// How long a skipped sting takes to fade out.
    static let fade: TimeInterval = 0.15

    /// Whether a game is open (AppModel's): its own audio session is in use, and the app's sounds play inside it.
    @ObservationIgnored var gameOpen: () -> Bool = { false }
    /// What plays short sounds over the open game: its TurnPlayer's cue node (AppModel's); nil, nothing.
    @ObservationIgnored var gameCues: () -> (any CuePlaying)? = { nil }

    @ObservationIgnored private let settings: AppSettings
    /// The app's Content folder, each game's in it (the music's sample is a game's bed); nil for a build with none.
    @ObservationIgnored private let content: URL?
    /// The app's own folder in the content (Content/app/); nil for a build with no content.
    @ObservationIgnored private let folder: URL?
    /// Finds the pages' clips, as the game "app".
    @ObservationIgnored private let resolver: ContentResolver?
    @ObservationIgnored private let cues: CueBank
    /// The manifest once read; nil inside when the build has none.
    @ObservationIgnored private var loaded: AppManifest??

    /// [content]: the app's Content folder (nil: no sounds, no pages).
    init(settings: AppSettings, content: URL?, cues: CueBank = .shared) {
        self.settings = settings
        self.content = content
        folder = content?.appendingPathComponent(AppManifest.folder, isDirectory: true)
        resolver = content.map { ContentResolver(gameId: AppManifest.folder, content: $0, packs: []) }
        self.cues = cues
        // Read away from the screen as the app starts (a screen asking sooner reads it itself), and the short sounds
        // decoded for the first game's listening.
        if let url = folder?.appendingPathComponent("app.json", isDirectory: false) {
            Task.detached(priority: .utility) { [weak self] in
                let manifest = AppManifest.load(url)
                await self?.read(manifest)
            }
        }
        if content != nil {
            Task.detached(priority: .utility) { cues.preload() }
        }
    }

    /// The app's help and sounds (Content/app/app.json, with this app's pages); nil if the build has none.
    var manifest: AppManifest? {
        if let loaded { return loaded }
        let m = folder.flatMap { AppManifest.load($0.appendingPathComponent("app.json", isDirectory: false)) }
        read(m)
        return m
    }

    /// The manifest, read away from the screen if it hasn't been yet: the intro waits for it (which sting) without
    /// stopping a frame. MainActivity.kt's startIntro reads it on Dispatchers.Default.
    func loadManifest() async -> AppManifest? {
        if let loaded { return loaded }
        guard let url = folder?.appendingPathComponent("app.json", isDirectory: false) else {
            read(nil)
            return nil
        }
        let m = await Task.detached(priority: .userInitiated) { AppManifest.load(url) }.value
        read(m)
        return manifest
    }

    private func read(_ manifest: AppManifest?) {
        guard loaded == nil else { return }
        if manifest == nil { Self.log.error("no app.json to read") }
        loaded = .some(manifest)
    }

    // ----- The intro's sting -----

    /// The sting is playing (the intro shows it).
    private(set) var introPlaying = false
    @ObservationIgnored private var sting: AVAudioPlayer?
    @ObservationIgnored private var introDone: (() -> Void)?
    @ObservationIgnored private var introWatch: Task<Void, Never>?

    /**
     * Plays the sting, if it's the process's first, the build has one, no other app's audio is playing and the app
     * isn't in the background (the intro then goes without it). Returns whether it plays: if so, [onDone] comes as it
     * ends (or is skipped, or can't play on), and not otherwise. The intro asks only with Settings' "Play the intro
     * sound" on.
     */
    func playIntro(onDone: @escaping () -> Void) -> Bool {
        if Self.introPlayed { return false }
        Self.introPlayed = true
        guard let s = manifest?.sting, let url = file(s.file) else { return false }
        if AVAudioSession.sharedInstance().secondaryAudioShouldBeSilencedHint {
            Self.log.info("another app's audio is playing: no sting")
            return false
        }
        // Launched in the background (a pack's download finishing): there's nobody to hear it.
        if UIApplication.shared.applicationState == .background { return false }
        guard hold(spoken: false) else { return false }
        let sound: AVAudioPlayer
        do {
            sound = try AVAudioPlayer(contentsOf: url)
        } catch {
            Self.log.error("can't play the sting: \(error, privacy: .public)")
            settle()
            return false
        }
        guard sound.play() else {
            settle()
            return false
        }
        sting = sound
        introDone = onDone
        introPlaying = true
        // Its end: once it stops playing (its last sample, a call); should that never be seen, a second after its
        // length.
        let latest = ContinuousClock.now + .seconds(s.seconds + 1)
        introWatch = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
                guard let self, let playing = self.sting else { return }
                if !playing.isPlaying || ContinuousClock.now >= latest {
                    self.endIntro()
                    return
                }
            }
        }
        return true
    }

    /// The intro skipped (a tap, Magic Tap, Escape): the sting fades out quickly, then the intro's onDone.
    func skipIntro() {
        guard let player = sting else { return }
        introWatch?.cancel()
        player.setVolume(0, fadeDuration: Self.fade)
        introWatch = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(Self.fade)) } catch { return }
            self?.endIntro()
        }
    }

    private func endIntro() {
        introWatch?.cancel()
        introWatch = nil
        let player = sting
        sting = nil
        introPlaying = false
        let done = introDone
        introDone = nil
        player?.stop()
        settle()
        done?()
    }

    // ----- The welcome, help pages and the voice speed's sample -----

    /// The clip being read aloud, if one is (a page's Listen button shows Pause for its own).
    private(set) var clipPlaying: AppClip?
    /// Where the voice is in the page being read ([HelpHighlight]): nil when nothing is, or before it starts.
    private(set) var highlight: HelpHighlight?
    @ObservationIgnored private var player: TurnPlayer?
    @ObservationIgnored private var reading: HelpPage?
    @ObservationIgnored private var ticker: Task<Void, Never>?

    /// Whether [clip] can be read aloud: the page is in the manifest, and its clips are in this build.
    func hasClip(_ clip: AppClip) -> Bool {
        guard let page = page(clip), page.hasClips, let resolver else { return false }
        return page.steps.allSatisfy { step in
            guard case .play(let c) = step else { return true }
            return resolver.url(c.path) != nil
        }
    }

    /**
     * Reads [clip] aloud from its start (whatever was being read stops), at the voice speed, with the word being read
     * in [highlight]. Not while a call has the audio.
     */
    func play(_ clip: AppClip) {
        guard let page = page(clip), let resolver else { return }
        stopClip()
        stopPreview()
        if !gameOpen() && !hold(spoken: true) {
            Self.log.info("the audio is someone else's: not reading")
            return
        }
        let p = player ?? makePlayer(resolver)
        player = p
        clipPlaying = clip
        reading = page
        p.speed = settings.voiceSpeed
        p.play(page.steps)
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.follow()
                do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
            }
        }
    }

    /// Stops reading aloud (the Pause button, a page closing, a game opening, a call).
    func stopClip() {
        guard clipPlaying != nil else { return }
        player?.stop()
        clipEnded()
    }

    private func makePlayer(_ resolver: ContentResolver) -> TurnPlayer {
        let p = TurnPlayer(resolver: resolver, cues: cues)
        p.onFinished = { [weak self] in self?.clipEnded() }
        // No audio at all (a call has it): nothing is read.
        p.onStalled = { [weak self] in self?.clipEnded() }
        return p
    }

    /// The page read to its end (or stopped): nothing marked, its engine let go, and other apps' audio back.
    private func clipEnded() {
        ticker?.cancel()
        ticker = nil
        reading = nil
        clipPlaying = nil
        highlight = nil
        // Its engine stopped, or the session it played in couldn't be let go ("busy"); the next page makes another.
        player?.release()
        settle()
    }

    /// The word being read now; in a pause between paragraphs, the last one stays marked.
    private func follow() {
        guard let page = reading, let at = player?.position(),
              let h = HelpHighlight.of(page, clip: at.clip, seconds: at.seconds), h != highlight else { return }
        highlight = h
    }

    /// The page a clip reads: Settings' sample is the welcome's first line alone.
    private func page(_ clip: AppClip) -> HelpPage? {
        guard let m = manifest else { return nil }
        switch clip {
        case .welcome:
            return m.welcome
        case .help(let id):
            return m.topic(id)
        case .sample:
            guard let w = m.welcome else { return nil }
            // Its first clip with words (an earcon has none), alone, with that clip's paragraph.
            var k = 0
            for step in w.steps {
                guard case .play(let c) = step else { continue }
                if !c.sfx {
                    let paragraph = w.clipParagraph.indices.contains(k) ? [w.clipParagraph[k]] : []
                    return HelpPage(
                        id: w.id, title: w.title, summary: w.summary, text: w.text, clipParagraph: paragraph,
                        steps: [step], links: w.links)
                }
                k += 1
            }
            return nil
        }
    }

    // ----- Short sounds, and the samples Settings plays -----

    @ObservationIgnored private var short: AVAudioPlayer?
    @ObservationIgnored private var shortEnds: Task<Void, Never>?

    /// A pack installed while the Shop or the store sheet shows: the success sound, and a tick if ticks are on.
    func playSuccess() {
        playSound(.success)
        if settings.listeningHaptics { Haptics.success() }
    }

    /**
     * Settings › Listening sounds or Vibrate when listening starts, turned on: what the player will get as the mic
     * opens (the sound, the tick, each if it's on).
     */
    func previewCue() {
        if settings.listeningHaptics { Haptics.micOpened() }
        if settings.listeningSounds { playSound(.listenStart) }
    }

    /// Settings › Voice speed › Play a sample: the welcome's first line at the speed chosen (again from its start).
    func previewVoiceSpeed() {
        play(.sample)
    }

    /**
     * One of the app's short sounds, now: with a game open, on its cue node (in its session); else on its own, in the
     * ambient session (so a phone on silent stays quiet), or in the session a page or one of Settings' samples plays in
     * while it does.
     */
    func playSound(_ cue: AppCue) {
        if gameOpen() {
            _ = gameCues()?.play(cue)
            return
        }
        guard let url = cues.url(cue) else { return }
        if clipPlaying == nil && preview == nil && !hold(spoken: false) { return }
        let sound: AVAudioPlayer
        do {
            sound = try AVAudioPlayer(contentsOf: url)
        } catch {
            Self.log.error("can't play \(cue.rawValue, privacy: .public): \(error, privacy: .public)")
            settle()
            return
        }
        short?.stop()
        short = sound
        sound.play()
        // Once it's over, the session can be let go.
        let length = sound.duration
        shortEnds?.cancel()
        shortEnds = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(length + 0.2)) } catch { return }
            guard let self else { return }
            self.short = nil
            self.settle()
        }
    }

    /// The voice speed changed: a page being read goes at the new speed at once.
    func speedChanged() {
        if clipPlaying != nil { player?.speed = settings.voiceSpeed }
    }

    // ----- Settings' samples of the intro's sting and of the music's volume -----

    /**
     * Music volume's sample (AppAudio.kt's MUSIC_SAMPLE): a game's bed (games/the-werewolf/map.json's village, music at
     * an even level from its start), at its volume there ([musicSampleVolume]) times the volume picked, for
     * [musicSampleSeconds], its last [musicFade] seconds faded out, as a bed fades at a turn's end, only slower.
     */
    static let musicSampleGame = "the-werewolf"
    static let musicSamplePath = "audio/village-bg"
    static let musicSampleVolume = 1.0
    static let musicSampleSeconds = 4.0
    static let musicFade = 0.5
    /// A sample that hasn't ended this long after its length (a phone slow to start it) is stopped anyway.
    static let previewWatchdog = 2.0

    /// The sample playing, if one is, and what ends it.
    @ObservationIgnored private var preview: AVAudioPlayer?
    @ObservationIgnored private var previewWatch: Task<Void, Never>?

    /// Whether one of Settings' samples (the sting, or the music) is playing.
    var previewing: Bool { preview != nil }

    /**
     * Settings › Play the intro sound, turned on: the sting, as the app will start with it, in the ambient session as
     * the intro has it (a phone on silent stays quiet, and another app's audio plays on). Nothing if the build has none.
     * Android's previewIntro.
     */
    func previewIntro() {
        guard let s = manifest?.sting, let url = file(s.file) else { return }
        stopPreview()
        stopClip()
        startPreview(url, spoken: false, volume: 1, seconds: s.seconds, fade: nil)
    }

    /**
     * Settings › Music volume, a step picked: a few seconds of a game's music at that volume ([musicSample]: the
     * Werewolf's village, at its own volume in the game times the music volume), fading out; a sample playing starts
     * again at the new volume. Off: silence, as the music will be. In the spoken session, as Play a sample has it, so
     * another app's music doesn't play over it (Android takes the audio focus for a moment). Android's previewMusic.
     */
    func previewMusic() {
        stopPreview()
        let volume = settings.musicVolume
        guard volume > 0, let url = musicSample else { return }
        stopClip()
        startPreview(
            url, spoken: true, volume: Float(Self.musicSampleVolume * volume), seconds: Self.musicSampleSeconds,
            fade: Self.musicFade)
    }

    /// The music sample's file in this build (as a game finds its bed: its first extension there); nil if none.
    var musicSample: URL? {
        guard let content else { return nil }
        let url = ContentResolver(gameId: Self.musicSampleGame, content: content, packs: []).url(Self.musicSamplePath)
        if url == nil { Self.log.error("no \(Self.musicSamplePath, privacy: .public) in this build: no music sample") }
        return url
    }

    /**
     * Plays [url] at [volume], in the spoken session or the ambient one, for [seconds] at most (its own length, if
     * shorter), its last [fade] seconds faded out if given. What it replaces has been stopped by the caller. Never over
     * a game: the session is the game's then (and Settings isn't showing).
     */
    private func startPreview(_ url: URL, spoken: Bool, volume: Float, seconds: Double, fade: Double?) {
        guard !gameOpen(), hold(spoken: spoken) else { return }
        let sound: AVAudioPlayer
        do {
            sound = try AVAudioPlayer(contentsOf: url)
        } catch {
            Self.log.error("can't play the sample: \(error, privacy: .public)")
            settle()
            return
        }
        sound.volume = volume
        guard sound.play() else {
            settle()
            return
        }
        preview = sound
        // Its end: faded out by [seconds], if it fades; else its own end (or a call), or a moment after its length
        // should that never be seen.
        let id = ObjectIdentifier(sound)
        let end = ContinuousClock.now + .seconds(seconds)
        let latest = fade == nil ? end + .seconds(Self.previewWatchdog) : end
        previewWatch = Task { [weak self] in
            var fading = false
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
                guard let self, let sound = self.preview, ObjectIdentifier(sound) == id else { return }
                let now = ContinuousClock.now
                if let fade, !fading, now >= end - .seconds(fade) {
                    fading = true
                    sound.setVolume(0, fadeDuration: fade)
                }
                if !sound.isPlaying || now >= latest {
                    self.stopPreview()
                    return
                }
            }
        }
    }

    /// The sample playing stops (another sample, a page read, a game opening, a call), and the session is let go.
    private func stopPreview() {
        previewWatch?.cancel()
        previewWatch = nil
        guard let sound = preview else { return }
        preview = nil
        sound.stop()
        settle()
    }

    /// A game is opening: the sting, anything being read, a sample and a short sound stop (the intro, if it was
    /// showing, is done), and the session is let go for the game's.
    func stopAll() {
        if sting != nil { endIntro() }
        stopClip()
        stopPreview()
        shortEnds?.cancel()
        shortEnds = nil
        short?.stop()
        short = nil
        settle()
    }

    // ----- The audio session, with no game open -----

    /// The session of the app's own sounds now held, if one is: the ambient one or the spoken one.
    @ObservationIgnored private var held: AudioSessionController?
    @ObservationIgnored private var ambientSession: AudioSessionController?
    @ObservationIgnored private var spokenSession: AudioSessionController?

    /// The spoken session (a page read aloud) or the ambient one (the sting, a short sound), made as first wanted.
    private func session(spoken: Bool) -> AudioSessionController {
        if let s = spoken ? spokenSession : ambientSession { return s }
        let report: @MainActor @Sendable (AudioSessionController.Event) -> Void = { [weak self] event in
            self?.sessionEvent(event)
        }
        let s: AudioSessionController
        if spoken {
            s = AudioSessionController(setUp: AudioSessionController.spoken, onEvent: report)
            spokenSession = s
        } else {
            s = AudioSessionController(setUp: AudioSessionController.ambient, onEvent: report)
            ambientSession = s
        }
        return s
    }

    /// That session, active, for what's about to play (taking over from the other, if it was held): false if it can't
    /// be (a call has the audio).
    private func hold(spoken: Bool) -> Bool {
        let s = session(spoken: spoken)
        if let held, held !== s { held.stopObserving() }
        held = s
        do {
            try s.activate()
            return true
        } catch {
            Self.log.error("can't activate the audio session: \(error, privacy: .public)")
            s.stopObserving()
            held = nil
            return false
        }
    }

    /**
     * Once nothing of the app's own plays, the session it held is let go, so other apps' audio carries on. A game open
     * has taken it over with its own: that one is the game's to let go.
     */
    private func settle() {
        guard let h = held else { return }
        if gameOpen() {
            h.stopObserving()
            held = nil
            return
        }
        guard sting == nil, clipPlaying == nil, short == nil, preview == nil else { return }
        held = nil
        h.deactivate(stopping: [player?.engine].compactMap { $0 })
    }

    /// A call, Siri or an alarm, the headphones taken out, or the audio system restarting: a page being read, or a
    /// sample, stops (the player starts it again), as Android's do when they lose the audio focus or the headphones.
    private func sessionEvent(_ event: AudioSessionController.Event) {
        switch event {
        case .interruptionBegan, .mediaServicesReset:
            stopClip()
            stopPreview()
        case .routeChanged(let reason):
            if reason == .oldDeviceUnavailable {
                stopClip()
                stopPreview()
            }
        case .engineConfigurationChanged(let engine):
            engineChanged(engine)
        case .interruptionEnded:
            break
        }
    }

    /**
     * An engine stopped itself, its output having changed (a Bluetooth headset's call link, a new sample rate): if it's
     * the page's, the page stops, as it would never finish. Its own sessions report it here; with a game open, the
     * game's session does (AppModel.sessionEvent).
     */
    func engineChanged(_ engine: ObjectIdentifier?) {
        if let engine, engine == player?.engine.map(ObjectIdentifier.init) { stopClip() }
    }

    /// A file of the app's folder ("sting.m4a"), if the build has it.
    private func file(_ name: String) -> URL? {
        guard let url = folder?.appendingPathComponent(name, isDirectory: false),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }
}
