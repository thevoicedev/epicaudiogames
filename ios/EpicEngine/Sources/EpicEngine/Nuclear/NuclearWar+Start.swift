// nuclear/NuclearWar.kt (lines 345-427): starting: doPlayNuclearWar, initNuclearStats, doChooseCountry, the meetings.

extension NuclearWar {
    // ----- Starting: doPlayNuclearWar, initNuclearStats, doChooseCountry -----

    func playNuclearWar(_ o: Out) throws {
        st.q = .chooseCountry
        try initNuclearStats()
        if st.playedNuclear {
            o.don(Lines.welcomeBack)
        } else {
            st.playedNuclear = true
            o.don(Lines.welcome)
            o.mix("tutorial")
            o.don(Lines.playAs)
        }
        o.reprompt(Lines.whichCountry)
    }

    func initNuclearStats() throws {
        st.countries = try ["France", "UK", "USA", "China", "Russia"].kShuffled(random).map { ref in
            let n = Nation(ref)
            n.cities = try World.land(ref).cities.kShuffled(random).map(City.init)
            return n
        }
        st.us = nil
        st.environment = 0
        st.prevEnvironment = 0
        st.round = 1
        st.citiesToBomb.removeAll()
        st.cityIndex = 0
        st.countryIndex = 0
        st.requestToBomb.removeAll()
        st.doneLongCall = false
        st.midGame = false
        st.countryToBomb = nil
        st.cityBombIndex = 0
    }

    /// Ours; Kotlin's `st.us!!` fails (NullPointerException) when there's none.
    func us() throws -> Nation {
        guard let us = st.us else { throw PlayError("the game has no country of yours (at \(st.q.rawValue))") }
        return us
    }

    func current() throws -> Nation { try at(st.countries, st.countryIndex) }
    func currentCity() throws -> City { try at(us().cities, st.cityIndex) }
    func isFinalRound() -> Bool { st.round >= 5 }
    func maxBombs() throws -> Int { Swift.max(NuclearWar.int(try us().balance / World.bomb), 0) }
    func bombsText(_ n: Int) -> Int { Swift.min(Swift.max(n, 1), World.bombsMax) }

    /// doChooseCountry
    func chooseCountry(_ o: Out, _ country: String) throws {
        try initNuclearStats()
        st.q = .countrySelect
        guard let us = st.countries.first(where: { $0.ref.kEquals(country) }) else { throw World.noSuchElement }
        st.us = us
        us.score = 0
        st.countries = st.countries.filter { !$0.ref.kEquals(country) }
        let motivators = try ["DEFENSE", "ENVIRONMENT", "FRIENDLY", "NUCLEAR"].kShuffled(random)
        for (i, n) in st.countries.enumerated() { n.motivator = try at(motivators, i) }
        st.countryIndex = 0
        let first = try current()
        o.bed(theme(country), 0.20)
        o.don(try Lines.leaderOf(country))
        if !st.rundown {
            o.don(Lines.meetFirst)
            o.don(try Lines.meet(first.ref))
        } else {
            o.don(try Lines.meetLeader(first.ref))
        }
        o.stopBeds()
        o.reprompt(try Lines.meet(first.ref))
    }

    /// doMeetCountry: the representative's hello and what drives them, then the next country (or the spending).
    func meetCountry(_ o: Out) throws {
        let c = try current()
        o.bed(theme(c.ref), 0.20)
        o.clip(audio.path(c.ref, "Representative"))
        o.clip(try audio.options(c.ref, "Motivators", c.motivator).kRandomOrNull(random))
        o.stopBeds()
        c.hasMet = true
        if st.countryIndex > 2 {
            techPrompt(o)
        } else {
            st.countryIndex += 1
            let next = try current()
            o.don(try st.countryIndex == 3 ? Lines.meetFinally(next.ref) : Lines.meet(next.ref))
            o.reprompt(try Lines.meet(next.ref))
        }
    }
}
