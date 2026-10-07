// nuclear/NuclearWar.kt (lines 745-991): bombs: buying them, and aiming them at countries and cities.

extension NuclearWar {
    // ----- Bombs -----

    /// doBombPrompt
    func bombPrompt(_ o: Out) throws {
        st.q = .bombPrompt
        let n = try us().bombs
        if n > 0 {
            o.don(Lines.buyMore(bombsText(n)))
            o.reprompt(Lines.buyMoreAgain(bombsText(n)))
        } else {
            o.don(Lines.buyAny)
            o.reprompt(Lines.buyAny)
        }
    }

    /// askBombAmount
    func askBombAmount(_ o: Out) {
        st.q = .bombNumberPrompt
        o.don(Lines.howMany)
        o.reprompt(Lines.howMany)
    }

    /// doNuclearPickNumber
    func pickNumber(_ o: Out, _ n: Int?) throws {
        if st.q != .bombPrompt && st.q != .bombNumberPrompt { return try continueWar(o) }
        let max = try maxBombs()
        guard let n else {
            o.don(Lines.didntCatch)
            return askBombAmount(o)
        }
        if n > max {
            o.don(Lines.affordUpTo(Swift.min(max, World.bombsMax)))
            askBombAmount(o)
        } else if n == 0 {
            try no(o)
        } else {
            let us = try us()
            o.clip(sfx("kaching"))
            us.balance &-= Int64(n) * World.bomb
            us.bombs += n
            o.part(Lines.nowHave(bombsText(us.bombs)))
            if us.balance <= 0 { o.part(Lines.nothing) } else { o.money(us.balance) }
            o.don(Lines.leftInBank)
            st.environment -= n * 5
            try completeBombPurchase(o)
        }
    }

    /// doCompleteBombPurchase
    func completeBombPurchase(_ o: Out) throws {
        if isFinalRound() { return try finalShieldPrompt(o) }
        if try us().balance >= World.environment { environmentPrompt(o) } else { try sanctionPromptWithCheck(o) }
    }

    /// doBombsOrNextRound
    func bombsOrNextRound(_ o: Out) throws {
        let n = try us().bombs
        if n > 0 && st.round > 1 {
            o.don(Lines.haveBombs(bombsText(n)))
            offerBombUse(o)
        } else {
            try nextRound(o)
        }
    }

    /// doOfferBombUse (on a speaker, always "from the prompt")
    func offerBombUse(_ o: Out) {
        st.q = .useBombs
        o.don(Lines.useOne)
        o.reprompt(Lines.useABomb)
    }

    /// getAttackableCountries
    func attackable() -> [Nation] {
        st.countries.filter { c in
            !c.destroyed && c.cities.contains { !$0.destroyed && !st.citiesToBomb.kContains($0.name) }
        }
    }

    /// A country's cities that can still be aimed at, in its fixed order.
    func targetCities(_ c: Nation) -> [String] {
        World.orderedCities(c.cities.filter { !$0.destroyed && !st.citiesToBomb.kContains($0.name) }.map(\.name))
    }

    /// askWhichCountryToBomb
    func askWhichCountryToBomb(_ o: Out) throws {
        st.q = .chooseBombCountry
        let refs = World.ordered(attackable().map(\.ref))
        if refs.isEmpty { return try nextRound(o) }    // the skill says "Attack undefined": nothing left to aim at
        if refs.count == 1 {
            st.q = .bombIndividual
            o.don(try Lines.wantAttack(refs[0]))
            o.reprompt(try Lines.wouldAttack(refs[0]))
            return
        }
        o.don(try Lines.attackCountries(refs))
        o.reprompt(try Lines.whichCountryAttack(refs))
    }

    /// chooseBombCity
    func chooseBombCity(_ o: Out) throws {
        st.q = .chooseBombCity
        guard let c = st.countries.first(where: { $0.ref.kEquals(st.countryToBomb) }) else {
            return try askWhichCountryToBomb(o)
        }
        let cities = targetCities(c)
        if cities.isEmpty { return try askWhichCountryToBomb(o) }
        if cities.count == 1 {
            st.cityBombIndex = 0
            o.don(Lines.wouldAttackCity(cities[0]))
            o.reprompt(Lines.wantAttackCity(cities[0]))
            return
        }
        o.don(try cities.count == 3 && us().bombs >= 3 ? Lines.attackAll(cities) : Lines.attackCities(cities))
        o.reprompt(try Lines.attackCities(cities))
    }

    /// chooseBombCityReprompt
    func chooseBombCityReprompt(_ o: Out) throws {
        st.q = .chooseBombCity
        guard let c = st.countries.first(where: { $0.ref.kEquals(st.countryToBomb) }) else {
            return try askWhichCountryToBomb(o)
        }
        let cities = targetCities(c)
        if cities.isEmpty { return try askWhichCountryToBomb(o) }
        if cities.count == 1 {
            st.cityBombIndex = 0
            o.don(try Lines.oneLeft(cities[0]))
            o.reprompt(Lines.wantAttackCity(cities[0]))
            return
        }
        o.don(try Lines.attackCities(cities))
        o.reprompt(try Lines.whichCity(cities))
    }

