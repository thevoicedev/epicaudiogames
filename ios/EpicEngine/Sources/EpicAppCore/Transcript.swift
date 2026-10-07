// GameController.kt's feed (lines 27-36, 77-93 and 136-179): the transcript, each line shown as its time comes.

import Foundation

/// One entry in the game's transcript. Its id stays the same when a line joins it, so the screen keeps its place.
public struct FeedItem: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// A line of the game, shown as it is spoken: the speaker's key, the name shown, and the text.
        case spoken(who: String, name: String, text: String)
        /// What the player said, typed or tapped.
        case reply(String)
        case note(String)
    }

    public let id: UUID
    public fileprivate(set) var kind: Kind

    public init(_ kind: Kind, id: UUID = UUID()) {
        self.kind = kind
        self.id = id
    }

    public var text: String {
        switch kind {
        case .spoken(_, _, let text), .reply(let text), .note(let text): text
        }
    }
}

/**
 * The game's transcript and which of its lines is being spoken. A turn's lines appear as the audio reaches them;
 * a line that carries on a sentence (the same speaker's previous line in this turn ends with a comma, or is marked to
 * carry on, as in a list of names made of one clip per name) joins that entry. The highlight counts the characters
 * said so far, in UTF-16 units as Kotlin's String.length does, spread evenly over the line's length in time.
 */
public struct Transcript: Sendable {
    public private(set) var feed: [FeedItem] = []
    /// The feed entry being spoken (-1: none), and how many of its characters have been said (for the highlight).
    public private(set) var activeEntry = -1
    public private(set) var activeChars = 0

    /// Speaker keys to the names shown (Play.who).
    private let who: LinkedMap<String>
    private var clipLines: [[Line]] = []
    private var revealed: [Int] = []
    private var entryOfLine: [LineKey: Int] = [:]
    /// Where each line starts in its feed entry: a line can carry on the one before it (see [reveal]).
    private var offsetOfLine: [LineKey: Int] = [:]
    private var turnStart = 0
    /// The last line shown carries on into the next one (a list said a name at a time).
    private var carryOn = false

    private struct LineKey: Hashable, Sendable {
        let clip: Int
        let line: Int
    }

    public init(who: LinkedMap<String>) {
        self.who = who
    }

    // ----- Turns -----

    /// A new turn (GameController.play): its clips' lines, none shown yet.
    public mutating func begin(_ steps: [Step]) {
        clipLines = steps.compactMap { if case .play(let clip) = $0 { clip.lines } else { nil } }
        revealed = Array(repeating: 0, count: clipLines.count)
        entryOfLine.removeAll()
        offsetOfLine.removeAll()
        turnStart = feed.count
        carryOn = false
    }

    /// Shows each line as its time comes, and how far into the line the voice is (GameController.follow).
    /// [position]: the clip playing and the seconds into it, nil in a pause; [clipsDone]: the clips before a pause.
    public mutating func follow(_ position: ClipPosition?, clipsDone: Int) {
        guard let position else {
            for c in 0..<max(clipsDone, 0) { reveal(c, .greatestFiniteMagnitude) }     // a pause: what came before it
            return
        }
        let clip = position.clip
        let t = position.seconds
        for c in 0..<max(clip, 0) { reveal(c, .greatestFiniteMagnitude) }
        reveal(clip, t)
        guard clipLines.indices.contains(clip) else { return }
        let lines = clipLines[clip]
        guard let i = lines.lastIndex(where: { $0.at <= t }) else { return }
        let line = lines[i]
        let key = LineKey(clip: clip, line: i)
        activeEntry = entryOfLine[key] ?? -1
        let progress = line.len > 0 ? Self.coerceIn((t - line.at) / line.len, 0.0, 1.0) : 1.0
        activeChars = (offsetOfLine[key] ?? 0) + Self.toInt(Double(line.text.utf16.count) * progress)
    }

    /// The rest of the turn's lines, all at once (its end, a skip, or an answer cutting it short).
    public mutating func revealAll() {
        for c in clipLines.indices { reveal(c, .greatestFiniteMagnitude) }
    }

    /// Nothing is being spoken now.
    public mutating func clearActive() {
        activeEntry = -1
    }

    // ----- Other entries -----

    /// What the player said, typed or tapped, trimmed (for a tapped button, its label).
    public mutating func reply(_ said: String) {
        feed.append(FeedItem(.reply(Kt.trim(said))))
    }

    public mutating func note(_ text: String) {
        feed.append(FeedItem(.note(text)))
    }

    /// An empty feed (the game starting again).
    public mutating func clear() {
        feed.removeAll()
    }

    // ----- Showing lines -----

    /**
     * Shows the clip's lines whose time has come. A line that carries on a sentence (the same speaker's previous line
     * in this turn ends with a comma, or is marked to carry on) joins that entry.
     */
    private mutating func reveal(_ clip: Int, _ t: Double) {
        guard clipLines.indices.contains(clip) else { return }
        let lines = clipLines[clip]
        while revealed[clip] < lines.count && lines[revealed[clip]].at <= t {
            let line = lines[revealed[clip]]
            let key = LineKey(clip: clip, line: revealed[clip])
            if let last = feed.last, case .spoken(let lastWho, let name, let lastText) = last.kind,
               feed.count - 1 >= turnStart, Kt.utf16Equal(lastWho, line.who),
               lastText.utf16.last == 0x2C || carryOn {
                entryOfLine[key] = feed.count - 1
                offsetOfLine[key] = lastText.utf16.count + 1
                feed[feed.count - 1].kind = .spoken(who: lastWho, name: name, text: "\(lastText) \(line.text)")
            } else {
                entryOfLine[key] = feed.count
                offsetOfLine[key] = 0
                feed.append(FeedItem(.spoken(who: line.who, name: who[line.who] ?? line.who, text: line.text)))
            }
            carryOn = line.more
            revealed[clip] += 1
        }
    }

    // ----- The highlight -----

    /**
     * Where a spoken entry's highlight ends (GameScreen.kt's Spoken): at the first space at or after [saidChars],
     * else the end of the text, in UTF-16 units. The words before it are said; the rest are still to come.
     */
    public static func highlightCut(_ text: String, saidChars: Int) -> Int {
        let u = text.utf16
        var i = max(saidChars, 0)
        guard i < u.count else { return u.count }
        var index = u.index(u.startIndex, offsetBy: i)
        while index != u.endIndex {
            if u[index] == 0x20 { return i }
            u.formIndex(after: &index)
            i += 1
        }
        return u.count
    }

    /// The text said so far and the text still to come, cut at [highlightCut].
    public static func highlight(_ text: String, saidChars: Int) -> (said: String, rest: String) {
        let u = Array(text.utf16)
        let cut = highlightCut(text, saidChars: saidChars)
        return (String(decoding: u[..<cut], as: UTF16.self), String(decoding: u[cut...], as: UTF16.self))
    }

    /// Kotlin's Double.coerceIn: NaN goes through.
    private static func coerceIn(_ x: Double, _ low: Double, _ high: Double) -> Double {
        if x < low { return low }
        if x > high { return high }
        return x
    }

    /// Kotlin's Double.toInt(): NaN is 0, the rest truncated and saturated.
    private static func toInt(_ d: Double) -> Int {
        if d.isNaN { return 0 }
        if d >= 2147483647.0 { return Int(Int32.max) }
        if d <= -2147483648.0 { return Int(Int32.min) }
        return Int(d)
    }
}
