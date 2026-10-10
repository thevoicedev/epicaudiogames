// MicPolicy.kt: whether the game opens the mic by itself, and what its one button does (MicPolicy, CircleAction).
// A11y has no Kotlin counterpart: VoiceOver and the mic (the plan's D8), its announcements and the focus delay.

import SwiftUI
import UIKit

/**
 * With VoiceOver on, the game doesn't open the mic by itself after a question (unless Settings say so, [MicPolicy]):
 * it would hear VoiceOver reading the screen. The player opens it (Magic Tap, the talking circle, or the Talk button),
 * and the listening sound says it's listening, as the ring can't be seen: the app's own, for everyone, however the mic
 * opens (GameController.listen; it took the place of the system's "begin recording" sound, which played only with
 * VoiceOver and after the recogniser was already listening).
 */
enum A11y {
    /// Read afresh each time it's asked (VoiceOver can be turned on and off mid-game).
    static var voiceOver: Bool { UIAccessibility.isVoiceOverRunning }

    /**
     * A status message for VoiceOver (a purchase done, a download finished or failed, the mic allowed): queued behind
     * what it's saying, never cutting it short. Never while the game is [listening]: the recogniser would hear it
     * (docs/DESIGN.md › Everywhere › Status messages). Android shows the same words as polite live-region text.
     */
    static func announce(_ message: String, unlessListening listening: Bool) {
        guard !listening, !message.isEmpty else { return }
        let queued = NSAttributedString(string: message, attributes: [.accessibilitySpeechQueueAnnouncement: true])
        UIAccessibility.post(notification: .announcement, argument: queued)
    }

    /**
     * How long after the end panel or the pause appears VoiceOver moves to its heading (docs/DESIGN.md › Everywhere ›
     * Focus): by then it's laid out, and VoiceOver has said what changed. GameScreen.kt's FOCUS_DELAY_MS.
     */
    static let focusDelay: Duration = .milliseconds(300)

    /**
     * The same after a page is pushed or a sheet rises (a Help topic, the help sheet): iOS moves VoiceOver to the new
     * screen itself as the transition ends (about 350 ms), so the heading is focused once that's done, not before.
     */
    static let focusAfterTransition: Duration = .milliseconds(700)

    /**
     * With VoiceOver on, how long after its tap Listen starts reading (a Help topic, the welcome) and Settings plays
     * its samples, so VoiceOver's own sound for the tap comes first, not over the voice (docs/DESIGN.md › Help).
     * HelpScreen.kt's LISTEN_DELAY_MS.
     */
    static let listenDelay: Duration = .milliseconds(400)

    /**
     * Voice Control's names for a control, each once: the first is the one it shows ("Show names"), so it's what
     * VoiceOver says; then the words a player might know it by (docs/DESIGN.md: the circle's "Skip", "Talk" and
     * "Picture"; the mic's "Talk", "Microphone" and "Mic").
     */
    static func inputLabels(_ labels: String...) -> [Text] {
        var once: [String] = []
        for label in labels where !once.contains(label) { once.append(label) }
        return once.map { Text(verbatim: $0) }
    }
}

/**
 * Whether the game opens the mic by itself once a question is asked (Settings › Microphone › Open the microphone by
 * itself). By default it doesn't with a screen reader on ([A11y.voiceOver]): the recogniser would hear VoiceOver
 * reading the screen, so the player opens it (Magic Tap, the talking circle, the Talk button, the headphones' button).
 * Android: listensByItself in MicPolicy.kt, with TalkBack.
 */
enum MicPolicy {
    static func listensByItself(policy: MicAuto, screenReaderOn: Bool) -> Bool {
        switch policy {
        case .notWithScreenReader: !screenReaderOn
        case .always: true
        case .never: false
        }
    }
}

/**
 * What the game's one button does now, with the name and state VoiceOver says for it (docs/DESIGN.md's table): the
 * talking circle, Magic Tap and the headphones' button (CircleAction in MicPolicy.kt, which gives Android's
 * notification button too); the Talk button takes its name from the same table ([mic]). [enabled] is false while
 * there's nothing to do yet.
 */
enum CircleAction: CaseIterable {
    case carryOn
    case skip
    case stopListening
    case talk
    /// The mic isn't allowed: a tap asks for it, or leads to Settings, as the Talk button does.
    case micRefused
    /// No speech recogniser that works (none for the language, or it needs a network there isn't): a tap tries again.
    case noRecognition
    /// A turn being worked out, with no question yet.
    case wait

    /// Its name: what VoiceOver says, and Voice Control answers to.
    var label: String {
        switch self {
        case .carryOn: "Carry on"
        case .skip: "Skip"
        case .stopListening: "Stop listening"
        case .talk, .wait: "Talk"
        case .micRefused: "Talk (the microphone is off)"
        case .noRecognition: "Talk (speech recognition isn't available)"
        }
    }

    /// What VoiceOver says the game is doing (the circle's value).
    var state: String {
        switch self {
        case .carryOn: "Paused"
        case .skip: "Speaking"
        case .stopListening: "Listening"
        case .talk, .micRefused, .noRecognition: "Your turn"
        case .wait: "Wait for the question"
        }
    }

    var enabled: Bool { self != .wait }

    /**
     * The first that applies: carry on when paused, skip while the game speaks, stop while it listens; at an end,
     * nothing (nil: the circle is just a picture); then talk once a question is asked, or the reason it can't.
     */
    static func of(
        paused: Bool, speaking: Bool, listening: Bool, end: Bool, ask: Bool, micAllowed: Bool, micWorks: Bool
    ) -> CircleAction? {
        if paused { return .carryOn }
        if speaking { return .skip }
        if listening { return .stopListening }
        if end { return nil }
        if !ask { return .wait }
        if !micAllowed { return .micRefused }
        if !micWorks { return .noRecognition }
        return .talk
    }

    /**
     * The Talk button's: what the circle does once a question is asked, whatever the voice is doing (while it speaks,
     * the Talk button cuts it short and listens, so it's Talk, never Skip). It's under the pause when paused, and gone
     * at an end, so neither applies (and it's never nil).
     */
    static func mic(listening: Bool, micAllowed: Bool, micWorks: Bool) -> CircleAction {
        of(paused: false, speaking: false, listening: listening, end: false, ask: true, micAllowed: micAllowed,
           micWorks: micWorks) ?? .talk
    }
}