    /// "Yes" to a city on offer: the first one said (doNuclearYes in CHOOSE_BOMB_CITY).
    func launchOffered(_ o: Out) throws {
        let found = st.countries.first { $0.ref.kEquals(st.countryToBomb) }
        guard let c = found, let city = targetCities(c).getOrNull(st.cityBombIndex) else {
            if found != nil { return try chooseBombCityReprompt(o) }
            return try continueWar(o)
        }
        let us = try us()
        us.bombs -= 1
        o.clip(sfx("pressButton"))
        o.don(Lines.launched(city))
        st.citiesToBomb.append(city)
        us.countriesBombed.append(c.ref)
        st.cityBombIndex = 0
        if us.bombs > 0 {
            st.q = .useBombs
            o.don(Lines.bombsLeft(bombsText(us.bombs)))
            o.don(Lines.useAnother)
            o.reprompt(Lines.useAnotherAgain)
        } else {
            directed(o)
            try nextRound(o)
        }
    }

    /// doSelectBombCity
    func selectBombCity(_ o: Out, _ city: String) throws {
        let us = try us()
        us.bombs -= 1
        o.bed(sfx("pressButton"), 1.0)
        o.don(Lines.picked(city))
        st.citiesToBomb.append(city)
        us.countriesBombed.append(try World.landOf(city).ref)
        st.cityBombIndex = 0
        try moreBombsOrNextRound(o)
    }

    /// doSelectBombAllCities
    func selectAllCities(_ o: Out) throws {
        guard let c = st.countries.first(where: { $0.ref.kEquals(st.countryToBomb) }) else { throw World.noSuchElement }
        let cities = targetCities(c)
        let us = try us()
        us.bombs -= cities.count
        for city in cities {
            o.clip(sfx("pressButton"))
            o.don(Lines.picked(city))
            st.citiesToBomb.append(city)
        }
        us.countriesBombed.append(c.ref)
        st.cityBombIndex = 0
        try moreBombsOrNextRound(o)
    }

    func moreBombsOrNextRound(_ o: Out) throws {
        let n = try us().bombs
        if n > 0 {
            st.q = .useBombs
            o.don(Lines.bombsLeft(bombsText(n)))
            if n == 1 {
                o.don(Lines.useIt)
                o.reprompt(Lines.useIt)
            } else {
                o.don(Lines.useAnother)
                o.reprompt(Lines.useAnotherAgain)
            }
        } else {
            directed(o)
            try nextRound(o)
        }
    }

    func directed(_ o: Out) {
        let n = st.citiesToBomb.count
        switch n {
        case 1: o.don(Lines.directedOne)
        case 2: o.don(Lines.directedTwo)
        default: o.don(Lines.directedAll(Swift.min(Swift.max(n, 3), World.bombsMax)))
        }
    }

    /// A country or a city named while aiming (doAnswerNuclearWar in the bombing states).
    func aimAt(_ o: Out, _ value: String) throws {
        if value == "all of them" {
            if st.q == .chooseBombCity && st.countryToBomb != nil {
                guard let c = st.countries.first(where: { $0.ref.kEquals(st.countryToBomb) }) else {
                    throw World.noSuchElement
                }
                if try us().bombs >= targetCities(c).count { return try selectAllCities(o) }
                o.don(try Lines.notEnoughForAll(c.ref))
            }
            return try continueWar(o)
        }
        let ours = try us().ref
        if World.refs.kContains(value) && !value.kEquals(ours) {
            if let c = st.countries.first(where: { $0.ref.kEquals(value) }) {
                if targetCities(c).isEmpty {
                    o.don(try Lines.allSet(value))
                } else {
                    st.countryToBomb = value
                    st.cityBombIndex = 0
                    return try chooseBombCity(o)
                }
            } else {
                o.don(try Lines.cantBomb(value))
            }
            return try continueWar(o)
        }
        if World.cities.kContains(value) {
            let inWar = st.countries.contains { n in n.cities.contains { $0.name.kEquals(value) && !$0.destroyed } }
            if try World.land(ours).cities.kContains(value) {
                o.don(try Lines.bombSelf(value).kRandom(random))
            } else if st.citiesToBomb.kContains(value) {
                o.don(Lines.onePerCity)
            } else if !inWar {
                // A city of a country knocked out earlier counts as destroyed (the skill would aim at it).
                o.don(Lines.alreadyDestroyed(value))
            } else {
                return try selectBombCity(o, value)
            }
            return try continueWar(o)
        }
        if value.kEquals(ours) { o.don(Lines.ownCountry) }
        try continueWar(o)
    }
}
