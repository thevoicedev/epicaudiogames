// nuclear/NuclearWar.kt (lines 992-1243): yes, no and names at each question (doNuclearYes, doNuclearNo, etc.).

extension NuclearWar {
    // ----- Yes, no and names: doNuclearYes, doNuclearNo, doAnswerNuclearWar -----

    func yes(_ o: Out) throws {
        switch st.q {
        case .bombIndividual:
            st.q = .chooseBombCountry
            guard let first = World.ordered(attackable().map(\.ref)).first else { return try continueWar(o) }
            try aimAt(o, first)
        case .chooseBombCity:
            try launchOffered(o)
        case .confirmBombPrompt:
            guard let c = st.countryToBomb else { return try continueWar(o) }
            o.don(try Lines.definitely(c))
            st.cityBombIndex = 0
            try chooseBombCity(o)
        case .countrySelect:
            try meetCountry(o)
        case .useBombs:
            try askWhichCountryToBomb(o)
        case .nuclearPrompt:
            try buyTech(o)
        case .environmentPrompt:
            try buyEnvironment(o)
        case .cityPrompt:
            let city = try currentCity()
            if try us().balance >= World.shield && city.shield == 0 && city.research == 0 {
                buildOrResearchPrompt(o)
            } else if city.research > 0 {
                try shieldPrompt(o)
            } else {
                try researchPrompt(o)
            }
        case .sanction:
            try countrySanctionChoice(o)
        case .upgradePrompt:
            o.don(Lines.shieldOrResearchAgain)
            o.reprompt(Lines.shieldOrResearchAgain)
        case .researchPrompt:
            try chooseResearch(o)
        case .shieldPrompt:
            try chooseShield(o)
        case .sanctionSpecific:
            guard let c = st.countries.first(where: { !$0.sanctioned }) else { return try continueWar(o) }
            try sanctionCountry(o, c.ref)
        case .phoneCountry:
            try phoneCountry(o, true)
        case .bombPrompt:
            o.part(Lines.youHave)
            o.money(try us().balance)
            o.don(Lines.toSpend)
            o.don(Lines.bombCost)
            askBombAmount(o)
        case .removeSanctionPrompt:
            if st.countries.count(where: { $0.sanctioned }) == 1 {
                try removeIndividualSanctionPrompt(o)
            } else {
                try removeSanctionPrompt(o)
            }
        case .removeIndividualSanction:
            st.q = .removeSanction
            guard let c = st.countries.first(where: { $0.sanctioned }) else { return try continueWar(o) }
            try answerWith(o, c.ref)
        default:
            try continueWar(o)      // SANCTION_COUNTRY too: the skill's "yes" there has nothing to pick
        }
    }

    func no(_ o: Out) throws {
        switch st.q {
        case .bombIndividual, .chooseBombCountry:
            try nextRound(o)
        case .useBombs:
            if st.citiesToBomb.isEmpty {
                let n = bombsText(try us().bombs)
                o.don(isFinalRound() ? Lines.dontUse(n) : Lines.keepForLater(n))
            }
            try nextRound(o)
        case .confirmBombPrompt:
            o.don(Lines.haveBombs(bombsText(try us().bombs)))
            offerBombUse(o)
        case .chooseBombCity:
            guard let c = st.countryToBomb else { return try chooseBombCityReprompt(o) }
            st.q = .confirmBombPrompt
            o.don(try Lines.sureBomb(c))
            o.reprompt(try Lines.sureBomb(c))
        case .countrySelect:
            techPrompt(o)
        case .nuclearPrompt:
            environmentPrompt(o)
        case .environmentPrompt:
            try afterEnvironment(o)
        case .researchPrompt:
            if try st.cityIndex >= us().cities.count - 1 {
                o.don(Lines.allCities)
                try sanctionPromptWithCheck(o)
            } else {
                st.cityIndex += 1
                try nextCityPrompt(o)
            }
        // UPGRADE_PROMPT: the skill's SkillFlow makes a no there a no to the city (doNo).
        case .cityPrompt, .upgradePrompt:
            if try st.cityIndex >= us().cities.count - 1 {
                o.don(Lines.everyCity)
                try sanctionPromptWithCheck(o)
            } else {
                st.cityIndex += 1
                try nextCityPrompt(o, howAbout: true)
            }
        case .sanction, .sanctionCountry, .sanctionSpecific:
            try bombsOrNextRound(o)
        case .phoneCountry:
            if st.countryIndex >= st.countries.count { return try callsComplete(o) }
            try phoneCountry(o, false)
            st.countryIndex += 1
            try nextCall(o)
        case .bombPrompt, .bombNumberPrompt:
            try completeBombPurchase(o)
        case .removeSanctionPrompt, .removeSanction, .removeIndividualSanction:
            try afterRemovingSanctions(o)
        case .shieldPrompt:
            if isFinalRound() {
                st.cityIndex += 1
                try finalShieldPrompt(o)
            } else if try st.cityIndex >= us().cities.count - 1 {
                o.don(Lines.everyCity)
                try sanctionPromptWithCheck(o)
            } else {
                st.cityIndex += 1
                try nextCityPrompt(o)
            }
        default:
            try continueWar(o)
        }
    }

