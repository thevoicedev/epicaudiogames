// GameController.kt: one game being played, its audio, its listening, and what the screen shows.

import EpicAppCore
import Foundation
import Observation
import os

/**
 * One game being played: the engine's game (a map's session, or Nuclear War), the audio, the listening, and what the
 * screen shows. A turn plays its clips while their lines appear in the feed; then the game waits for an answer
 * (listening by itself, as Alexa does, unless [listensByItself] says not to), shows its end, or leaves.
 *
 * The microphone never opens without the listening sound ([listeningSounds]) and its tick ([onListen]), and the mic
 * hears nothing until the sound is over; it closes with the falling sound and a softer tick when the recogniser ends
 * the listen or the player turns it off, not when a new turn, typing, a pause or leaving stops it (docs/DESIGN.md ›
 * Sounds, haptics and the microphone; GameController.kt's opening and closing).
 *
 * An engine error doesn't crash the app: the feed gets a note and the game goes back to the list (L1).
 *
 * What happens in it goes to [onEvent], for the usage data (docs/DESIGN.md › Usage data): the game opened, an end
 * reached (and the free part's end), the next chapter, a restart, the mic's answer, the game going wrong, and, as it
 * closes, how it went (turns, time, and how many answers were spoken, typed and tapped, and how many questions went
 * unanswered: counts, never an answer). GameController.kt's.
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
    /// The mic has opened: a tick (the app's is as Settings › Vibrate when listening starts says).
    @ObservationIgnored var onListen: () -> Void = { Haptics.micOpened() }
    /// The mic has closed, the recogniser done or the player having turned it off: a softer tick (the app's, as
    /// Settings say). Not when the game stops listening itself.
    @ObservationIgnored var onListenEnd: () -> Void = { Haptics.micClosed() }

    /**
     * What the game's one button does now, and what VoiceOver calls it: the talking circle, Magic Tap and the
     * headphones' button ([CircleAction]). Nil at an end. GameController.kt's circleAction.
     */
    var circleAction: CircleAction? {
        CircleAction.of(
            paused: paused, speaking: speaking, listening: listening, end: end != nil, ask: ask != nil,
            micAllowed: micAllowed, micWorks: micWorks)
    }

    /**
     * Whether the game opens the mic by itself once a question is asked: the app asks MicPolicy (A11y.swift), by
     * default not with VoiceOver on, which the recogniser would hear. Asked each time, as the setting and VoiceOver can
     * change mid-game. The player can always open it: Magic Tap, the circle, the Talk button, the headphones' button
     * (D8). GameController.kt's listensByItself.
     */
    @ObservationIgnored private let listensByItself: () -> Bool
    /// Whether the listening sounds play (Settings › Listening sounds), asked as each would.
    @ObservationIgnored private let listeningSounds: () -> Bool
    /**
     * What happens in the game, for the usage data: an event's name and its details (Analytics/Events.swift makes
     * them; the app's Analytics.track takes them; by default, as in tests, they go nowhere). GameController.kt's
     * onEvent.
     */
    @ObservationIgnored private let onEvent: (String, [String: any Sendable]) -> Void

    @ObservationIgnored private var game: any Play
    @ObservationIgnored private let fresh: () -> any Play
    @ObservationIgnored private let saves: any SaveStore
    @ObservationIgnored private let audio: any TurnPlaying
    @ObservationIgnored private let listener: any Listening
    /// What plays the listening sounds (the game's TurnPlayer); none: the mic opens without them.
    @ObservationIgnored private let cues: (any CuePlaying)?
    @ObservationIgnored private let policy: OpenPolicy
    @ObservationIgnored private let onLeave: (GameController) -> Void
    @ObservationIgnored private var transcript: Transcript
    @ObservationIgnored private var turn: Turn?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var silences = 0
    /// When the latest turn began.
    @ObservationIgnored private var askedAt = ContinuousClock.now

    // This play of the game, for the usage data's game_leave as it closes: counts, never what was said.
    /// When it opened; nil if it never did.
    @ObservationIgnored private var openedAt: ContinuousClock.Instant?
    /// The turns played, the first one included: each turn's number, as it plays.
    @ObservationIgnored private var turns = 0
    @ObservationIgnored private var answersSpoken = 0
    @ObservationIgnored private var answersTyped = 0
    @ObservationIgnored private var answersTapped = 0
    /// Questions that got no answer (every silence that counted: [silences] starts again from each answer).
    @ObservationIgnored private var unanswered = 0
    /// The turn (by its number) whose end was reached last, or shown again as the game opened: its game_end goes once.
    @ObservationIgnored private var reached: Int?
    @ObservationIgnored private var closed = false

    /// How an answer came, for the usage data's counts.
    private enum Given {
        case spoken, typed, tapped
    }

    /**
     * [fresh] makes a new game of the same kind, for a save that can't be opened (L11). [onLeave] is called, once
     * this game's callbacks have returned, when the game goes back to the list. [listensByItself]: by default, always
     * (the app gives MicPolicy's answer); [listeningSounds]: by default, always (the app gives Settings'); [onEvent]:
     * by default, nothing.
     */
    init(
        info: GameInfo, game: any Play, fresh: @escaping () -> any Play, dependencies: GameDependencies,
        policy: OpenPolicy = .android, onLeave: @escaping (GameController) -> Void,
        listensByItself: @escaping () -> Bool = { true },
        listeningSounds: @escaping () -> Bool = { true },
        onEvent: @escaping (String, [String: any Sendable]) -> Void = { _, _ in }
    ) {
        self.info = info
        self.game = game
        self.fresh = fresh
        saves = dependencies.saves
        audio = dependencies.audio
        listener = dependencies.listener
        cues = dependencies.cues
        self.policy = policy
        self.onLeave = onLeave
        self.listensByItself = listensByItself
        self.listeningSounds = listeningSounds
        self.onEvent = onEvent
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
            unavailable: { [weak self] in self?.unavailable() },
            trouble: { [weak self] in self?.stopped() }
        )
    }

    func open() {
        openedAt = .now
        let saved = savedPlace()
        do {
            let opening = try policy.open(game, saved: saved, fresh: fresh)
            if opening.clearSave { saves.clear(info.id) }
            game = opening.game
            // Picked up again, or back at the end it was left at.
            let atItsEnd = saved?.ended == true && opening.turn.end != nil && !opening.clearSave
            let resumed = opening.welcomeBack || atItsEnd
            if resumed { transcript.note("Welcome back!") }
            emit(Events.gameOpen(info.id, resumed: resumed))
            // Opened at an end reached before (a chapter's end, its next chapter now here): not reached again.
            play(opening.turn, reachedBefore: resumed && opening.turn.end != nil)
        } catch {
            emit(Events.gameOpen(info.id, resumed: false))
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

    /// The game closes (left, or the app's model gone): how it went is usage data, once.
    func close() {
        if !closed {
            closed = true
            let seconds = openedAt.map { Int((ContinuousClock.now - $0).components.seconds) } ?? 0
            emit(Events.gameLeave(
                info.id, node: turn?.node, turns: turns, seconds: seconds, spoken: answersSpoken,
                typed: answersTyped, tapped: answersTapped, silences: unanswered))
        }
        ticker?.cancel()
        listener.release()
        audio.release()
    }

    /// Something happened in the game: to [onEvent].
    private func emit(_ e: Event) {
        onEvent(e.name, e.props)
    }

    // ----- Turns -----

    /// [reachedBefore]: the turn is an end the game was left at, opened again (its game_end went then).
    private func play(_ t: Turn, reachedBefore: Bool = false) {
        turn = t
        turns += 1
        if reachedBefore { reached = turns }
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
            if reached != turns {
                reached = turns
                ended(e, at: t.node)
            }
        } else if let a = t.ask {
            ask = a
            saves.store(info.id, game.save())
            if !paused && !typing && listensByItself() { listen() }
        }
    }

    /// An end reached, for the usage data: which, and where; and the free part's end, if a pack has what comes next.
    private func ended(_ e: End, at node: String) {
        emit(Events.gameEnd(info.id, kind: e.kind, node: node))
        if let pack = e.locked, !canGoOn { emit(Events.lockedEnd(info.id, pack: pack)) }
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
        emit(Events.gameError(info.id, node: turn?.node))
        transcript.note("Sorry, the game went wrong.")
        sync()
        failure = "\(info.title) went wrong and had to stop."
        leave()
    }

    private static let log = Logger(subsystem: "com.epicaudiogames.app", category: "game")

    // ----- Answers -----

    /**
     * A typed answer (also while the voice is still talking: it stops). [shown] is what the reply shows. Answering
     * while paused carries on.
     */
    func answer(_ text: String, shown: String? = nil) {
        give(text, shown: shown, how: .typed)
    }

    /// An answer, spoken, typed or tapped ([how], which only the usage data's counts care about).
    private func give(_ text: String, shown: String?, how: Given) {
        if Kt.trim(text).isEmpty || ask == nil { return }
        if AppCommands.isPause(text) {
            pause()
            return
        }
        switch how {
        case .spoken: answersSpoken += 1
        case .typed: answersTyped += 1
        case .tapped: answersTapped += 1
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
        give(button.value, shown: button.label, how: .tapped)
    }

    /// The recogniser's guesses, best first: the first that the question takes, else the best.
    private func heard(_ guesses: [String]) {
        guard listening else { return }         // a listen that's over
        listening = false
        partial = ""
        closing()
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
        give(best ?? guesses[0], shown: nil, how: .spoken)
    }

    /// Nobody answered (for the whole time to answer: the listener waits it out): the question again; after a second
    /// silence, the game waits for a tap.
    private func silence() {
        guard listening else { return }         // a listen that's over
        listening = false
        partial = ""
        closing()
        if ask == nil { return }
        silences += 1
        unanswered += 1
        if silences >= 2 { pause() } else { perform { try game.silence() } }
    }

    /// Passing trouble, nothing to do with the player (the mic couldn't start): the listen just ends.
    private func stopped() {
        if listening { closing() }
        listening = false
        partial = ""
        level = 0
    }

    /// No recogniser that can work now (none for the language, or no connection): answers are typed or tapped.
    private func unavailable() {
        if listening { closing() }
        listening = false
        micWorks = false
    }

    // ----- Listening -----

    /**
     * Listens for an answer: the listening sound first (Settings › Listening sounds), then the listener, which hears
     * the mic only from when the sound will have been heard out (at once, with the sound off or unable to play); and
     * the tick. However the mic opens (by itself, the Talk button, the circle, Magic Tap, the headphones' button), it
     * comes here. Calling it while listening does nothing (L3).
     */
    func listen() {
        if !micAllowed || !micWorks || ask == nil || speaking || listening { return }
        partial = ""
        listening = true
        let after = listeningSounds() ? cues?.play(.listenStart) : nil
        listener.start(hints: ListenHints.of(ask), after: after)
        onListen()
    }

    /**
     * The mic closing because the recogniser ended the listen or the player turned it off: the falling sound and a
     * softer tick, as Settings say. Not when the game stops listening itself (a new turn, typing, a pause, leaving).
     * GameController.kt's closing.
     */
    private func closing() {
        onListenEnd()
        if listeningSounds() { _ = cues?.play(.listenStop) }
    }

    private func stopListening() {
        listener.stop()
        listening = false
        level = 0
    }

    /**
     * The mic allowed now (the player said yes, or turned it on in Settings): the game listens if it's waiting and
     * listens by itself. When the player asked for the mic with a tap ([listen]: the Talk button, the circle, Magic
     * Tap), it does what the tap would have done with the mic allowed, cutting the voice short, whatever
     * [listensByItself] says; but not over a pause. GameController.kt's allowMic.
     */
    func allowMic(listen: Bool = false) {
        micAllowed = true
        if paused { return }
        if listen {
            if speaking { skip() }
            self.listen()
        } else if !typing && listensByItself() {
            self.listen()
        }
    }

    /**
     * What the player said to iOS's microphone question (the mic and speech recognition), asked as the game opened or
     * by a tap: usage data. GameController.kt's micAnswered.
     */
    func micAnswered(granted: Bool) {
        emit(Events.micPermission(granted: granted, where: .game))
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
            closing()           // the player turned it off
        } else if speaking {
            skip()              // which listens, unless the player is typing
            listen()
        } else {
            listen()
        }
    }

    /**
     * The game's one button: the talking circle, VoiceOver's Magic Tap, and the play/pause of the headphones and the
     * lock screen (NowPlaying). Paused, it carries on; speaking, it skips the voice; waiting for an answer, it [talk]s
     * (starts or stops listening; the screen's talk also asks for the mic, as the Talk button does). At an end,
     * nothing. What it does, and its name, is [circleAction]. GameController.kt's circle.
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
        emit(Events.gameRestart(info.id))
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
        emit(Events.gameRestart(info.id))
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
        if let next = end?.next { emit(Events.chapterNext(info.id, next: next)) }
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
