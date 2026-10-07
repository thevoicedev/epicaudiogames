// nuclear/NuclearWar.kt (lines 1645-1806): what the other countries do (doCountryDecisions) and what they buy.

import Foundation

extension NuclearWar {
    // ----- What the other countries do: doCountryDecisions -----

    func rnd() throws -> Double { try random.nextDouble() }

    /// randomIntFromInterval
    func randomInt(_ min: Int, _ max: Int) throws -> Int {
        NuclearWar.int(floor(try rnd() * Double(NuclearWar.int(max - min + 1)) + Double(min)))
    }

    func countryDecisions() throws {
        let lateRounds = st.round > 3
        let us = try us()
        for x in st.countries {
            if x.destroyed { continue }
            if x.alive().count == 1 && x.balance >= World.shield {
                for c in x.cities where !c.destroyed && c.shield == 0 {
                    c.shield += 1
                    x.balance &-= World.shield
                }
            }
            func contribute() {
                x.balance &-= World.environment
                x.contributions += 1
                st.environment += 15
            }
            switch x.motivator {
            case "ENVIRONMENT":
                if x.balance >= World.environment { contribute() }
                if lateRounds && x.tech { maxOutBombs(x) }
                if (!x.bombedBy.isEmpty || st.environment < 0 || us.countriesBombed.kContains(x.ref)) && x.tech {
                    maxOutBombs(x)
                }
                try buyShieldsOrResearch(x)
            case "DEFENSE":
                if x.balance >= World.environment { contribute() }
                maxOutShields(x)
                // Its bombs: the skill works out how many from NaN, so it never buys any.
                if st.round >= 2 || !x.bombedBy.isEmpty || us.countriesBombed.kContains(x.ref) {
                    if !x.tech && x.balance >= World.tech {
                        x.balance &-= World.tech
                        x.tech = true
                        st.environment -= 10
                    }
                }
                var research = NuclearWar.int(Swift.min(3, x.balance / World.research))
                if research > 0 { research = try randomInt(1, research) }
                for c in x.cities where !c.destroyed && c.research == 0 && research > 0 {
                    c.research += 1
                    research -= 1
                    x.balance &-= World.research
                }
            case "FRIENDLY":
                if x.balance >= World.environment { contribute() }
                try randomlyBuyNuclearStuff(x)
                try randomlyBuyNuclearStuff(x)
                if try x.ref.kEquals("Russia") && rnd() < 0.65 { nuclearTechPurchasing(x) }
                if try rnd() < 0.5 { nuclearTechPurchasing(x) }
                try buyShieldsOrResearch(x)
            case "NUCLEAR":
                if try x.balance >= World.environment && rnd() < 0.5 { contribute() }
                if lateRounds && x.tech { maxOutBombs(x) }
                nuclearTechPurchasing(x)
                if st.round == 1 {
                    for c in x.cities where x.balance >= World.shield && !c.destroyed && c.shield == 0 {
                        c.shield += 1
                        x.balance &-= World.shield
                    }
                } else if try rnd() < 0.2 {
                    try buyShieldsOrResearch(x)
                }
                if x.balance < 5_000_000 { buyResearchEverywhere(x) }
                // The skill sets a chance of shields from the research count, but only checks it isn't zero.
                if x.cities.contains(where: { $0.research > 0 }) {
                    for c in x.cities where x.balance >= World.shield && !c.destroyed && c.shield == 0 {
                        c.shield += 1
                        x.balance &-= World.shield
                    }
                } else {
                    buyResearchEverywhere(x)
                }
            default:
                break
            }
        }
    }

    func buyResearchEverywhere(_ x: Nation) {
        for c in x.cities where x.balance >= World.research && !c.destroyed && c.research == 0 {
            c.research += 1
            x.balance &-= World.research
        }
    }

    func buyBomb(_ x: Nation) {
        x.balance &-= World.bomb
        x.bombs += 1
        x.strikesToUse += 1
        st.environment -= 5
    }

    /// randomlyBuyNuclearStuff
    func randomlyBuyNuclearStuff(_ x: Nation) throws {
        var options: [String] = []
        if x.balance >= World.research && x.cities.contains(where: { !$0.destroyed && $0.research == 0 }) {
            options.append("research")
        }
        if x.balance >= World.shield && x.cities.contains(where: { !$0.destroyed && $0.shield == 0 }) {
            options.append("shield")
        }
        if x.tech && st.round >= 2 && x.balance >= World.bomb { options.append("bombs") }
        switch try options.kRandomOrNull(random) {
        case "research"?:
            x.balance &-= World.research
            try x.cities.filter { !$0.destroyed && $0.research == 0 }.kRandomOrNull(random)?.research += 1
        case "shield"?:
            x.balance &-= World.shield
            try x.cities.filter { !$0.destroyed && $0.shield == 0 }.kRandomOrNull(random)?.shield += 1
        case "bombs"?:
            buyBomb(x)
        default:
            break
        }
    }

    /// doNuclearTechPurchasing
    func nuclearTechPurchasing(_ x: Nation) {
        if x.tech {
            let amount = NuclearWar.int(x.balance / World.bomb)
            if amount > 0 && x.bombs < 4 {
                times(Swift.min(amount, 100)) { if x.bombs < 5 { buyBomb(x) } }
            }
        } else if x.balance >= World.tech {
            x.tech = true
            x.balance &-= World.tech
            st.environment -= 10
        }
    }

    /// countryBuyShieldsOrResearch
    func buyShieldsOrResearch(_ x: Nation) throws {
        var research = Swift.min(3, x.balance / World.research)
        var shields = Swift.min(3, x.balance / World.shield)
        for c in x.cities {
            if try rnd() > 0.7 && !c.destroyed && c.research == 0 && research > 0 && x.balance >= World.research {
                c.research += 1
                research -= 1
                x.balance &-= World.research
            } else if !c.destroyed && c.shield == 0 && shields > 0 && x.balance >= World.shield {
                c.shield += 1
                shields -= 1
                x.balance &-= World.shield
            }
        }
    }

    /// maxOutBombs
    func maxOutBombs(_ x: Nation) {
        let amount = NuclearWar.int(x.balance / World.bomb)
        if amount > 0 && x.bombs < 3 {
            times(Swift.min(amount, 100)) { if x.bombs < 5 { buyBomb(x) } }
        }
    }

    /// maxOutShields
    func maxOutShields(_ x: Nation) {
        var n = Swift.min(3, x.balance / World.shield)
        if n > 0 {
            for c in x.cities where !c.destroyed && c.shield == 0 && n > 0 {
                c.shield += 1
                n -= 1
                x.balance &-= World.shield
            }
        }
    }
}
