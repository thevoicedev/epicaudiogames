// nuclear/NuclearWar.kt (lines 428-645): spending: nuclear tech, the environment, the cities' shields and research.

extension NuclearWar {
    // ----- Spending: tech, the environment, the cities -----

    /// doNuclearTechPrompt
    func techPrompt(_ o: Out, start: Bool = true) {
        st.q = .nuclearPrompt
        o.don(start ? Lines.techStart : Lines.tech)
        o.reprompt(Lines.tech)
    }

    func buyTech(_ o: Out) throws {
        let us = try us()
        us.tech = true
        st.q = .environmentPrompt
        us.balance &-= World.tech
        st.environment -= 10
        o.clip(sfx("kaching"))
        try moneyLeft(o)
        if st.round < 5 {
            o.bed(sfx("nuclearReactor"), 0.30)
            o.pause(0.5)
            o.don(Lines.techDone)
            o.stopBeds()
        }
        environmentPrompt(o)
    }

    /// environmentalImpactPrompt
    func environmentPrompt(_ o: Out) {
        st.q = .environmentPrompt
        o.don(st.round > 1 ? Lines.env : Lines.envStart)
        o.reprompt(Lines.env)
    }

    func buyEnvironment(_ o: Out) throws {
        let us = try us()
        us.balance &-= World.environment
        us.contributions += 1
        st.environment += 15
        let percent = NuclearWar.int(st.environment + 100)
        o.clip(sfx("kaching"))
        o.clip(sfx("upgradeEnvironment"))
        if percent == 100 {
            o.don(Lines.envBack)
        } else {
            o.don(Lines.envAt(Swift.min(Swift.max(percent / 5 * 5, 0), World.percentMax)))
            // The tip's "extra 500K" is 5 points: only true after nuclear tech (-10, then +15).
            if st.round == 1 && !st.rundown && st.environment == 5 { o.don(Lines.envExtra) }
        }
        try moneyLeft(o)
        try afterEnvironment(o)
    }

    func afterEnvironment(_ o: Out) throws {
        if try us().balance >= World.research {
            st.cityIndex = 0
            try cityUpgradePrompt(o)
        } else {
            try sanctionPromptWithCheck(o)
        }
    }

    /// doNuclearMoneyLeftSpeech
    func moneyLeft(_ o: Out) throws {
        let b = try us().balance
        if b <= 0 {
            o.don(Lines.spentAll)
        } else {
            o.part(Lines.youHave)
            o.money(b)
            o.don(Lines.left)
        }
    }

    func canUpgrade(_ city: City?) throws -> Bool {
        guard let city else { return false }
        let b = try us().balance
        return !city.destroyed
            && ((b >= World.shield && city.shield == 0) || (b >= World.research && city.research == 0))
    }

    /// doCityUpgradePrompt: the first city to upgrade this round.
    func cityUpgradePrompt(_ o: Out) throws {
        st.q = .cityPrompt
        let names = try us().cities.map(\.name)
        let found = try us().cities.getOrNull(st.cityIndex)
        guard try canUpgrade(found), let city = found else {
            if found == nil { return try sanctionPromptWithCheck(o) }
            st.cityIndex += 1
            return try cityUpgradePrompt(o)
        }
        if city.shield == 0 && city.research > 0 { return try shieldPrompt(o) }
        if city.research == 0 && city.shield > 0 { return try researchPrompt(o) }
        if st.midGame {
            o.don(st.rundown ? Lines.wantUpgrade(city.name) : Lines.anyUpgradesOn(city.name))
        } else {
            o.don(try st.completed
                ? Lines.upgradesTo(at(names, 0))
                : Lines.threeCities(at(names, 0), at(names, 1), at(names, 2)))
        }
        o.reprompt(Lines.anyUpgradesTo(city.name))
    }

