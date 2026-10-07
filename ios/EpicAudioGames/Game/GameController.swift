// GameController.kt: one game being played, its audio, its listening, and what the screen shows.

import EpicAppCore
import Foundation
import Observation
import os

/**
 * One game being played: the engine's game (a map's session, or Nuclear War), the audio, the listening, and what the
 * screen shows. A turn plays its clips while their lines appear in the feed; then the game waits for an answer
 * (listening by itself, as Alexa does, unless VoiceOver is on), shows its end, or leaves.
 *
 * An engine error doesn't crash the app: the feed gets a note and the game goes back to the list (L1).
 */
@Observable
final class GameController {
    let info: GameInfo

    private(set) var feed: [FeedItem] = []
    private(set) var speaking = false
    private(set) var listening = false
    private(set) var level: Float = 0
    private(set) var partial = ""
    private(set) var ask: Ask?
    private(set) var end: End?
    private(set) var paused = false
    /// The feed entry being spoken, and how many of its characters have been said (for the highlight).
    private(set) var activeEntry = -1
    private(set) var activeChars = 0
    var micWorks: Bool
    var micAllowed = false
    /// What went wrong, when an engine error ended the game (L1); the list tells the player.
    private(set) var failure: String?
    /**
     * The player is typing an answer (the text box has the focus): the mic doesn't open by itself, and stops if it's
     * listening, as typing is the answer coming.
     */
    @ObservationIgnored var typing = false {
        didSet { if typing { typed() } }
    }
    /// A tap on a chip this soon after a new question is the last tap's double (see [tap]); tests make it nothing.
    @ObservationIgnored var doubleTap: Duration = .milliseconds(500)
    /// Whether the game listens by itself once a question is asked: not while VoiceOver runs (it would hear
    /// VoiceOver), when the player opens the mic (D8).
    @ObservationIgnored var listensByItself: () -> Bool = { !A11y.voiceOver }
    /// The mic has opened (a sound, with VoiceOver on).
    @ObservationIgnored var onListen: () -> Void = { A11y.micOpened() }

    @ObservationIgnored private var game: any Play
    @ObservationIgnored private let fresh: () -> any Play
    @ObservationIgnored private let saves: any SaveStore
    @ObservationIgnored private let audio: any TurnPlaying
    @ObservationIgnored private let listener: any Listening
    @ObservationIgnored private let policy: OpenPolicy
    @ObservationIgnored private let onLeave: (GameController) -> Void
    @ObservationIgnored private var transcript: Transcript
    @ObservationIgnored private var turn: Turn?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var silences = 0
    /// When the latest turn began.
    @ObservationIgnored private var askedAt = ContinuousClock.now

    /**
     * [fresh] makes a new game of the same kind, for a save that can't be opened (L11). [onLeave] is called, once
     * this game's callbacks have returned, when the game goes back to the list.
     */
    init(
        info: GameInfo, game: any Play, fresh: @escaping () -> any Play, dependencies: GameDependencies,
        policy: OpenPolicy = .android, onLeave: @escaping (GameController) -> Void
    ) {
        self.info = info
        self.game = game
        self.fresh = fresh
        saves = dependencies.saves
        audio = dependencies.audio
        listener = dependencies.listener
        self.policy = policy
        self.onLeave = onLeave
        transcript = Transcript(who: game.who)
        micWorks = dependencies.listener.isAvailable
        audio.onFinished = { [weak self] in
            // A turn finishes once: a late call for one already finished (skipped, answered) is let go.
            guard let self, self.speaking else { return }
            self.finishTurn()
        }
        audio.onStalled = { [weak self] in
            // No audio at all (a call has it): the turn's lines and the question, waiting for a tap (L2).
            guard let self, self.speaking else { return }
            self.pause()
        }
        listener.events = ListenerEvents(
            partial: { [weak self] in self?.partial = $0 },
            heard: { [weak self] in self?.heard($0) },
            silence: { [weak self] in self?.silence() },
            level: { [weak self] in self?.level = $0 },
            unavailable: { [weak self] in
                self?.listening = false
                self?.micWorks = false
            },
            trouble: { [weak self] in self?.stopped() }
        )
    }

    func open() {
        let saved = savedPlace()
        do {
            let opening = try policy.open(game, saved: saved, fresh: fresh)
            if opening.clearSave { saves.clear(info.id) }
            game = opening.game
            // Picked up again, or back at the end it was left at.
            let atItsEnd = saved?.ended == true && opening.turn.end != nil && !opening.clearSave
            if opening.welcomeBack || atItsEnd { transcript.note("Welcome back!") }
            play(opening.turn)
        } catch {
            fail(error)
        }
    }