    /// A country, a city, "shield" or "research" said (doAnswerNuclearWar).
    func answerWith(_ o: Out, _ value: String) throws {
        switch st.q {
        case .phoneCountry:
            // "next round" skips the calls, not what they'd do (as when each is ignored).
            if value == "next round" { try callsUnheard(o) } else { try continueWar(o) }
        case .chooseCountry:
            if World.refs.kContains(value) { try chooseCountry(o, value) } else { try continueWar(o) }
        case .chooseBombCountry, .useBombs, .chooseBombCity, .bombIndividual:
            try aimAt(o, value)
        case .upgradePrompt, .shieldPrompt, .researchPrompt, .cityPrompt:
            try upgradeWith(o, value)
        case .sanctionCountry, .sanction, .sanctionSpecific:
            let c = st.countries.first { $0.ref.kEquals(value) }
            if let c, c.sanctioned {
                o.don(try Lines.alreadySanctioned(value))
                try countrySanctionChoice(o)
            } else if c != nil {
                try sanctionCountry(o, value)
            } else {
                if try value.kEquals(us().ref) {
                    o.don(Lines.sanctionOwn)
                } else if World.refs.kContains(value) {
                    o.don(try Lines.cantSanction(value))
                }
                try countrySanctionChoice(o)
            }
        case .removeSanction, .removeSanctionPrompt, .removeIndividualSanction:
            let c = st.countries.first { $0.ref.kEquals(value) }
            if let c, c.sanctioned {
                try unsanctionCountry(o, value)
            } else if c != nil {
                o.don(try Lines.noSanctionsOn(value))
                if st.q == .removeIndividualSanction {
                    try removeIndividualSanctionPrompt(o)
                } else {
                    try removeSanctionPrompt(o)
                }
            } else {
                if try value.kEquals(us().ref) {
                    o.don(Lines.unsanctionOwn)
                } else if World.refs.kContains(value) {
                    o.don(try Lines.notToUnsanction(value))
                }
                try sanctionPromptWithCheck(o)
            }
        default:
            try continueWar(o)
        }
    }

    /// "Shield" or "research" said at a city's upgrades.
    func upgradeWith(_ o: Out, _ value: String) throws {
        guard let city = try us().cities.getOrNull(st.cityIndex) else { return try continueWar(o) }
        if isFinalRound() && st.q == .shieldPrompt && value != "shield" { return try shieldPrompt(o) }
        switch value {
        case "shield":
            if city.shield > 0 {
                o.don(Lines.alreadyShield(city.name))
                try continueWar(o)
            } else if try us().balance < World.shield {
                o.don(Lines.noMoneyShield(city.name))
                try researchPrompt(o)
            } else {
                try chooseShield(o)
            }
        case "research":
            if city.research > 0 {
                o.don(Lines.alreadyResearch(city.name))
                try continueWar(o)
            } else {
                try chooseResearch(o)
            }
        default:
            try continueWar(o)      // the skill: "You can't <what was said>, in this war."
        }
    }

    /// doContinueNuclearWar: the question again (also "repeat", and anything not understood).
    func continueWar(_ o: Out) throws {
        switch st.q {
        case .chooseCountry:
            o.don(Lines.chooseFrom)
            o.reprompt(Lines.chooseFrom)
        case .countrySelect:
            o.don(try Lines.meet(current().ref))
            o.reprompt(try Lines.meet(current().ref))
        case .nuclearPrompt:
            o.don(Lines.techSpend)
            o.reprompt(Lines.techSpend)
        case .environmentPrompt:
            environmentPrompt(o)
        case .researchPrompt:
            try researchPrompt(o)
        case .upgradePrompt:
            buildOrResearchPrompt(o)
        case .sanction:
            sanctionPrompt(o)
        case .sanctionCountry, .sanctionSpecific:
            try countrySanctionChoice(o)
        case .cityPrompt:
            try nextCityPrompt(o)
        case .shieldPrompt:
            try shieldPrompt(o)
        case .phoneCountry:
            guard let c = st.countries.getOrNull(st.countryIndex) else { return try callsComplete(o) }
            o.don(try Lines.callImportant(c.ref))
            o.reprompt(try Lines.callAgain(c.ref))
        case .bombPrompt:
            o.don(Lines.buyAny)
            o.reprompt(Lines.buyNuclear)
        case .bombNumberPrompt:
            let max = try maxBombs()
            if max > 0 { o.don(Lines.affordUpTo(Swift.min(max, World.bombsMax))) }
            o.don(Lines.howManySay)
            o.reprompt(Lines.howManySay)
        case .removeSanctionPrompt:
            o.don(Lines.removeFromOne)
            o.reprompt(Lines.removeFromOne)
        case .removeSanction:
            try removeSanctionPrompt(o)
        case .removeIndividualSanction:
            try removeIndividualSanctionPrompt(o)
        case .useBombs:
            o.don(Lines.useABombLong)
            o.reprompt(Lines.useABombLong)
        case .chooseBombCountry, .bombIndividual:
            try askWhichCountryToBomb(o)
        case .chooseBombCity:
            try chooseBombCityReprompt(o)
        case .confirmBombPrompt:
            guard let c = st.countryToBomb else { return try askWhichCountryToBomb(o) }
            o.don(try Lines.sureBombAll(c))
            o.reprompt(try Lines.sureBombAll(c))
        case .gameOver:
            o.don(Lines.canYouRepeat)
            o.reprompt(Lines.canYouRepeat)
        }
    }
}
