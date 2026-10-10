// WearBridge.kt's messages (the phone's side of the Wear OS app, through the Wearable Data Layer): what the iPhone
// tells the Apple Watch app about its game, and what the watch's two buttons ask of it, as WatchConnectivity carries
// them. The watch app links no package, so ios/EpicWatch/WatchLink.swift is this file again, word for word
// (WatchLinkTests checks it). It imports nothing, so it builds the same in both.

/**
 * The game on the iPhone, as the watch shows it (docs/DESIGN.md › Watches): its title, what it's doing in words, its
 * one button named as on the iPhone (the talking circle's CircleAction), whether the microphone is open (the watch
 * buzzes as it opens and as it closes), and whether Pause can do anything. The iPhone makes it (WatchBridge.swift) and
 * the watch shows it (PhoneLink.swift, WatchView.swift). WatchConnectivity carries it as property-list values
 * ([context(at:)]); [from(_:)] reads them back.
 */
nonisolated public struct WatchState: Equatable, Sendable {
    /// The open game's title; empty when no game is open (the watch then says to open one on the iPhone).
    public var title: String
    /// What the game is doing, in words: "Speaking", "Your turn", "Listening…", "Paused" or "Wait for the question";
    /// at an end, its heading ("Chapter complete"); empty when no game is open.
    public var state: String
    /// What the big button does, for its icon; nil when there's nothing to press (no game, an end), or the iPhone named
    /// something this watch app doesn't know (its button still shows, by [label]).
    public var action: WatchAction?
    /// The big button's name, the same words as on the iPhone: "Skip", "Talk", "Stop listening", "Carry on", "Talk (the
    /// microphone is off)"; empty when there's no button.
    public var label: String
    /// The big button can do something now.
    public var enabled: Bool
    /// The microphone is open.
    public var listening: Bool
    /// Pause can do something: a game is open, and it's neither paused nor at an end.
    public var canPause: Bool

    public init(
        title: String, state: String, action: WatchAction?, label: String, enabled: Bool, listening: Bool,
        canPause: Bool
    ) {
        self.title = title
        self.state = state
        self.action = action
        self.label = label
        self.enabled = enabled
        self.listening = listening
        self.canPause = canPause
    }

    /// No game open.
    public static let none = WatchState(
        title: "", state: "", action: nil, label: "", enabled: false, listening: false, canPause: false)

    /// A game is open on the iPhone.
    public var gameOpen: Bool { !title.isEmpty }

    /**
     * As WatchConnectivity carries it (property-list values only), with [at]: when the iPhone made it, in seconds since
     * 1970, so that one arriving after a newer one (the session's two ways of carrying it can cross) is let go
     * ([WatchInbox]).
     */
    public func context(at: Double) -> [String: Any] {
        [
            WatchKey.title: title, WatchKey.state: state, WatchKey.action: action?.rawValue ?? "",
            WatchKey.label: label, WatchKey.enabled: enabled, WatchKey.listening: listening,
            WatchKey.canPause: canPause, WatchKey.at: at,
        ]
    }

    /// The state in [context], and when the iPhone made it; nil for anything else (the context is empty until the
    /// iPhone has said something).
    public static func from(_ context: [String: Any]) -> (state: WatchState, at: Double)? {
        guard let title = context[WatchKey.title] as? String,
              let state = context[WatchKey.state] as? String,
              let action = context[WatchKey.action] as? String,
              let label = context[WatchKey.label] as? String,
              let enabled = context[WatchKey.enabled] as? Bool,
              let listening = context[WatchKey.listening] as? Bool,
              let canPause = context[WatchKey.canPause] as? Bool,
              let at = context[WatchKey.at] as? Double
        else { return nil }
        let made = WatchState(
            title: title, state: state, action: WatchAction(rawValue: action), label: label, enabled: enabled,
            listening: listening, canPause: canPause)
        return (made, at)
    }
}

/**
 * What the big button does, as the iPhone's CircleAction says (Accessibility/A11y.swift, the same names): the watch
 * picks its icon by it, as the iPhone's talking circle picks its badge.
 */
nonisolated public enum WatchAction: String, CaseIterable, Sendable {
    /// Paused: the game carries on.
    case carryOn
    /// Speaking: the voice is cut short.
    case skip
    /// Listening: the microphone closes.
    case stopListening
    /// The player's turn: the microphone opens.
    case talk
    /// The microphone isn't allowed on the iPhone, and only the iPhone can ask for it.
    case micRefused
    /// No speech recognition on the iPhone just now: a press tries again.
    case noRecognition
    /// Nothing to do until the question is asked.
    case wait
}

/**
 * What the watch's buttons ask of the iPhone, as a message: the big button ([primary]: what Magic Tap does on the
 * iPhone) or Pause.
 */
nonisolated public enum WatchCommand: String, CaseIterable, Sendable {
    case primary
    case pause

    /// As WatchConnectivity carries it.
    public var message: [String: Any] { [WatchKey.command: rawValue] }

    /// The command in a message from the watch; nil for anything else.
    public init?(message: [String: Any]) {
        guard let name = message[WatchKey.command] as? String, let command = WatchCommand(rawValue: name) else {
            return nil
        }
        self = command
    }
}

/**
 * The watch's buzz as the microphone opens or closes (docs/DESIGN.md › Watches): the cue for a player who can't hear
 * the listening sound. watchOS's start haptic, then its stop haptic (PhoneLink.swift).
 */
nonisolated public enum WatchHaptic: Equatable, Sendable {
    case listeningStarted
    case listeningStopped
}

/**
 * The iPhone's states as the watch takes them in: the newest shows, and one the iPhone made before it, arriving late
 * the other way (a message and the application context can cross), is let go; unless it's older by more than
 * [clockJump], which only the iPhone's clock being put back can do. The microphone opening or closing buzzes
 * ([WatchHaptic]), except in the first state the watch has (as its app opens, nothing has just happened) and as the
 * game closes (leaving a game plays no sound on the iPhone either).
 */
nonisolated public struct WatchInbox: Sendable {
    /// What shows: no game, until the iPhone says.
    public private(set) var state = WatchState.none
    /// When the iPhone made [state]; nil until it has said.
    public private(set) var at: Double?

    /// Seconds: a state this much older than the one showing is the iPhone's clock put back, not a late one.
    public static let clockJump = 60.0

    public init() {}

    /// Takes [new], made [at]: whether it shows now, and the buzz it calls for.
    public mutating func take(_ new: WatchState, at: Double) -> (shown: Bool, haptic: WatchHaptic?) {
        if let last = self.at, at < last, last - at < Self.clockJump { return (false, nil) }
        let first = self.at == nil
        let wasListening = state.listening
        state = new
        self.at = at
        guard !first, new.gameOpen, wasListening != new.listening else { return (true, nil) }
        return (true, new.listening ? .listeningStarted : .listeningStopped)
    }
}

/// The dictionaries' keys.
nonisolated enum WatchKey {
    static let title = "title"
    static let state = "state"
    static let action = "action"
    static let label = "label"
    static let enabled = "enabled"
    static let listening = "listening"
    static let canPause = "canPause"
    static let at = "at"
    static let command = "command"
}
