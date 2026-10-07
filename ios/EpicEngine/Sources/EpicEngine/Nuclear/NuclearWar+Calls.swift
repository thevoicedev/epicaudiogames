// nuclear/NuclearWar.kt (lines 1244-1495): the calls (doPhoneCountry, doAngryCountryCall, doCallsComplete).

extension NuclearWar {
    // ----- The calls: doPhoneCountryPrompt, doPhoneCountry, doAngryCountryCall, doCallsComplete -----

    /// doPhoneCountryPrompt
    func phoneCountryPrompt(_ o: Out) throws {
        st.q = .phoneCountry
        let c = try current()
        o.bed(theme(c.ref), 0.25)
        if st.round < 3 && !st.doneLongCall {
            st.doneLongCall = true
            o.bed(sfx("phoneRing"), 1.0)
            o.pause(3.0)
            o.don(try Lines.callIncoming(c.ref))
        } else {
            o.bed(sfx("shortRing"), 1.0)
            o.pause(1.0)
            o.don(try (st.countryIndex > 0 ? Lines.onHold(c.ref) : Lines.longCall(c.ref)).kRandom(random))
            o.don(try Lines.pickUp.kRandom(random))
        }
        o.stopBeds()
        o.reprompt(Lines.answer)
    }

    /// The next call after one is answered or ignored.
    func nextCall(_ o: Out) throws {
        if st.countryIndex >= st.countries.count {
            try callsComplete(o)
        } else if try current().attackUs != 0 {
            try angryCountryCall(o)
        } else {
            try phoneCountryPrompt(o)
        }
    }

