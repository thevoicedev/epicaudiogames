// nuclear/NuclearWar.kt (lines 646-744): sanctions: adding them, taking them off.

extension NuclearWar {
    // ----- Sanctions -----

    /// doSanctionPromptWithCheck
    func sanctionPromptWithCheck(_ o: Out) throws {
        if st.midGame {
            sanctionPrompt(o, mid: true, remove: st.countries.contains { $0.sanctioned })
        } else {
            sanctionPrompt(o)
        }
    }

    /// doSanctionPrompt
    func sanctionPrompt(_ o: Out, mid: Bool = false, remove: Bool = false) {
        st.q = .sanction
        let text: String
        if mid && remove {
            st.q = .removeSanctionPrompt
            text = Lines.removeAny
        } else if mid {
            text = st.rundown ? Lines.addAny : Lines.addAnyLong
        } else {
            text = Lines.sanctionAny
        }
        o.don(text)
        o.reprompt(text)
    }

    /// doCountrySanctionChoice
    func countrySanctionChoice(_ o: Out) throws {
        st.q = .sanctionCountry
        let remaining = World.ordered(st.countries.filter { !$0.sanctioned }.map(\.ref))
        let text: String
        if remaining.count >= 2 {
            text = try Lines.sanctionList(remaining)
        } else if remaining.count == 1 {
            st.q = .sanctionSpecific
            text = try Lines.sanctionOne(remaining[0])
        } else {
            return try bombsOrNextRound(o)      // the skill asks to sanction "undefined"
        }
        o.don(text)
        o.reprompt(text)
    }

    /// sanctionCountry
    func sanctionCountry(_ o: Out, _ ref: String) throws {
        if let c = st.countries.first(where: { $0.ref.kEquals(ref) }) {
            c.sanctioned = true
            c.wasSanctioned = false
        }
        // The skill's "and will get 20% less income" never plays: a country has always just been sanctioned.
        o.bed(sfx("stampFx"), 1.0)
        o.don(try Lines.sanctioned(ref))
        if st.countries.allSatisfy({ $0.sanctioned }) {
            o.don(Lines.sanctionedAll)
            try bombsOrNextRound(o)
        } else {
            st.q = .sanction
            o.don(Lines.sanctionAnother)
            o.reprompt(Lines.sanctionAnother)
        }
    }

    /// doRemoveSanctionPrompt
    func removeSanctionPrompt(_ o: Out) throws {
        st.q = .removeSanction
        let sanctioned = World.ordered(st.countries.filter { $0.sanctioned }.map(\.ref))
        if sanctioned.count < 2 { return try removeIndividualSanctionPrompt(o) }
        o.don(try Lines.removeList(sanctioned))
        o.reprompt(try Lines.removeListAgain(sanctioned))
    }

    /// doRemoveIndividualSanctionPrompt
    func removeIndividualSanctionPrompt(_ o: Out) throws {
        st.q = .removeIndividualSanction
        guard let c = st.countries.first(where: { $0.sanctioned }) else { return try sanctionPromptWithCheck(o) }
        o.don(try Lines.removeOne(c.ref))
        o.reprompt(try Lines.removeOne(c.ref))
    }

    /// unSanctionCountry
    func unsanctionCountry(_ o: Out, _ ref: String) throws {
        if let c = st.countries.first(where: { $0.ref.kEquals(ref) }) {
            c.sanctioned = false
            c.wasSanctioned = true
            c.stillSanctioned = false
        }
        o.bed(sfx("eraser"), 1.0)
        o.don(try Lines.youRemoved(ref))
        let left = st.countries.count(where: { $0.sanctioned })
        if left == 1 {
            try removeIndividualSanctionPrompt(o)
        } else if left > 1 {
            st.q = .removeSanctionPrompt
            o.don(Lines.removeMore)
            o.reprompt(Lines.removeMore)
        } else {
            try sanctionPromptWithCheck(o)
        }
    }

    func afterRemovingSanctions(_ o: Out) throws {
        if st.countries.contains(where: { !$0.sanctioned }) {
            sanctionPrompt(o, mid: true)
        } else {
            try bombsOrNextRound(o)
        }
    }
}
