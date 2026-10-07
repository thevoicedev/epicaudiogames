// nuclear/NuclearWar.kt (lines 1978-2098): the scores (getNuclearTeamRanks, getAllScoreSpeech) and the game's ends.

extension NuclearWar {
    // ----- Scores: getNuclearTeamRanks, createScoresArray, getAllScoreSpeech, doGameOverScoreSpeech -----

    /// A country's score in the rankings ([ref] nil: you).
    struct Rank {
        let ref: String?
        let score: Int
    }

    /// The countries still in the war and you, best first, ties grouped (you first in a pair, last in a bigger tie).
    func scoreGroups() throws -> [[Rank]] {
        let us = try us()
        let all = (st.countries.filter { !$0.destroyed }.map { Rank(ref: $0.ref, score: $0.score) }
            + (us.destroyed ? [] : [Rank(ref: nil, score: us.score)])).stableSorted(descending: true) { $0.score }
        var groups: [[Rank]] = []
        for r in all {
            if let last = groups.last?.last, last.score == r.score {
                groups[groups.count - 1].append(r)
            } else {
                groups.append([r])
            }
        }
        return groups.map { g in
            if g.count < 2 { return g }
            let usHere = g.filter { $0.ref == nil }
            let others = g.filter { $0.ref != nil }
            return g.count == 2 ? usHere + others : others + usHere
        }
    }

    /// The place said for a group: "last", "first", or its ordinal counting the ties above it.
    func placeOf(_ groups: [[Rank]], _ x: Int) throws -> String {
        if x == 0 { return "first" }      // before "last": everyone tied is joint first
        if x == groups.count - 1 { return "last" }
        var place = x + 1
        // Kotlin's take(x) fails below 0.
        guard x >= 0 else { throw PlayError("Requested element count \(x) is less than zero.") }
        let above = groups.prefix(x).reduce(0) { $0 + $1.count }
        if place >= 2 && place <= 4 && above > x { place += above - x }
        return World.ordinal(place)
    }

    /// The scores, last place first (getAllScoreSpeech; [end]: doGameOverScoreSpeech, "came" not "are in").
    func scoreSpeech(_ o: Out, end: Bool) throws {
        let groups = try scoreGroups()
        for x in groups.indices.reversed() {
            let place = try placeOf(groups, x)
            let group = groups[x]
            let first = end && place == "first"
            if first {
                o.bed(sfx("marching"), 1.0)
                o.pause(3.0)
                o.bed(sfx("triumph"), 1.0)
                o.pause(2.0)
            }
            if group.count > 1 {
                o.items(try group.map { try Lines.subject($0.ref) }, end ? .on : .comma)
                o.part(end ? Lines.endTiePlacing(place) : Lines.tiePlacing(place))
            } else {
                o.part(try end ? Lines.endPlacing(group[0].ref, place) : Lines.placing(group[0].ref, place))
            }
            o.don(Lines.points(group[group.count - 1].score))
        }
    }

    // ----- Game over -----

    /// doNuclearGameOver: the five rounds are done.
    func nuclearGameOver(_ o: Out) throws {
        st.playedNuclear = true
        o.bed(sfx("longOrchestral"), 0.20)
        o.clip(sfx("trumpet"))
        o.don(Lines.gameOver)
        st.completed = true
        // (The skill's "<country> was knocked out" lines need countries it only lists when the environment
        // collapses, and then the game ends the other way: they're never said.)
        try scoreSpeech(o, end: true)
        let groups = try scoreGroups()
        for r in try at(groups, 0) { if let ref = r.ref { o.clip(audio.path(ref, "Victory")) } }
        o.stopBeds()
        let ours = groups.firstIndex { g in g.contains { $0.ref == nil } } ?? -1
        let place = try placeOf(groups, ours)
        let title: String
        if ours == 0 && groups[0].count == 1 {
            title = "You won the war!"
        } else if ours == 0 {
            title = "You came joint first"
        } else {
            title = "You came \(place)"
        }
        finish("ending", title)
    }

    /// everyCountryDestroyed
    func everyCountryDestroyed(_ o: Out) {
        o.bed(sfx("longOrchestral"), 0.25)
        o.don(Lines.everyCountry)
        o.stopBeds()
        finish("gameover", "Every country was destroyed")
    }

    /// destroyEveryOneGameOver: you're the last country standing.
    func destroyEveryOneGameOver(_ o: Out) throws {
        o.bed(sfx("longOrchestral"), 0.25)
        o.don(try Lines.everyoneDestroyed.kRandom(random))
        o.bed(sfx("marching"), 1.0)
        o.pause(3.0)
        o.bed(sfx("triumph"), 1.0)
        o.pause(2.0)
        o.don(try Lines.victory(us().ref))
        o.stopBeds()
        finish("ending", "The last country standing!")
    }

    /// doWeGotDestroyedGameOver
    func weGotDestroyedGameOver(_ o: Out) throws {
        o.bed(sfx("longOrchestral"), 0.30)
        o.pause(1.5)
        o.don(try Lines.weLose.kRandom(random))
        o.don(Lines.gameOver)
        o.stopBeds()
        finish("gameover", "Your cities were destroyed")
    }

    /// doHeavenlyEnvironmentDestruction: the environment gave out.
    func heavenlyEnvironmentDestruction(_ o: Out) {
        o.bed(sfx("halo"), 0.40)
        o.pause(0.5)
        o.don(Lines.lightning)
        o.bed(sfx("thunderbolt"), 1.0)
        o.pause(3.0)
        o.clip(sfx("dropExplode"))
        o.don(Lines.warStopped)
        o.stopBeds()
    }
}