    /**
     * doPhoneCountry: what a country does when it calls. Answered ([respond]), the call plays and the next one rings;
     * ignored (and in the final round, where nobody calls), its effects happen all the same.
     */
    func phoneCountry(_ o: Out, _ respond: Bool) throws {
        guard let cur = st.countries.getOrNull(st.countryIndex) else { return try callsComplete(o) }
        let us = try us()
        if respond { o.clip(sfx("pickupPhone")) }
        var hungUp = false
        var doPickup = false
        var angry = false
        var sanctionUs = false
        var removeSanctions = false
        let introHello = try respond && (st.round <= 2 ? st.countryIndex < 2 : random.nextDouble() < 0.5)
        var wasBombed = us.countriesBombed.count(where: { $0.kEquals(cur.ref) })
        let withNuclear = st.countries.filter { $0.tech && !$0.ref.kEquals(cur.ref) }.map(\.ref)
        let doubleSanction = cur.stillSanctioned
        let sanctionedUs = us.sanctionedBy.kContains(cur.ref)
        let tripleSanction = doubleSanction && sanctionedUs
        func hello() {
            if introHello { o.clip(audio.path(cur.ref, "PhoneHello")) }
        }
        if cur.attackUs != 0 || cur.hasAttackedUs {
            hungUp = true
            if respond { o.clip(sfx("hangUp")) }
        } else if cur.wasSanctioned && wasBombed == 0 {
            hello()
            let target = try st.countries.filter { !$0.ref.kEquals(cur.ref) && !$0.destroyed }.map(\.ref)
                .kRandomOrNull(random)
            cur.wasSanctioned = false
            cur.stillSanctioned = false
            st.requestToBomb.append((cur.ref, target ?? ""))
            if respond {
                if sanctionedUs {
                    removeSanctions = true
                    us.sanctioned = false
                    us.sanctionedBy.removeAll { $0.kEquals(cur.ref) }
                }
                o.clip(audio.path(cur.ref, "SanctionsRemoved"))
                o.clip(target.flatMap { audio.keyed(cur.ref, "BombCountry", $0) })
            }
        } else if !cur.bombedBy.isEmpty && cur.strikesToUse != 0 {
            hello()
            var toBomb = try cur.bombedBy.kRandom(random)
            if try random.nextDouble() < 0.5 && wasBombed > 0 { toBomb = us.ref }
            var city: City?
            var bombingUs = false
            cur.bombify.append(toBomb)
            if let target = st.countries.first(where: { $0.ref.kEquals(toBomb) }) {
                city = try target.alive().kRandomOrNull(random)
            } else {
                for (from, _) in st.requestToBomb where from.kEquals(cur.ref) {
                    city = try us.alive().kRandomOrNull(random)
                    bombingUs = true
                }
            }
            if let city {
                // "We're going to attack <city>." (China has no clip for Cardiff: on Alexa it 404s; here it's left out)
                if respond { o.clip(audio.keyed(cur.ref, "Attack", NuclearWar.lettersOnly(city.name))) }
                doPickup = true
            } else if bombingUs {
                hungUp = true
                cur.attackUs += 1
                cur.hasAttackedUs = true
                if respond { o.clip(sfx("hangUp")) }
            } else if respond {
                o.clip(try unused(cur, "general", "GeneralChat"))
            }
        } else if wasBombed > 0 || (doubleSanction && us.sanctioned) || tripleSanction {
            hello()
            if wasBombed == 0 { wasBombed = 1 }
            cur.attackUs = wasBombed + (doubleSanction ? 1 : 0)
            if respond {
                o.clip(audio.path(cur.ref, "GotBombed"))
                angry = true
            }
        } else if doubleSanction {
            sanctionUs = true
            us.sanctionedBy.append(cur.ref)
            us.sanctioned = true
            if respond { o.clip(sfx("hangUp")) }
        } else if cur.sanctioned {
            hello()
            cur.stillSanctioned = true
            if respond { o.clip(audio.path(cur.ref, "RemoveSanction")) }
        } else {
            hello()
            if respond {
                switch cur.motivator {
                case "DEFENSE":
                    o.clip(try unused(cur, "defense", "DefenseSpending"))
                case "ENVIRONMENT":
                    if st.environment < 0 {
                        o.clip(try audio.paths(cur.ref, "EnvironmentBad").kRandomOrNull(random))
                    } else {
                        o.clip(try unused(cur, "general", "GeneralChat"))
                    }
                case "FRIENDLY":
                    if try !withNuclear.isEmpty && random.nextDouble() < 0.5 {
                        o.clip(audio.keyed(cur.ref, "Worried", try withNuclear.kRandom(random)))
                    } else {
                        o.clip(try unused(cur, "friendly", "Friendly"))
                    }
                case "NUCLEAR":
                    if try random.nextDouble() < 0.2 {
                        o.clip(try unused(cur, "general", "GeneralChat"))
                    } else {
                        o.clip(try unused(cur, "nuclear", "NuclearBuilding"))
                    }
                default:
                    break
                }
            }
        }
        if !respond { return }
        if (wasBombed == 0 && !doubleSanction) || doPickup || sanctionUs { o.clip(sfx("pickupPhone")) }
        if removeSanctions {
            o.don(try Lines.removedOnYou(cur.ref))
            o.clip(sfx("eraser"))
        } else if sanctionUs {
            o.don(try Lines.instaHangUp.kRandom(random))
            o.clip(sfx("stampFx"))
            o.don(Lines.sanctionedYou)
        } else if hungUp {
            o.don(try Lines.instaHangUp.kRandom(random))
        } else if angry {
            o.don(try tripleSanction ? Lines.tripleSanction.kRandom(random) : Lines.enemyAngry(cur.ref).kRandom(random))
        }
        st.countryIndex += 1
        try nextCall(o)
    }

    /// Kotlin's `replace(Regex("[^A-Za-z]"), "")`: only the ASCII letters kept ("St Petersburg" is "StPetersburg").
    static func lettersOnly(_ s: String) -> String {
        String(String.UnicodeScalarView(s.unicodeScalars.filter { $0.isASCII && $0.properties.isAlphabetic }))
    }