    /// Where a save is kept aside while its place isn't in the map (its pack missing, or not updated yet).
    private var parked: String { "\(info.id).parked" }

    /**
     * The save to open. In a map game, a save at a place the map doesn't have is kept aside rather than overwritten
     * by the game starting again; once the map has its place again (the pack back), it's picked up.
     */
    private func savedPlace() -> Saved? {
        let saved = saves.load(info.id)
        guard let session = game as? Session else { return saved }
        if let saved, !saved.ended, session.map.nodes[saved.node] == nil {
            saves.store(parked, saved)
            return saved
        }
        guard let back = saves.load(parked), session.map.nodes[back.node] != nil else { return saved }
        saves.store(info.id, back)
        saves.clear(parked)
        return back
    }

    func close() {
        ticker?.cancel()
        listener.release()
        audio.release()
    }

    // ----- Turns -----

    private func play(_ t: Turn) {
        turn = t
        ask = t.ask         // its chips show at once: an answer can cut the voice short
        askedAt = .now
        end = nil
        partial = ""
        stopListening()
        transcript.begin(t.steps)
        sync()
        speaking = true
        audio.play(t.steps)          // calls finishTurn when the turn's audio has played (later, even with none)
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.follow()
                do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
            }
        }
    }

    /// Shows each line as its time comes, and how far into the line the voice is.
    private func follow() {
        let position = audio.position()
        transcript.follow(position, clipsDone: position == nil ? audio.clipsDone() : 0)
        sync()
    }

    /// Copies the transcript to what the screen watches, only what changed (the highlight moves every 50 ms).
    private func sync() {
        if transcript.feed != feed { feed = transcript.feed }
        if transcript.activeEntry != activeEntry { activeEntry = transcript.activeEntry }
        if transcript.activeChars != activeChars { activeChars = transcript.activeChars }
    }

    private func finishTurn() {
        ticker?.cancel()
        transcript.revealAll()
        speaking = false
        transcript.clearActive()
        sync()
        guard let t = turn else { return }
        if t.quit {
            // "Leave" keeps the player's place (the question they answered), as an ended Alexa session did. A
            // plain quit isn't picked up again, but its save keeps the map's "keep" variables for next time.
            let s = game.save()
            saves.store(info.id, t.keep ? s : Saved(node: s.node, vars: s.vars, ended: true))
            leave()
        } else if let e = t.end {
            end = e
            saves.store(info.id, game.save())
        } else if let a = t.ask {
            ask = a
            saves.store(info.id, game.save())
            if !paused && !typing && listensByItself() { listen() }
        }
    }

    /// Plays what the engine says next; an engine error ends the game (L1).
    private func perform(_ next: () throws -> Turn) {
        guard let t = attempt(next) else { return }
        play(t)
    }

    /// What the engine says next, or nil when an engine error has ended the game (L1).
    private func attempt(_ next: () throws -> Turn) -> Turn? {
        do {
            return try next()
        } catch {
            fail(error)
            return nil
        }
    }

    /**
     * The engine couldn't go on: a note, and back to the list, which tells the player plainly (what went wrong goes to
     * the log). The save is the last turn's.
     */
    private func fail(_ error: any Error) {
        Self.log.error("\(self.info.id, privacy: .public) went wrong: \(String(describing: error), privacy: .public)")
        ticker?.cancel()
        audio.stop()
        speaking = false
        transcript.clearActive()
        transcript.note("Sorry, the game went wrong.")
        sync()
        failure = "\(info.title) went wrong and had to stop."
        leave()
    }

    private static let log = Logger(subsystem: "com.epicaudiogames.app", category: "game")

    // ----- Answers -----

    /**
     * A typed answer or a tapped chip (also while the voice is still talking: it stops). [shown] is what the reply
     * shows: a chip's label. Answering while paused carries on.
     */
    func answer(_ text: String, shown: String? = nil) {
        if Kt.trim(text).isEmpty || ask == nil { return }
        if AppCommands.isPause(text) {
            pause()
            return
        }
        paused = false
        stopListening()
        if speaking {
            audio.stop()
            ticker?.cancel()
            transcript.revealAll()
            speaking = false
            transcript.clearActive()
        }
        transcript.reply(shown ?? text)     // trimmed
        sync()
        silences = 0
        perform { try game.answer(text) }
    }

    /**
     * A tapped chip (the question's button): it sends its value, and the reply shows its label. A tap this soon after
     * a new question is the last tap's double (its chips show at once, where the last ones were), so it's let go.
     */
    func tap(_ button: AnswerButton) {
        if ContinuousClock.now - askedAt < doubleTap { return }
        answer(button.value, shown: button.label)
    }

    /// The recogniser's guesses, best first: the first that the question takes, else the best.
    private func heard(_ guesses: [String]) {
        guard listening else { return }         // a listen that's over
        listening = false
        partial = ""
        if ask == nil { return }
        if guesses.isEmpty {
            // Speech it couldn't make out: "sorry?" (the game's else); twice running, the game waits for a tap.
            transcript.reply("…")
            sync()
            silences += 1
            if silences >= 2 {
                pause()
                return
            }
            let at = turn?.node
            guard let t = attempt({ try game.answer("") }) else { return }
            // Only at the same question do they run on: a new one gets its own "say it again".
            if t.ask == nil || !(at.map { Kt.utf16Equal($0, t.node) } ?? false) { silences = 0 }
            play(t)
            return
        }
        let best = guesses.first { g in AppCommands.isPause(g) || ((try? game.understands(g)) ?? false) }
        answer(best ?? guesses[0])
    }

    /// Nobody answered: the question again; after a second silence, the game waits for a tap.
    private func silence() {
        guard listening else { return }         // a listen that's over
        listening = false
        partial = ""
        if ask == nil { return }
        silences += 1
        if silences >= 2 { pause() } else { perform { try game.silence() } }
    }

    /// Passing trouble, nothing to do with the player (the mic couldn't start): the listen just ends.
    private func stopped() {
        listening = false
        partial = ""
        level = 0
    }

    // ----- Listening -----

    /// Listens for an answer. Calling it while listening does nothing (L3).
    func listen() {
        if !micAllowed || !micWorks || ask == nil || speaking || listening { return }
        partial = ""
        listening = true
        listener.start(hints: ListenHints.of(ask))
        onListen()
    }

    private func stopListening() {
        listener.stop()
        listening = false
        level = 0
    }

    /// The mic allowed now (the player said yes, or turned it on in Settings): the game listens if it's waiting.
    func allowMic() {
        micAllowed = true
        if !paused && !typing && listensByItself() { listen() }
    }

    /// A key typed in the text box: listening stops, and the silences count from nothing again.
    func typed() {
        if listening { stopListening() }
        silences = 0
    }

    /// The mic button: listen now (cutting the voice short), or stop listening. After a failure, it tries again.
    func mic() {
        micWorks = true
        if listening {
            stopListening()
        } else if speaking {
            skip()              // which listens, unless the player is typing
            listen()
        } else {
            listen()
        }
    }

    /**
     * The game's one button, with no screen to look at: VoiceOver's Magic Tap, and the play/pause of the headphones and
     * the lock screen (NowPlaying). Paused, it carries on; speaking, it skips the voice; waiting for an answer, it
     * [talk]s (starts or stops listening; the screen's talk also asks for the mic). At an end, nothing.
     */
    func magicTap(talk: () -> Void) {
        if paused {
            carryOn()
        } else if speaking {
            skip()
        } else if end == nil {
            talk()
        }
    }

    /// Stops the voice and shows the rest of the turn's lines.
    func skip() {
        if !speaking { return }
        audio.stop()
        paused = false
        finishTurn()
    }

    /// "Stop", a second silence, the store sheet, or the audio taken (a call, headphones out): everything waits for a
    /// tap. Not the app going to the background or the phone locking: the game plays on (UIBackgroundModes audio).
    func pause() {
        paused = true
        stopListening()
        if speaking {
            audio.stop()
            finishTurn()        // the rest of the lines, and the question (or the end) waiting
        }
    }

    /// Back from a pause: the question again.
    func carryOn() {
        paused = false
        silences = 0
        if speaking { return }
        if ask != nil { perform { try game.silence() } }
    }

    // ----- Ends -----

    func playAgain() {
        transcript.clear()
        transcript.note("Starting again!")
        sync()
        paused = false
        silences = 0
        let e = end
        if e?.kind == "gameover", let retry = e?.retry {
            perform { try game.restart(at: retry) }
        } else {
            perform { try game.restart() }
        }
    }

    /// The menu's "Start again": the game from its very beginning.
    func startAgain() {
        audio.stop()
        transcript.clear()
        transcript.note("Starting again!")
        sync()
        paused = false
        silences = 0
        perform { try game.restart() }
    }

    var canGoOn: Bool { end?.canGoOn(in: game) ?? false }

    func nextChapter() {
        transcript.note("Next chapter")
        sync()
        paused = false
        silences = 0
        perform { try game.nextChapter() }
    }

    /// Back to the game list (posted, as it closes this game's audio from inside its own callbacks).
    func leave() {
        stopListening()
        audio.stop()
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.onLeave(self)
        }
    }
}
