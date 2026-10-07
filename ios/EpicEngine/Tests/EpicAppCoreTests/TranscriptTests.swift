// Transcript.swift: GameController.kt's reveal and follow, and GameScreen.kt's highlight cut, in UTF-16 units.

import Testing

@testable import EpicAppCore

struct TranscriptTests {
    private static let who: LinkedMap<String> = ["GRIBBO": "Gribbo", "PIP": "Pip", "NARRATOR": "", "HOST": ""]

    private func texts(_ t: Transcript) -> [String] { t.feed.map(\.text) }

    private func at(_ clip: Int, _ seconds: Double) -> ClipPosition { ClipPosition(clip: clip, seconds: seconds) }

    /// A line after the same speaker's comma joins the entry; its highlight starts after the comma and a space,
    /// and counts UTF-16 units (é, — and ’ are one each; e + U+0301 is two).
    @Test func aLineAfterACommaJoinsWithAccentsDashesAndQuotes() {
        var t = Transcript(who: Self.who)
        let second = "cr\u{E8}me br\u{FB}l\u{E9}e \u{2014} the best\u{2019}s here"
        #expect(second.utf16.count == 30)
        t.begin([clip("c", [line(0, 1, "GRIBBO", "Caf\u{E9},"), line(1, 2, "GRIBBO", second)])])

        t.follow(at(0, 0.5), clipsDone: 0)
        #expect(t.feed.map(\.kind) == [.spoken(who: "GRIBBO", name: "Gribbo", text: "Caf\u{E9},")])
        #expect(t.activeEntry == 0)
        #expect(t.activeChars == 2)                 // 5 * 0.5, truncated
        let id = t.feed[0].id

        t.follow(at(0, 2.0), clipsDone: 0)
        #expect(texts(t) == ["Caf\u{E9}, \(second)"])
        #expect(t.feed[0].id == id)
        #expect(t.activeEntry == 0)
        #expect(t.activeChars == 6 + 15)            // after "Café, ", then 30 * 0.5
        t.follow(at(0, 2.998), clipsDone: 0)
        #expect(t.activeChars == 6 + 29)            // 30 * 0.999, truncated
        t.follow(at(0, 9.0), clipsDone: 0)
        #expect(t.activeChars == 36)                // clamped: the whole entry
        #expect(t.feed[0].text.utf16.count == 36)

        var d = Transcript(who: Self.who)
        d.begin([clip("c", [line(0, 1, "PIP", "Un cafe\u{301},"), line(1, 1, "PIP", "s'il vous pla\u{EE}t")])])
        d.follow(at(0, 1.5), clipsDone: 0)
        #expect(texts(d) == ["Un cafe\u{301}, s'il vous pla\u{EE}t"])
        #expect(d.activeChars == 10 + 7)            // "Un café," is 9 units; 15 * 0.5
    }

