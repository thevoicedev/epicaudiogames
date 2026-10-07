// Text.kt:23 and Matcher.kt:100: maxByOrNull and maxBy keep the first of the longest. No fixture has a tie whose
// winner changes the result, so these pin it by hand (the harness self-test's "last maximum wins" must fail here).

import EpicConformance
import EpicEngine
import Testing

@Suite struct TieBreakTests {
    /// Two phrases of one answer, as long as each other, both said: the first in the list wins.
    @Test func longestKeepsTheFirst() {
        #expect(SpokenText.longest("big red", [Phrase("red", false), Phrase("big", false)]) == Phrase("red", false))
        #expect(SpokenText.longest("big red", [Phrase("big", false), Phrase("red", false)]) == Phrase("big", false))
    }

    /// Two answers that do the same thing, their phrases as long as each other, both said: the first answer wins.
    @Test func matcherKeepsTheFirstHit() throws {
        let map = try GameMap.parse("""
            {"format":1,"id":"demo","title":"Demo","start":"a","nodes":{"a":{"say":[],"ask":{"reprompt":[],"answers":\
            [{"words":["red"],"go":"b"},{"words":["big"],"go":"b"}]}},"b":{"say":[],"end":{"kind":"ending","title":"Done"}}}}
            """)
        let ask = try #require(map.nodes["a"]?.ask)
        #expect(try Matcher.match(map, ask, map.vars, "big red") == Matcher.Result(index: 0, repeat: false, how: "\"red\""))
    }
}
