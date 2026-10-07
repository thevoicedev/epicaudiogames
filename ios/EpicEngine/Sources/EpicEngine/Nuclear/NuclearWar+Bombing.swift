// nuclear/NuclearWar.kt (lines 1807-1977): the bombing at the end of a round (bombCountries) and who strikes whom.

extension NuclearWar {
    // ----- The bombing: bombCountries -----

    final class Bombing {
        var destroyedCities: [String] = []
        var destroyedShields: [String] = []
        /// additionalBombingMap: each country's targets this round, in the order they bombed.
        var strikes = LinkedMap<[String]>()
        var total = 0

        func hit(_ city: City) {
            if city.shield > 0 {
                city.shield -= 1
                destroyedShields.append(city.name)
            } else {
                city.destroyed = true
                destroyedShields.removeAll { $0.kEquals(city.name) }
                destroyedCities.append(city.name)
            }
        }
    }

    func bombCountries(_ o: Out) throws {
        let b = Bombing()
        b.total = st.citiesToBomb.count
        let us = try us()
        for x in st.countries {
            for city in x.cities {
                times(st.citiesToBomb.count(where: { $0.kEquals(city.name) })) { b.hit(city) }
            }
            if x.strikesToUse == 0 { continue }
            // The draw is made even when the final round throws its result away.
            var amount = try x.strikesToUse < 3 ? x.strikesToUse : randomInt(3, x.strikesToUse)
            if st.round > 4 { amount = x.strikesToUse }
            var bombedByThis: [String] = []
            try times(Swift.min(amount, 100)) {
                let insufficient = us.contributions == 0
                if x.attackUs != 0 && x.bombify.isEmpty {
                    // (this strike isn't counted in the skill's total, so it doesn't harm the environment)
                    _ = try bombOurCountry(x, &bombedByThis, b)
                } else if !x.bombify.isEmpty || x.attackUs != 0 || insufficient {
                    let struck: Bool
                    if !x.bombify.isEmpty && x.attackUs != 0 {
                        if try rnd() > 0.6 || insufficient {
                            struck = try bombOurCountry(x, &bombedByThis, b)
                        } else {
                            struck = try bombifyCountry(x, &bombedByThis, b)
                        }
                    } else if !x.bombify.isEmpty {
                        struck = try bombifyCountry(x, &bombedByThis, b)
                    } else {
                        struck = try bombOurCountry(x, &bombedByThis, b)
                    }
                    if struck { b.total += 1 }
                } else {
                    try fudge(x, &bombedByThis, b)
                }
            }
        }
        for c in st.countries where !c.destroyed && c.cities.count(where: \.destroyed) == 3 { c.destroyed = true }
        if us.cities.count(where: \.destroyed) == 3 { us.destroyed = true }

        if !st.citiesToBomb.isEmpty {
            o.part(Lines.youWillBomb)
            o.items(st.citiesToBomb.uniqued(), .end)
        }
        let ours = try World.land(us.ref).cities
        for (ref, cities) in b.strikes {
            let mine = cities.filter { ours.kContains($0) }
            let others = cities.filter { !ours.kContains($0) }
            if !mine.isEmpty {
                o.bed(sfx("alarm"), 0.5)
                o.pause(1.0)
                o.part(try Lines.isBombing(ref).kRandom(random))
                o.items(mine, .end)
                if !others.isEmpty {
                    o.part(Lines.alsoBombing)
                    o.items(others, .end)
                }
            } else {
                o.part(try Lines.isBombing(ref).kRandom(random))
                o.items(cities, .end)
            }
        }
        if st.citiesToBomb.isEmpty && b.strikes.isEmpty { return }
        times(b.total) {
            if st.environment > -100 {
                st.environment -= 5
                st.prevEnvironment -= 5
            }
        }
        for n in Lines.countdown {
            o.don(n)
            o.clip(sfx("singleBeep"))
        }
        o.clip(sfx("dropExplode"))
        let cities = b.destroyedCities.uniqued()
        let shields = b.destroyedShields.uniqued()
        if cities.isEmpty && shields.isEmpty { return }
        o.bed(try audio.paths("sfx", "dramaticFx").kRandomOrNull(random), 1.0)
        o.bed(sfx("orchestralShort"), 1.0)
        o.pause(0.5)
        if cities.count == 1 {
            o.don(try Lines.destroyCity(cities[0]).kRandom(random))
        } else if cities.count > 1 {
            o.items(cities, .on)
            o.don(try Lines.destroyCities.kRandom(random))
        }
        if shields.count == 1 {
            o.don(try Lines.destroyShield(shields[0]).kRandom(random))
        } else if shields.count > 1 {
            let (lead, tail) = try Lines.destroyShields.kRandom(random)
            o.part(lead)
            o.items(shields, .on)
            o.don(tail)
        }
        o.stopBeds()
    }