    @Test func onlyTheSameSpeakerAfterACommaJoins() {
        var t = Transcript(who: Self.who)
        t.begin([clip("c", [
            line(0, 1, "GRIBBO", "Hello."), line(1, 1, "GRIBBO", "Again,"), line(2, 1, "PIP", "Me too,"),
            line(3, 1, "PIP", "and me"), line(4, 1, "ZED", "Who?"), line(5, 1, "NARRATOR", "Later,"),
        ])])
        t.revealAll()
        #expect(t.feed.map(\.kind) == [
            .spoken(who: "GRIBBO", name: "Gribbo", text: "Hello."),
            .spoken(who: "GRIBBO", name: "Gribbo", text: "Again,"),
            .spoken(who: "PIP", name: "Pip", text: "Me too, and me"),
            .spoken(who: "ZED", name: "ZED", text: "Who?"),
            .spoken(who: "NARRATOR", name: "", text: "Later,"),
        ])
    }

    /// A line marked to carry on (a list said a name at a time, a clip per name) joins the next, across clips.
    @Test func aLineMarkedToCarryOnJoinsTheNext() {
        var t = Transcript(who: Self.who)
        t.begin([
            clip("c0", [line(0, 1, "HOST", "Paris", more: true)]), clip("c1", [line(0, 1, "HOST", "Lyon", more: true)]),
            clip("c2", [line(0, 1, "HOST", "and Nice.")]), clip("c3", [line(0, 1, "HOST", "Next")]),
        ])
        t.follow(at(1, 0.5), clipsDone: 1)
        #expect(texts(t) == ["Paris Lyon"])
        #expect(t.activeEntry == 0)
        #expect(t.activeChars == 6 + 2)
        t.revealAll()
        #expect(texts(t) == ["Paris Lyon and Nice.", "Next"])
    }

    /// Only this turn's entries are joined: a comma (or a carry-on) at the end of the last turn starts afresh.
    @Test func linesDontJoinTheLastTurn() {
        var t = Transcript(who: Self.who)
        t.begin([clip("c", [line(0, 1, "GRIBBO", "Hello,"), line(1, 1, "GRIBBO", "and", more: true)])])
        t.revealAll()
        t.begin([clip("c", [line(0, 1, "GRIBBO", "there")])])
        t.revealAll()
        #expect(texts(t) == ["Hello, and", "there"])

        t.begin([clip("c", [line(0, 1, "PIP", "One,"), line(5, 1, "PIP", "two")])])
        t.follow(at(0, 1), clipsDone: 0)
        t.reply("three")
        t.follow(at(0, 6), clipsDone: 0)
        #expect(texts(t) == ["Hello, and", "there", "One,", "three", "two"])
        #expect(t.activeEntry == 4)
    }

    /// The highlight is spread evenly over the line's time, truncated and clamped, in UTF-16 units (🍜 is two).
    @Test func theHighlightCountsUTF16Units() {
        var t = Transcript(who: Self.who)
        t.begin([clip("c", [line(1.0, 2.0, "PIP", "\u{1F35C} noodles"), line(4.0, 0, "PIP", "Hi there")])])
        t.follow(at(0, 0.5), clipsDone: 0)
        #expect(t.feed.isEmpty)
        #expect(t.activeEntry == -1)
        t.follow(at(0, 1.5), clipsDone: 0)
        #expect(t.activeEntry == 0)
        #expect(t.activeChars == 2)                 // 10 * 0.25
        t.follow(at(0, 2.0), clipsDone: 0)
        #expect(t.activeChars == 5)
        t.follow(at(0, 2.998), clipsDone: 0)
        #expect(t.activeChars == 9)
        t.follow(at(0, 3.5), clipsDone: 0)
        #expect(t.activeChars == 10)
        t.follow(at(0, 4.0), clipsDone: 0)          // a line with no length is said at once
        #expect(texts(t) == ["\u{1F35C} noodles", "Hi there"])
        #expect(t.activeEntry == 1)
        #expect(t.activeChars == 8)
    }

    /// In a pause, the clips before it show whole; the highlight stays where it was.
    @Test func aPauseShowsTheClipsBeforeIt() {
        var t = Transcript(who: Self.who)
        t.begin([
            clip("c0", [line(0, 1, "PIP", "One."), line(0.5, 1, "PIP", "Two.")]), .pause(1),
            clip("c1", [line(0, 1, "PIP", "Three.")]),
        ])
        t.follow(at(0, 0.2), clipsDone: 0)
        #expect(texts(t) == ["One."])
        #expect(t.activeChars == 0)
        t.follow(nil, clipsDone: 1)
        #expect(texts(t) == ["One.", "Two."])
        #expect(t.activeEntry == 0)
        t.follow(at(1, 0), clipsDone: 1)
        #expect(texts(t) == ["One.", "Two.", "Three."])
        #expect(t.activeEntry == 2)
        t.clearActive()
        #expect(t.activeEntry == -1)
        t.follow(at(7, 1), clipsDone: 0)            // a clip the turn hasn't got: nothing more
        #expect(t.feed.count == 3)
    }

    /// Replies show trimmed (Kotlin's trim: no-break and ideographic spaces too); a tapped button shows its value.
    @Test func repliesAndNotes() {
        var t = Transcript(who: [:])
        let button = AnswerButton(label: "Answer", value: "yes")
        t.reply(button.value)
        t.reply("  the USA \n")
        t.reply("\u{3000}none\u{A0}")
        t.reply("\u{2026}")
        t.note("Welcome back!")
        #expect(t.feed.map(\.kind) == [.reply("yes"), .reply("the USA"), .reply("none"), .reply("\u{2026}"),
                                       .note("Welcome back!")])
        #expect(Set(t.feed.map(\.id)).count == 5)
        t.clear()
        #expect(t.feed.isEmpty)
    }

    /// GameScreen.kt: the words said end at the first space at or after the characters said, else the text's end.
    @Test func theHighlightCutsAtASpace() {
        let s = "Hello there friend"
        let cuts = [0, 3, 5, 6, 12, 18, 100, -4].map { Transcript.highlightCut(s, saidChars: $0) }
        #expect(cuts == [5, 5, 5, 11, 18, 18, 18, 5])
        let a = Transcript.highlight("Hello there", saidChars: 2)
        #expect(a.said == "Hello")
        #expect(a.rest == " there")
        let b = Transcript.highlight("\u{1F35C}\u{1F35C} hot", saidChars: 1)
        #expect(b.said == "\u{1F35C}\u{1F35C}")
        #expect(b.rest == " hot")
        let c = Transcript.highlight("", saidChars: 0)
        #expect(c.said.isEmpty && c.rest.isEmpty)
        #expect(Transcript.highlightCut("caf\u{E9} \u{2014} ok", saidChars: 5) == 6)
        #expect(Transcript.highlightCut("cafe\u{301} \u{2014} ok", saidChars: 5) == 5)
        #expect(Transcript.highlightCut("cafe\u{301} \u{2014} ok", saidChars: 6) == 7)
    }
}