    /// doAngryCountryCall: countries that want to attack you don't call (two or three in a row are said together).
    /// "No one calls" only when no one has and no one will: the skill also said it with a fourth country still to ring.
    func angryCountryCall(_ o: Out) throws {
        let cur = try current()
        if cur.attackUs == 0 { return try phoneCountryPrompt(o) }
        let first = st.countryIndex
        st.countryIndex += 1
        let next = st.countries.getOrNull(st.countryIndex)
        if let next, next.attackUs != 0 {
            st.countryIndex += 1
            let nextNext = st.countries.getOrNull(st.countryIndex)
            let pair = World.ordered([cur.ref, next.ref])
            if let nextNext, nextNext.attackUs != 0 {
                st.countryIndex += 1
                let after = st.countries.getOrNull(st.countryIndex)
                if first == 0 && (after == nil || after?.attackUs != 0) {
                    o.bed(sfx("crickets"), 0.5)
                    o.don(try Lines.noCalls.kRandom(random))
                    o.stopBeds()
                    return try callsComplete(o)
                }
                o.don(try Lines.twoNoTalk(at(pair, 0), at(pair, 1)).kRandom(random))
                o.don(try Lines.singleNoTalk(nextNext.ref).kRandom(random))
                return try after == nil ? callsComplete(o) : phoneCountryPrompt(o)
            }
            o.don(try Lines.twoNoTalk(at(pair, 0), at(pair, 1)).kRandom(random))
            if nextNext == nil { try callsComplete(o) } else { try phoneCountryPrompt(o) }
        } else {
            o.don(try Lines.singleNoTalk(cur.ref).kRandom(random))
            if next == nil { try callsComplete(o) } else { try phoneCountryPrompt(o) }
        }
    }

    /// doCallsComplete: on to this round's spending.
    func callsComplete(_ o: Out) throws {
        st.countryIndex = 0
        let us = try us()
        if isFinalRound() {
            st.cityIndex = 0
            o.don(try hasFinalRoundMove() ? Lines.finalMove : Lines.finalRound)
            if us.tech && us.balance >= World.bomb {
                try bombPrompt(o)
            } else if try hasFinalRoundMove() {
                try finalShieldPrompt(o)
            } else {
                try sanctionPromptWithCheck(o)
            }
            return
        }
        o.don(Lines.callsDone(st.round))
        let b = us.balance
        if b >= World.tech && !us.tech {
            techPrompt(o, start: false)
        } else if b >= World.environment && !us.tech {
            environmentPrompt(o)
        } else if b < World.environment && !us.tech {
            try sanctionPromptWithCheck(o)
        } else if b >= World.bomb && us.tech {
            try bombPrompt(o)
        } else if b >= World.environment && us.tech {
            environmentPrompt(o)
        } else {
            try sanctionPromptWithCheck(o)
        }
    }

    /// getNextShieldableCityIndex
    func nextShieldableCity() throws -> Int {
        let us = try us()
        if us.balance < World.shield { return -1 }
        for i in stride(from: st.cityIndex, to: us.cities.count, by: 1) {
            let c = try at(us.cities, i)
            if !c.destroyed && c.shield == 0 { return i }
        }
        return -1
    }

    func hasFinalRoundMove() throws -> Bool {
        let us = try us()
        return try (us.tech && us.balance >= World.bomb) || us.bombs > 0 || nextShieldableCity() != -1
    }

    /// doFinalRoundStart: nobody calls, but what the calls would do happens.
    func finalRoundStart(_ o: Out) throws {
        st.countryIndex = 0
        try callsUnheard(o)
    }

    /// The calls left aren't heard (the final round, or "next round"), but what they would do happens.
    func callsUnheard(_ o: Out) throws {
        for i in stride(from: st.countryIndex, to: st.countries.count, by: 1) {
            st.countryIndex = i
            if try at(st.countries, i).attackUs == 0 { try phoneCountry(o, false) }
        }
        try callsComplete(o)
    }

    /// doFinalShieldPrompt
    func finalShieldPrompt(_ o: Out) throws {
        let i = try nextShieldableCity()
        if i == -1 { return try bombsOrNextRound(o) }
        st.cityIndex = i
        try shieldPrompt(o)
    }
}