    func strike(_ x: Nation, _ city: City, _ bombedByThis: inout [String], _ b: Bombing) {
        bombedByThis.append(city.name)
        b.strikes[x.ref] = (b.strikes[x.ref] ?? []) + [city.name]
        b.hit(city)
    }

    /// bombOurCountry: true if a bomb was dropped.
    func bombOurCountry(_ x: Nation, _ bombedByThis: inout [String], _ b: Bombing) throws -> Bool {
        let ours = try us().cities.filter { !$0.destroyed && !bombedByThis.kContains($0.name) }
        if ours.isEmpty { return false }
        x.attackUs -= 1
        x.strikesToUse -= 1
        x.bombs -= 1
        x.hasAttackedUs = true
        // With three cities the skill's random choice never works: it's always the first.
        let i = try ours.count == 2 && rnd() >= 0.7 ? 1 : 0
        strike(x, ours[i], &bombedByThis, b)
        return true
    }

    /// bombifyCountry: a country bombing back at one that bombed it (always its first city that's left).
    func bombifyCountry(_ x: Nation, _ bombedByThis: inout [String], _ b: Bombing) throws -> Bool {
        guard let target = try st.countries.filter({ x.bombify.kContains($0.ref) }).kRandomOrNull(random) else {
            x.bombify.removeAll()
            return false
        }
        guard let city = target.cities.first(where: { !$0.destroyed && !bombedByThis.kContains($0.name) }) else {
            return false
        }
        x.strikesToUse -= 1
        x.bombs -= 1
        strike(x, city, &bombedByThis, b)
        return true
    }

    /**
     * The skill's "fudge": a strike at another computer country, sometimes the leader's or Russia's cities (never
     * yours: its check for that compares a boolean with a string).
     */
    func fudge(_ x: Nation, _ bombedByThis: inout [String], _ b: Bombing) throws {
        let places = st.countries.filter { !$0.ref.kEquals(x.ref) }
            .flatMap { c in c.cities.filter { !$0.destroyed && !bombedByThis.kContains($0.name) }.map(\.name) }
        if places.isEmpty { return }
        x.strikesToUse -= 1
        x.bombs -= 1
        b.total += 1
        let leader = st.countries.stableSorted(descending: true) { score($0) }.first
        var place: String?
        if let leader {
            let theirs = places.filter { p in leader.cities.contains { $0.name.kEquals(p) } }
            if try !theirs.isEmpty && rnd() < 0.3 { place = try theirs.kRandom(random) }
        }
        if place == nil && st.countries.contains(where: { $0.ref.kEquals("Russia") }) {
            let russian = try places.filter { try World.land("Russia").cities.kContains($0) }
            if try !russian.isEmpty && rnd() < 0.2 { place = try russian.kRandom(random) }
        }
        let target = try place ?? places.kRandom(random)
        for c in st.countries {
            for city in c.cities where city.name.kEquals(target) {
                c.bombedBy.append(x.ref)
                strike(x, city, &bombedByThis, b)
            }
        }
    }
}