    /// doNextCityPrompt
    func nextCityPrompt(_ o: Out, howAbout: Bool = false) throws {
        st.q = .cityPrompt
        let found = try us().cities.getOrNull(st.cityIndex)
        guard try canUpgrade(found), let city = found else {
            if try st.cityIndex >= us().cities.count { return try sanctionPromptWithCheck(o) }
            st.cityIndex += 1
            return try nextCityPrompt(o)
        }
        if city.shield == 0 && city.research > 0 { return try shieldPrompt(o) }
        if city.research == 0 && city.shield > 0 { return try researchPrompt(o) }
        if try us().balance < World.shield { return try researchPrompt(o) }
        o.don(howAbout ? Lines.howAbout(city.name) : Lines.upgradesOn(city.name))
        o.reprompt(Lines.anyUpgradesTo(city.name))
    }

    /// doBuildOrResearchPrompt
    func buildOrResearchPrompt(_ o: Out) {
        st.q = .upgradePrompt
        o.don(Lines.costs)
        o.don(Lines.shieldOrResearch)
        o.reprompt(Lines.shieldOrResearchAgain)
    }

    /// doResearchPrompt
    func researchPrompt(_ o: Out) throws {
        st.q = .researchPrompt
        let name = try currentCity().name
        let text = st.rundown ? Lines.researchFor(name) : Lines.researchProductivity(name)
        o.don(text)
        o.reprompt(text)
    }

    /// doShieldPrompt
    func shieldPrompt(_ o: Out) throws {
        st.q = .shieldPrompt
        let text = Lines.shieldFor(try currentCity().name)
        o.don(text)
        o.reprompt(text)
    }

    /// doChooseResearch
    func chooseResearch(_ o: Out) throws {
        let us = try us()
        us.balance &-= World.research
        let city = try currentCity()
        city.research = 1
        us.mark("research-\(st.cityIndex)")
        o.clip(sfx("kaching"))
        o.bed(sfx("research"), 1.0)
        o.pause(0.5)
        o.don(Lines.productivity(city.name))
        o.part(Lines.youHave)
        o.money(us.balance)
        o.don(Lines.left)
        let enoughForResearch = us.balance >= World.research
        let enoughForShield = us.balance >= World.shield
        let doneAllCities = st.cityIndex >= us.cities.count - 1
        let doneShield = us.done.kContains("shield-\(st.cityIndex)")
        if doneAllCities {
            if doneShield {
                o.don(Lines.doneAll)
                try sanctionPromptWithCheck(o)
            } else if enoughForShield {
                try shieldPrompt(o)
            } else {
                try sanctionPromptWithCheck(o)
            }
        } else if !enoughForResearch {
            try sanctionPromptWithCheck(o)
        } else if doneShield {
            st.cityIndex += 1
            try nextCityPrompt(o)
        } else if enoughForShield {
            try shieldPrompt(o)
        } else {
            st.cityIndex += 1      // (the money left was just said)
            try nextCityPrompt(o)
        }
    }

    /// doChooseShield
    func chooseShield(_ o: Out) throws {
        let us = try us()
        let city = try currentCity()
        us.balance &-= World.shield
        city.shield = 1
        o.clip(sfx("kaching"))
        o.bed(sfx("shield"), 1.0)
        o.don(Lines.protectedNow(city.name))
        try moneyLeft(o)
        us.mark("shield-\(st.cityIndex)")
        if isFinalRound() {
            st.cityIndex += 1
            return try finalShieldPrompt(o)
        }
        let enoughForResearch = us.balance >= World.research
        let doneResearch = us.done.kContains("research-\(st.cityIndex)")
        let doneAllCities = st.cityIndex >= us.cities.count - 1
        if doneAllCities {
            if doneResearch {
                o.don(Lines.doneAll)
                try sanctionPromptWithCheck(o)
            } else if enoughForResearch {
                try researchPrompt(o)
            } else {
                try sanctionPromptWithCheck(o)
            }
        } else if !enoughForResearch {
            try sanctionPromptWithCheck(o)
        } else if doneResearch {
            st.cityIndex += 1
            try nextCityPrompt(o)
        } else {
            try researchPrompt(o)
        }
    }
}
