// nuclear/NuclearWar.kt (lines 1496-1644): the end of a round (doNextRound): bombing, scores, money, then the calls.

import Foundation

extension NuclearWar {
    // ----- The end of a round: doNextRound -----

    func nextRound(_ o: Out) throws {
        st.countryIndex = 0
        st.midGame = true
        st.q = .phoneCountry
        let prevBalance = try us().balance
        st.prevEnvironment = st.environment
        try countryDecisions()
        st.round += 1
        try bombCountries(o)
        for c in st.countries { c.score += score(c) }
        let us = try us()
        us.score += score(us)
        st.cityBombIndex = 0
        for c in st.countries { updateBalance(c) }
        updateBalance(us)
        if NuclearWar.int(st.prevEnvironment + 100) < 0 {
            heavenlyEnvironmentDestruction(o)
            us.destroyed = true
            for c in st.countries { c.destroyed = true }
        }
        // Every other country gone (the skill counts four, so a country knocked out in an earlier round kept the
        // game going with nobody left to call; here it's over). The environment's collapse destroys them all too.
        let allDestroyed = st.countries.allSatisfy { c in c.destroyed || c.cities.allSatisfy(\.destroyed) }
        if allDestroyed {
            if us.destroyed { everyCountryDestroyed(o) } else { try destroyEveryOneGameOver(o) }
        } else if us.destroyed {
            try weGotDestroyedGameOver(o)
        } else if st.round > 5 {
            try nuclearGameOver(o)
        } else {
            try roundReport(o, prevBalance)
        }
    }

    /// The rest of doNextRound: who's out, the round, the scores and the money, then the calls.
    func roundReport(_ o: Out, _ prevBalance: Int64) throws {
        let us = try us()
        let out = World.ordered(st.countries.filter(\.destroyed).map(\.ref))
        st.countries = st.countries.filter { !$0.destroyed }
        o.bed(sfx("longOrchestral"), 0.10)
        if !out.isEmpty {
            o.pause(1.5)
            o.bed(sfx("deplete"), 1.0)
            o.don(try Lines.countriesDestroyed(out).kRandom(random))
        }
        o.bed(sfx("trumpet"), 1.0)
        o.pause(3.0)
        o.don(Lines.roundComplete(NuclearWar.int(st.round - 1)))
        if !st.rundown {
            o.don(Lines.scores)
            o.clip(sfx("woosh"))
            o.don(Lines.scoreParts)
            st.rundown = true
            let balancePoints = prevBalance > 5_000_000 ? 4 : prevBalance >= 2_000_000 ? 2 : 0
            var research = 0
            var shields = 0
            var cityPoints = 0
            for c in us.alive() {
                cityPoints += 5
                if c.shield > 0 { shields += 1 }
                if c.research > 0 { research += 2 }
            }
            if balancePoints > 0 {
                o.part(Lines.bankPoints(balancePoints))
                o.money(prevBalance)
                o.don(Lines.inTheBank)
                o.clip(sfx("kaching"))
            }
            if us.contributions > 0 {
                o.don(Lines.envPoints(Swift.min(us.contributions, 5)))
                o.clip(sfx("upgradeEnvironment"))
            }
            if research > 0 && shields == 0 {
                o.don(Lines.researchAndCities(research, cityPoints))
                o.clip(sfx("research"))
            } else if shields > 0 && research == 0 {
                o.don(Lines.shieldsAndCities(shields, cityPoints))
                o.clip(sfx("shield"))
            } else if shields > 0 {
                o.don(Lines.shieldsResearchAndCities(shields, research, cityPoints))
                o.bed(sfx("shield"), 1.0)
                o.pause(0.5)
                o.clip(sfx("research"))
            } else {
                o.don(Lines.citiesOnly(cityPoints))
            }
        } else {
            let alive = us.alive()
            if !alive.isEmpty {
                // "upgraded" counts every city left, as the skill does.
                let upgraded = alive.count(where: { $0.shield > 0 || $0.research > 0 })
                o.don(upgraded == 0 ? Lines.citiesNoUpgrades(alive.count) : Lines.citiesUpgraded(alive.count))
            }
            if us.bombs > 0 { o.don(Lines.reserve(bombsText(us.bombs))) }
            o.pause(1.0)
        }
        o.clip(sfx("woosh"))
        try scoreSpeech(o, end: false)
        let earned = us.balance &- prevBalance
        if earned == 0 {
            o.don(Lines.noEarnings)
        } else {
            if earned < 0 {
                o.part(Lines.youLost)
                o.money(0 &- earned)
                o.don(Lines.thisRound)
            } else {
                o.part(Lines.youReceived)
                o.money(earned)
                o.don(Lines.inEarnings)
                o.clip(sfx("kaching"))
            }
            o.part(Lines.youHave)
            o.money(us.balance)
            o.don(Lines.toSpend)
        }
        o.stopBeds()
        st.citiesToBomb.removeAll()
        if isFinalRound() { return try finalRoundStart(o) }
        let first = try current()
        if first.attackUs != 0 || first.hasAttackedUs { try angryCountryCall(o) } else { try phoneCountryPrompt(o) }
    }

    /// calculateScoreForCountry
    func score(_ c: Nation) -> Int {
        var s = c.balance > 5_000_000 ? 4 : c.balance >= 2_000_000 ? 2 : 0
        s += c.contributions
        for city in c.alive() {
            s += 5
            if city.shield > 0 { s += 1 }
            if city.research > 0 { s += 2 }
        }
        return NuclearWar.int(s)
    }

    /// updateCountryBalance
    func updateBalance(_ c: Nation) {
        var add = 0.0
        for city in c.cities {
            if !city.destroyed { add += 3_000_000 }
            if city.research > 0 { add += 1_000_000 }
        }
        add += Double(st.environment) * 100_000.0
        if c.sanctioned { add = floor(add * 0.8) }
        c.balance = c.balance &+ Kt.saturatingLong(add)
        if c.balance < 0 { c.balance = 0 }
    }
}
