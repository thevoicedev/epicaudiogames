// nuclear/NuclearWar.kt (lines 232-329): the skill's intents (yes, no, a number, a name), its buttons, numbers said.

extension NuclearWar {
    // ----- Answers: the skill's intents (yes, no, a number, a name) for the question at hand -----

    enum Intent: Equatable {
        case yes
        case no
        case number
        case name(String)
    }

    func answers() throws -> [(answer: Answer, intent: Intent)] {
        var out: [(answer: Answer, intent: Intent)] = []
        func add(_ m: Match, _ i: Intent) {
            let key: String = switch i {
            case .yes: "yes"
            case .no: "no"
            case .number: "number"
            case .name(let value): "name:\(value)"
            }
            let set: SetList = ["intent": .assign(.string(key))]
            out.append((Answer(match: m, go: nil, set: set, whenCond: nil, opposite: nil), i))
        }
        func words(_ list: [String]) -> Match { .words(NuclearWar.phrases(list)) }
        add(.yes(extra: []), .yes)
        add(.no(extra: []), .no)
        if st.q == .bombPrompt || st.q == .bombNumberPrompt {
            add(.re(try RegexBox(NuclearWar.numberPattern)), .number)
            add(words(["none", "no bombs"]), .no)
        }
        if st.q == .phoneCountry {
            add(words(["next", "skip", "continue", "play"]), .no)
            add(words(["next round"]), .name("next round"))
        }
        if st.q == .chooseBombCity {
            add(words(["all of them", "all", "all three", "every city", "all the cities", "all of it"]),
                .name("all of them"))
        }
        for (ref, list) in NuclearWar.countryWords {
            let alone = (NuclearWar.countryAlone[ref] ?? []).map { Phrase($0, true) }
            add(.words(NuclearWar.phrases(list) + alone), .name(ref))
        }
        for city in World.cities { add(words([city] + (NuclearWar.cityWords[city] ?? [])), .name(city)) }
        add(words(["shield", "shields", "a shield", "build a shield"]), .name("shield"))
        add(words(["research", "do research"]), .name("research"))
        return out
    }

    func buttons() throws -> [AnswerButton] {
        let yesNo = [AnswerButton(label: "Yes", value: "yes"), AnswerButton(label: "No", value: "no")]
        func countries(_ refs: [String]) throws -> [AnswerButton] {
            try World.ordered(refs).map { AnswerButton(label: try World.voice($0), value: $0) }
        }
        switch st.q {
        case .chooseCountry:
            return try countries(World.refs)
        case .phoneCountry:
            return [AnswerButton(label: "Answer", value: "yes"), AnswerButton(label: "Ignore", value: "no")]
        case .upgradePrompt:
            return [AnswerButton(label: "Shield", value: "shield"), AnswerButton(label: "Research", value: "research"),
                    AnswerButton(label: "No", value: "no")]
        case .chooseBombCountry:
            return try countries(attackable().map(\.ref))
        case .chooseBombCity:
            let c = st.countries.first { $0.ref.kEquals(st.countryToBomb) }
            let cities = c.map(targetCities) ?? []
            // One city left is asked as a yes or no ("Would you like to attack Paris?").
            if cities.count == 1 { return yesNo }
            let all = try cities.count == 3 && us().bombs >= 3
            return cities.map { AnswerButton(label: $0, value: $0) }
                + (all ? [AnswerButton(label: "All of them", value: "all of them")] : [])
        case .sanctionCountry:
            return try countries(st.countries.filter { !$0.sanctioned }.map(\.ref))
        case .removeSanction:
            return try countries(st.countries.filter { $0.sanctioned }.map(\.ref))
        case .bombNumberPrompt:
            let max = try maxBombs()
            let counts = stride(from: 1, through: Swift.min(max, 3), by: 1)
            return counts.map { AnswerButton(label: "\($0)", value: "\($0)") }
                + [AnswerButton(label: "None", value: "none")]
        case .gameOver:
            return []
        default:
            return yesNo
        }
    }

    /// The number said: "3", "three", "twenty two", "one hundred", "a hundred" (not "to", "for" or "won", which say
    /// other things). One said with "not", "don't" or "never" before it ("not one", "I don't want one") is 0, a no.
    func number(_ said: String) -> Int? {
        let dashless = String(String.UnicodeScalarView(said.unicodeScalars.map { $0 == "-" ? " " : $0 }))
        let text = SpokenText.normalise(dashless)
        let t = Kt.split(text, " ")
        func numberWord(_ w: String) -> Int? { NuclearWar.numberWords.first { $0.0 == w }?.1 }
        func scale(_ w: String) -> Int? { NuclearWar.scales.first { $0.0 == w }?.1 }
        for (i, w) in t.enumerated() {
            var next = i + 1
            let n: Int
            if let d = Kt.int32OrNull(w) {
                n = Int(d)
            } else if let tens = NuclearWar.tens.first(where: { $0.0 == w })?.1 {
                let ones = t.getOrNull(i + 1).flatMap(numberWord).flatMap { $0 < 10 ? $0 : nil }
                if ones != nil { next += 1 }
                n = tens + (ones ?? 0)
            } else if let word = numberWord(w) {
                n = word
            } else if w == "couple" {
                n = 2
            } else if let s = scale(w) {
                return SpokenText.negated(text, w) ? 0 : s
            } else {
                continue
            }
            if SpokenText.negated(text, w) { return 0 }
            let times = t.getOrNull(next).flatMap(scale) ?? 1
            return Swift.min(n * times, Int(Int32.max))
        }
        return nil
    }
}
