// TextTest.kt: reading what the player said (TextTest), and conditions on the variables (ConditionTest).

import Testing

@testable import EpicEngine

struct TextTests {
    @Test func normalises() {
        #expect(SpokenText.normalise("Don’t FOLLOW it!") == "don't follow it")
        #expect(SpokenText.normalise("  C, A... C?  ") == "c a c")
        #expect(SpokenText.normalise("?!") == "")
    }

    @Test func matchesWholeWords() {
        #expect(SpokenText.phraseLength("the red one", Phrase("red", false)) > 0)
        #expect(SpokenText.phraseLength("i'm ready", Phrase("red", false)) == -1)
        #expect(SpokenText.phraseLength("fine", Phrase("fine", true)) > 0)
        #expect(SpokenText.phraseLength("i'm fine", Phrase("fine", true)) == -1)
        #expect(
            SpokenText.longest("no rehearsal please", [Phrase("rehearsal", false), Phrase("no rehearsal", false)])?.text
                == "no rehearsal")
    }

    @Test func readsDigitsLikeTheSkill() {
        #expect(SpokenText.digits("four two two one one") == "42211")
        #expect(SpokenText.digits("4 2 2 1 1") == "42211")
        #expect(SpokenText.digits("four twenty-two eleven") == "42211")
        #expect(SpokenText.digits("forty two thousand two hundred and eleven") == "42211")
        #expect(SpokenText.digits("three one four") == "314")
        #expect(SpokenText.digits("to too won one") == "2211")
        #expect(SpokenText.digits("ten") == "10")
        #expect(SpokenText.digits("one hundred") == "100")
        #expect(SpokenText.digits("a hundred") == "")          // as in the skill: no number word, no digits
        #expect(SpokenText.digits("no idea") == "")
        #expect(SpokenText.digits("for to to one one") == "42211")
        #expect(SpokenText.digits("won won to to for") == "11224")
        #expect(SpokenText.digits("for hundred") == "400")
        // fixed: "to", "for", "won" and "oh" on their own were numbers ("I want to play" said 2)
        #expect(SpokenText.digits("I want to play") == "")
        #expect(SpokenText.digits("go for it") == "")
        #expect(SpokenText.digits("I need to listen to it again") == "")
        #expect(SpokenText.digits("oh yes I won") == "")
        #expect(SpokenText.digits("I want to play this one") == "1")
    }

    @Test func readsSymbols() {
        let letters: LinkedMap<[String]> = ["c": ["c", "see", "sea"], "a": ["a", "ay", "eh"]]
        #expect(SpokenText.symbols("see a see", letters) == "cac")
        #expect(SpokenText.symbols("c ac", letters) == "c")
        #expect(SpokenText.symbols("c ac", letters, spelled: true) == "cac")
        let turns: LinkedMap<[String]> = ["l": ["left", "lift"], "r": ["right", "write"]]
        #expect(SpokenText.symbols("left, right, write, lift!", turns) == "lrrl")
    }

    @Test func findsNegation() {
        #expect(SpokenText.negated("don't follow it", "follow"))
        #expect(SpokenText.negated("i really don't want to follow", "follow"))
        #expect(SpokenText.negated("let's not hide", "hide"))
        #expect(!SpokenText.negated("follow it", "follow"))
        #expect(!SpokenText.negated("don't you want to go on and follow", "follow"))
        #expect(SpokenText.negated("of course not", "of course"))
        #expect(SpokenText.negated("i would not", "i would"))
        #expect(!SpokenText.negated("follow not hide", "follow"))      // a "not" after it only when it ends the answer
        #expect(!SpokenText.negated("not", "not"))
    }

    @Test func findsUnsureAnswers() {
        #expect(SpokenText.unsure("i'm not sure"))
        #expect(SpokenText.unsure("i don't know"))
        #expect(SpokenText.unsure("dunno"))
        #expect(!SpokenText.unsure("sure"))
        #expect(!SpokenText.unsure("i know"))
        #expect(!SpokenText.unsure("not surely"))
    }
}

struct ConditionTests {
    @Test func tests() throws {
        let vars: VarStore = ["tries": 2.0, "choice": "hide", "nana": true, "empty": ""]
        #expect(try Condition.parse("tries >= 2").test(vars))
        #expect(try !Condition.parse("tries < 2").test(vars))
        #expect(try Condition.parse("choice == \"hide\"").test(vars))
        #expect(try Condition.parse("nana && tries != 3").test(vars))
        #expect(try Condition.parse("!empty").test(vars))
        #expect(try Condition.parse("missing || nana").test(vars))
        #expect(try !Condition.parse("missing").test(vars))
        #expect(try Condition.parse("nana && tries > 1").names == ["nana", "tries"])
    }

    @Test func rejectsNonsense() {
        expectMapException { _ = try Condition.parse("tries >> 2") }
    }
}
