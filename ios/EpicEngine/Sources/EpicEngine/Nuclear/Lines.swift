// nuclear/Lines.kt (lines 1-607): Don's lines, and every text the game can say.

import Foundation

/**
 * Don's lines: what Alexa said in Nuclear War (the skill's addVoice calls and its Speech.js lists), word for word but
 * for punctuation, and with fewer of the random variations that have a name in them. Each line is one clip, found by
 * its text. A line with a name or a small number in it has a clip per value; lists of names, money and points are
 * said in pieces that carry on into each other (see [items] and [NuclearWar]).
 *
 * [all] lists every text the game can say, with the words around each piece so it's rendered as part of a sentence:
 * tools/games/nuclearwar.py renders them all, and NuclearWarTest checks that the game says nothing else.
 *
 * The lines with a country in them fail (as Kotlin's World.land does) for a ref that isn't one of the five.
 */
public enum Lines {
    /**
     * A text to render: [speak] is what Don reads when it differs from what's shown ("Saint Petersburg"); [before] and
     * [after] are the words around a piece of a sentence.
     */
    public struct Phrase: Equatable, Sendable {
        public let text: String
        public let speak: String
        public let before: String
        public let after: String

        public init(_ text: String, _ speak: String, _ before: String = "", _ after: String = "") {
            self.text = text
            self.speak = speak
            self.before = before
            self.after = after
        }
    }

    /// Kotlin's replaceFirstChar { it.uppercaseChar() }: the first character upper case, the rest as it is.
    static func cap(_ s: String) -> String {
        guard let first = s.unicodeScalars.first else { return s }
        let upper = first.properties.uppercaseMapping.unicodeScalars
        // uppercaseChar maps one UTF-16 unit to one: a character that would become two stays as it is.
        guard first.value < 0x10000, upper.count == 1, let u = upper.first, u.value < 0x10000 else { return s }
        return String(u) + String(s.unicodeScalars.dropFirst())
    }

    private static func v(_ ref: String) throws -> String { try World.voice(ref) }
    private static func bombs(_ n: Int) -> String { n == 1 ? "bomb" : "bombs" }
    private static func pts(_ n: Int) -> String { n == 1 ? "point" : "points" }

    /**
     * What Don is given to read for a text: numbers in words (ElevenLabs reads digits well, but its timings for them
     * are unreliable, and the clips are cut by those timings), and a few names as they're said.
     */
    public static func speak(_ text: String) throws -> String {
        let t = text.replacingOccurrences(of: "St Petersburg", with: "Saint Petersburg", options: .literal)
            .replacingOccurrences(of: "500K", with: "500 thousand", options: .literal)
            .replacingOccurrences(of: "%", with: " percent", options: .literal)
        // NUMBER, "\d[\d,]*(\.\d+)?" (Java's \d: ASCII digits), each match spelled out.
        let u = Array(t.utf16)
        func isDigit(_ c: UInt16) -> Bool { c >= 0x30 && c <= 0x39 }
        var out: [UInt16] = []
        var i = 0
        while i < u.count {
            guard isDigit(u[i]) else {
                out.append(u[i])
                i += 1
                continue
            }
            let start = i
            i += 1
            while i < u.count && (isDigit(u[i]) || u[i] == 0x2C) { i += 1 }
            var whole = String(decoding: u[start..<i].filter { $0 != 0x2C }, as: UTF16.self)
            var fraction: String?
            if i + 1 < u.count && u[i] == 0x2E && isDigit(u[i + 1]) {
                let f = i + 1
                i += 1
                while i < u.count && isDigit(u[i]) { i += 1 }
                fraction = String(decoding: u[f..<i], as: UTF16.self)
            }
            // Kotlin's toLong(): too many digits fail.
            guard let n = Int64(whole) else { throw PlayError("For input string: \"\(whole)\"") }
            whole = try spell(n)
            if let fraction {
                whole += " point " + (try fraction.utf16.map { try spell(Int64($0 - 0x30)) }.joined(separator: " "))
            }
            out += whole.utf16
        }
        return String(decoding: out, as: UTF16.self)
    }

    private static let small = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
        "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen"]
    private static let tens = ["", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]

    /// 109 is "one hundred nine", as ElevenLabs says it. (A negative number fails, as Kotlin's index does.)
    public static func spell(_ n: Int64) throws -> String {
        if n < 0 { throw PlayError("Index \(n) out of bounds for length \(small.count)") }
        if n < 20 { return small[Int(n)] }
        if n < 100 { return tens[Int(n / 10)] + (n % 10 != 0 ? "-" + small[Int(n % 10)] : "") }
        if n < 1000 { return small[Int(n / 100)] + " hundred" + (n % 100 != 0 ? " " + (try spell(n % 100)) : "") }
        if n < 1_000_000 {
            return try spell(n / 1000) + " thousand" + (n % 1000 != 0 ? " " + (try spell(n % 1000)) : "")
        }
        return try spell(n / 1_000_000) + " million" + (n % 1_000_000 != 0 ? " " + (try spell(n % 1_000_000)) : "")
    }

    private static let options = "France, the USA, the UK, China or Russia"

    // ----- Starting: doPlayNuclearWar, doChooseCountry, the meetings -----

    public static let welcome = "Welcome to the nuclear war game."
    public static let playAs = "Would you like to play as \(options)?"
    public static let welcomeBack = "Welcome back to nuclear war. Would you like to play as \(options)?"
    public static let whichCountry = "Which country would you like to play as? \(options)."
    public static let chooseFrom = "Choose from: \(options)."
    public static let meetFirst =
        "Before making decisions in round one, it is a good idea to meet the representatives from the other countries."

    public static func leaderOf(_ ref: String) throws -> String { "You are now the leader of \(try v(ref))." }
    public static func meet(_ ref: String) throws -> String { "Would you like to meet \(try v(ref))?" }
    public static func meetFinally(_ ref: String) throws -> String { "Finally, would you like to meet \(try v(ref))?" }
    public static func meetLeader(_ ref: String) throws -> String {
        "Would you like to meet the leader of \(try v(ref))?"
    }

    // ----- Spending: nuclear tech, the environment, the cities -----

    public static let techStart = "Round 1. Now let's spend that 10 million. The first decision is to spend 5 million "
        + "and invest in nuclear tech. Do you want to invest in nuclear tech?"
    public static let tech = "Do you want to invest in nuclear tech?"
    public static let techSpend = "Would you like to spend 5 million on nuclear tech?"
    public static let techDone = "You now have nuclear tech. In the next round you will be able to buy bombs."
    public static let envStart = "Would you like to spend 1 million and improve the environment by 15%?"
    public static let env = "Would you like to spend 1 million on the environment?"
    public static let envBack = "The environment is back to 100 percent."
    public static func envAt(_ percent: Int) -> String { "The environment is at \(percent) percent." }
    public static let envExtra = "This will bring in an extra 500K for all countries each round."
    public static let spentAll = "You have spent all your money."
    public static let doneAll = "You've done work to all your cities."
    public static let everyCity = "You've gone through every city."
    public static let allCities = "You've gone through all your cities."
    public static let costs = "A shield costs 3 million, and research costs 2 million."
    public static let shieldOrResearch = "Want to build a shield, or do research?"
    public static let shieldOrResearchAgain = "Build a shield, or do research?"

    public static func wantUpgrade(_ city: String) -> String { "Want to upgrade \(city)?" }
    public static func anyUpgradesOn(_ city: String) -> String { "Do you want to do any upgrades on \(city)?" }
    public static func upgradesTo(_ city: String) -> String { "Do you want to do upgrades to \(city)?" }
    public static func anyUpgradesTo(_ city: String) -> String { "Do you want to do any upgrades to \(city)?" }
    public static func threeCities(_ a: String, _ b: String, _ c: String) -> String {
        "Now you have 3 cities to defend and improve. \(a), \(b) and \(c). Do you want to do upgrades to \(a)?"
    }
    public static func howAbout(_ city: String) -> String { "How about \(city)?" }
    public static func upgradesOn(_ city: String) -> String { "Want to do upgrades on \(city)?" }
    public static func researchFor(_ city: String) -> String { "Would you like to do research for \(city)?" }
    public static func researchProductivity(_ city: String) -> String {
        "Would you like to do research and increase productivity of \(city)?"
    }
    public static func shieldFor(_ city: String) -> String { "Would you like to build a shield for \(city)?" }
    public static func productivity(_ city: String) -> String {
        "\(city) now has increased productivity and will bring in an extra 1 million every round."
    }
    public static func protectedNow(_ city: String) -> String { "\(city) is now protected from one nuclear strike." }
    public static func alreadyShield(_ city: String) -> String { "You already have a shield on \(city)." }
    public static func noMoneyShield(_ city: String) -> String {
        "You don't have enough money for a shield for \(city)."
    }
    public static func alreadyResearch(_ city: String) -> String { "You already have research on \(city)." }

    // ----- Sanctions -----

    public static let removeAny = "Want to remove any sanctions?"
    public static let addAny = "Want to add any sanctions?"
    public static let addAnyLong = "Would you like to add sanctions to any country?"
    public static let sanctionAny = "Would you like to sanction any country?"
    public static let removeFromOne = "Would you like to remove sanctions from a country?"
    public static let removeMore = "Would you like to remove anymore sanctions?"
    public static let sanctionedAll = "You have sanctioned all the countries."
    public static let sanctionAnother = "Want to sanction another country?"
    public static let sanctionOwn = "You can't sanction your own country!"
    public static let unsanctionOwn = "You can't unsanction your own country!"
    public static let sanctionedYou = "They've just sanctioned you."

    /// "Sanction France, the UK or China." (2 to 4 countries, in [World.ordered] order).
    public static func sanctionList(_ refs: [String]) throws -> String {
        let n = try refs.map(v)
        switch n.count {
        case 4: return "Sanction \(n[0]), \(n[1]), \(n[2]) or \(n[3])."
        case 3: return "Sanction \(n[0]), \(n[1]) or \(n[2])."
        default: return "Sanction \(try at(n, 0)) or \(try at(n, 1))."
        }
    }

    public static func sanctionOne(_ ref: String) throws -> String { "Would you like to sanction \(try v(ref))?" }
    public static func sanctioned(_ ref: String) throws -> String { "\(cap(try v(ref))) has been sanctioned." }
    public static func alreadySanctioned(_ ref: String) throws -> String {
        "You have already sanctioned \(try v(ref))."
    }
    public static func cantSanction(_ ref: String) throws -> String { "You can't sanction \(try v(ref))." }

    /// The skill's doRemoveSanctionPrompt list: "France, the UK, or China."
    private static func orList(_ refs: [String]) throws -> String {
        let n = try refs.map(v)
        guard let last = n.last else { throw PlayError("List is empty.") }
        return n.dropLast().joined(separator: ", ") + ", or " + last + "."
    }

    public static func removeList(_ refs: [String]) throws -> String { "Remove sanctions from \(try orList(refs))" }
    public static func removeListAgain(_ refs: [String]) throws -> String {
        "Which country would you like to remove sanctions from? \(try orList(refs))"
    }
    public static func removeOne(_ ref: String) throws -> String {
        "Would you like to remove sanctions from \(try v(ref))?"
    }
    public static func youRemoved(_ ref: String) throws -> String { "You have removed the sanctions on \(try v(ref))." }
    public static func noSanctionsOn(_ ref: String) throws -> String {
        "\(cap(try v(ref))) doesn't have any sanctions!"
    }
    public static func notToUnsanction(_ ref: String) throws -> String {
        "\(cap(try v(ref))) is not available to unsanction."
    }
    public static func removedOnYou(_ ref: String) throws -> String {
        "\(cap(try v(ref))) has removed the sanctions on your country."
    }

    // ----- Bombs: buying and aiming -----

    public static func bombsLeft(_ n: Int) -> String { "You have \(n) \(bombs(n)) left." }
    public static func haveBombs(_ n: Int) -> String { "You have \(n) \(bombs(n))." }
    public static func buyMore(_ n: Int) -> String { "You have \(n) \(bombs(n)), want to buy anymore?" }
    public static func buyMoreAgain(_ n: Int) -> String { "You have \(n) \(bombs(n)), would you like to buy anymore?" }
    public static func affordUpTo(_ n: Int) -> String { "You can afford up to \(n) \(bombs(n))." }
    public static func nowHave(_ n: Int) -> String { "You now have \(n) \(bombs(n)) and" }
    public static func dontUse(_ n: Int) -> String { "You don't use your \(bombs(n))." }
    public static func keepForLater(_ n: Int) -> String { "You keep your \(n) \(bombs(n)) for later." }
    public static func reserve(_ n: Int) -> String { "Finally, you have \(n) \(bombs(n)) in reserve." }
    public static func directedAll(_ n: Int) -> String { "You have directed all \(n) of your bombs." }
    public static let directedOne = "You have directed your only bomb."
    public static let directedTwo = "You have directed both of your bombs."
    public static let useIt = "Would you like to use it?"
    public static let useAnother = "Want to use another bomb?"
    public static let useAnotherAgain = "Would you like to use another bomb?"
    public static let useOne = "Want to use one?"
    public static let useABomb = "Want to use a bomb?"
    public static let useABombLong = "Would you like to use a bomb?"
    public static let buyAny = "Would you like to buy any bombs?"
    public static let buyNuclear = "Would you like to buy nuclear bombs?"
    public static let bombCost = "Bombs cost 3 million each."
    public static let howMany = "How many bombs would you like to buy?"
    public static let howManySay = "How many bombs would you like to buy? Say a number."
    public static let didntCatch = "Didn't catch that."
    public static let onePerCity = "You can only use one bomb per city."
    public static let ownCountry = "I don't think bombing your own country is a good idea."
    public static let canYouRepeat = "Can you repeat that?"

    /// "Attack France, the UK or China." (2 to 4 countries).
    public static func attackCountries(_ refs: [String]) throws -> String {
        let n = try refs.map(v)
        switch n.count {
        case 4: return "Attack \(n[0]), \(n[1]), \(n[2]) or \(n[3])."
        case 3: return "Attack \(n[0]), \(n[1]), or \(n[2])."
        default: return "Attack \(try at(n, 0)) or \(try at(n, 1))."
        }
    }

    public static func whichCountryAttack(_ refs: [String]) throws -> String {
        let attack = try attackCountries(refs)
        // Kotlin's removePrefix("Attack ").
        let rest = attack.hasPrefix("Attack ") ? String(attack.dropFirst(7)) : attack
        return "Which country would you like to attack? " + rest
    }
    public static func wantAttack(_ ref: String) throws -> String { "Want to attack \(try v(ref))?" }
    public static func wouldAttack(_ ref: String) throws -> String { "Would you like to attack \(try v(ref))?" }
    public static func cantBomb(_ ref: String) throws -> String { "You can't bomb \(try v(ref))." }
    public static func allSet(_ ref: String) throws -> String {
        "You have already set bombs on all cities in \(try v(ref))."
    }
    public static func noCitiesLeft(_ ref: String) throws -> String {
        "\(cap(try v(ref))) hasn't got any cities left! You can't attack them."
    }
    public static func notEnoughForAll(_ ref: String) throws -> String {
        "You don't have enough bombs to bomb all of \(try v(ref))'s cities."
    }
    public static func sureBomb(_ ref: String) throws -> String { "Are you sure you want to bomb \(try v(ref))?" }
    public static func sureBombAll(_ ref: String) throws -> String {
        "You've gone through all the cities. Are you sure you want to bomb \(try v(ref))?"
    }
    public static func definitely(_ ref: String) throws -> String {
        "\(cap(try v(ref))) is definitely going to get it."
    }

    private static func cityOptions(_ cities: [String]) throws -> String {
        if cities.count == 2 { return "\(cities[0]) or \(cities[1])" }
        return "\(try at(cities, 0)), \(try at(cities, 1)) or \(try at(cities, 2))"
    }

    /// "Attack Paris, Lyon or Marseille." (2 or 3 of one country's cities).
    public static func attackCities(_ cities: [String]) throws -> String { "Attack \(try cityOptions(cities))." }
    public static func attackAll(_ cities: [String]) throws -> String {
        "Attack \(try at(cities, 0)), \(try at(cities, 1)), \(try at(cities, 2)), or all of them."
    }
    public static func whichCity(_ cities: [String]) throws -> String {
        "Which city do you want to attack? \(try cityOptions(cities))."
    }
    public static func wouldAttackCity(_ city: String) -> String { "Would you like to attack \(city)?" }
    public static func wantAttackCity(_ city: String) -> String { "Want to attack \(city)?" }
    public static func oneLeft(_ city: String) throws -> String {
        "There's just one city left in \(try v(World.landOf(city).ref)). \(city). Want to attack it?"
    }
    public static func launched(_ city: String) -> String { "A bomb will be launched on \(city)." }
    public static func picked(_ city: String) -> String { "\(city)." }
    public static func alreadyDestroyed(_ city: String) -> String { "\(city) has already been destroyed." }
    public static func bombSelf(_ city: String) -> [String] {
        [
            "It would be rather silly to bomb \(city), it's your own city!",
            "Bombing \(city)? No way! You don't want to destroy the place you live in.",
            "Bombing your own city would probably backfire.",
            "Don't bomb your own city! People will complain.",
        ]
    }

    // ----- The calls -----

    public static func callIncoming(_ ref: String) throws -> String {
        "A call from \(try v(ref)) is incoming. Would you like to answer?"
    }
    public static let answer = "Would you like to answer?"
    public static func callImportant(_ ref: String) throws -> String {
        "Would you like to answer a call from \(try v(ref)), it might be important."
    }
    public static func callAgain(_ ref: String) throws -> String {
        "Would you like to answer a call from \(try v(ref))?"
    }

    public static func longCall(_ ref: String) throws -> [String] {
        let c = try v(ref)
        return [
            "\(cap(c)) is calling.", "\(cap(c)) is ringing.", "\(cap(c)) is on the line.", "It's \(c) on the phone.",
            "A call from \(c) is incoming.", "Incoming call from \(c).", "You have a call from \(c) waiting.",
            "Your phone is ringing, it's \(c).",
        ]
    }

    public static func onHold(_ ref: String) throws -> [String] {
        let c = cap(try v(ref))
        return [
            "\(c) is on hold.", "\(c) is waiting.", "\(c) wants to speak with you.", "\(c) would like a chat.",
            "\(c) is waiting to talk.", "\(c) is on the line.",
        ]
    }

    public static let pickUp = [
        "Want to answer?", "Want to pick up?", "Shall we hear what they have to say?", "Want to listen?",
        "Will you pick up the phone?", "Want to chat?",
    ]

    public static let noCalls = [
        "It appears no one feels like giving you a call this round. Curious...",
        "This round, it's as if everyone is hesitant to dial your number. Peculiar.",
        "The lack of phone calls this round is quite baffling.",
        "Seems like no calls are coming through this round. Intriguing...",
        "This round, the phone remains quiet. Unexpected. Or maybe not.",
        "No one appears to be reaching out this round. How unusual.",
        "No calls for you this round, which is rather strange.",
        "This round, no one seems to be dialing your digits. How odd.",
        "Nobody seems to have you on speed dial this round. How bizarre.",
        "The phone lines seem unusually quiet this round.",
    ]

    public static let instaHangUp = [
        "They hung up straight away. Seems like they're trying to send a message.",
        "They hung up instantly. How cheeky.",
        "They hang up. Now that's a power move.",
        "Psych! They didn't even say anything.",
        "An immediate hang-up. It's as if they're making a statement.",
        "They disconnected. How sassy.",
        "They hung up without a word.",
        "The line went dead instantly. A silent protest.",
        "Click! They hung up, just like that.",
        "The call was over before it began.",
        "No conversation necessary, apparently.",
        "They didn't bother with small talk.",
    ]

    public static let tripleSanction = [
        "It's probably to do with sanctioning them for so long.",
        "It might be to do with the sanctioning.",
        "I think the sanctioning has taken its toll.",
        "It might be related to the duration of the sanctions.",
        "Sanctioning over time seems to have had an effect.",
        "Extended sanctioning might be a contributing factor.",
        "The ongoing sanctions could be taking their toll.",
        "It might be due to the long-standing sanctions.",
    ]

    public static func enemyAngry(_ ref: String) throws -> [String] {
        let l = try World.land(ref).leaderSays
        return [
            "Gosh, \(l) sounds really annoyed.", "Oh dear, \(l) has had better days.",
            "Yikes, \(l) is really steamed up.",
            "Oh my, \(l) is not a happy camper right now.", "Blimey, \(l) is quite miffed.",
            "Holy smokes, \(l) is fuming like a volcano!", "Uh-oh, you've really ruffled \(l)'s feathers.",
            "\(l) needs to take a breather.",
            "You've really riled them up. Watch out.", "Woops, you've definitely struck a chord with them.",
            "Golly, that was an awkward call.", "That call was hotter than a jalapeño!",
            "Well, that was a spicy meatball of a conversation!",
        ]
    }

    public static func singleNoTalk(_ ref: String) throws -> [String] {
        let c = try v(ref)
        return [
            "\(cap(c)) doesn't want to talk. How weird.", "\(cap(c)) doesn't want to chat. Now that's peculiar.",
            "Looks like \(c) is giving us the cold shoulder.", "\(cap(c)) has decided to ghost us. How mature.",
            "Seems like \(c) is taking a vow of silence.",
            "\(cap(c)) is ignoring us. Did we forget their birthday or something?",
        ]
    }

    /// Two countries, in [World.ordered] order.
    public static func twoNoTalk(_ a: String, _ b: String) throws -> [String] {
        let x = try v(a)
        let y = try v(b)
        return ["\(cap(x)) and \(y) don't want to talk.", "\(cap(x)) and \(y) seem to be unavailable.",
            "Neither \(x) or \(y) want to talk."]
    }

    public static func callsDone(_ round: Int) -> String { "All calls done. Round \(round) out of 5." }
    public static let finalMove = "Final round! Last chance to protect your cities, or attack."
    public static let finalRound = "Final round!"

    // ----- The bombing at the end of a round -----

    public static let youWillBomb = "You will bomb"
    public static func isBombing(_ ref: String) throws -> [String] {
        ["\(cap(try v(ref))) is bombing", "\(cap(try v(ref))) is nuking"]
    }
    public static let alsoBombing = "They are also bombing"
    public static let countdown = ["3", "2", "1"]

    public static func destroyCity(_ city: String) -> [String] {
        [
            "\(city) was blown to smithereens.", "\(city) has been vaporized.", "The blast wiped \(city) off the map.",
            "\(city) has been obliterated.", "\(city) has been reduced to radioactive rubble.", "\(city) is in ruins.",
        ]
    }

    /// After a list of cities: "Paris and Lyon" ...
    public static let destroyCities = [
        "have been blown to smithereens.", "have been turned to rubble.", "have been vaporized.",
        "have been obliterated by nukes.", "have been reduced to ashes.", "are in smoldering ruins.",
    ]

    public static func destroyShield(_ city: String) -> [String] {
        [
            "The shield on \(city) was blown up.", "The shield around \(city) has been shattered.",
            "The shield on \(city) has been obliterated.", "The forcefield on \(city) has been destroyed.",
            "The shield over \(city) has been crushed.", "The shield on \(city) has been broken.",
        ]
    }

    /// Around a list of cities: "The shields around" ... "have been shattered."
    public static let destroyShields: [(lead: String, tail: String)] = [
        ("The shields around", "have been shattered."), ("The shields on", "have been decimated."),
        ("The shields over", "have been crushed."), ("The forcefields on", "have been dismantled."),
    ]

    /// The countries knocked out this round (1 to 3, in [World.ordered] order).
    public static func countriesDestroyed(_ refs: [String]) throws -> [String] {
        let n = try refs.map(v)
        let list: String
        switch n.count {
        case 1: list = cap(n[0])
        case 2: list = "\(cap(n[0])) and \(n[1])"
        default: list = "\(cap(try at(n, 0))), \(try at(n, 1)) and \(try at(n, 2))"
        }
        if n.count == 1 {
            return [
                "\(list) has been destroyed and will no longer be in the war.",
                "The nation of \(n[0]) has been eliminated.",
                "\(list) has been removed from the war.", "\(list) has been knocked out.",
                "\(list) has been obliterated.",
            ]
        }
        return [
            "\(list) have been destroyed and will no longer be in the war.",
            "\(list) are no longer in the war after being nuked.", "\(list) have been knocked out.",
        ]
    }

    // ----- The end of a round: scores and money -----

    public static func roundComplete(_ round: Int) -> String { "Round \(round) of 5 complete." }
    public static let scores = "Here's the scores."
    public static let scoreParts = "Your score is made up of different parts."
    public static func bankPoints(_ points: Int) -> String { "This round, you got \(points) points for having" }
    public static let inTheBank = "in the bank."
    public static func envPoints(_ n: Int) -> String { "Your environmental contributions got you \(n) \(pts(n))." }
    private static func yourCities(_ cityPoints: Int) -> String {
        cityPoints == 5 ? "last city" : "\(cityPoints / 5) cities"
    }
    public static func researchAndCities(_ research: Int, _ cityPoints: Int) -> String {
        "You got \(research) points for research and \(cityPoints) for your \(yourCities(cityPoints))."
    }
    public static func shieldsAndCities(_ shields: Int, _ cityPoints: Int) -> String {
        "You got \(shields) \(pts(shields)) for your \(shields == 1 ? "shield" : "shields") and \(cityPoints) "
            + "points for your \(yourCities(cityPoints))."
    }
    public static func shieldsResearchAndCities(_ shields: Int, _ research: Int, _ cityPoints: Int) -> String {
        "You got \(shields) \(pts(shields)) for your shields and \(research) points for your research and "
            + "\(cityPoints) points for your \(yourCities(cityPoints))."
    }
    public static func citiesOnly(_ cityPoints: Int) -> String {
        "You got \(cityPoints) points for your \(yourCities(cityPoints))."
    }
    public static func citiesNoUpgrades(_ n: Int) -> String {
        "You have \(n) \(n == 1 ? "city" : "cities"), with no \(n == 1 ? "shield" : "shields") or research."
    }
    public static func citiesUpgraded(_ n: Int) -> String { "You have \(n) upgraded \(n == 1 ? "city" : "cities")." }
    public static let noEarnings = "You didn't earn any money this round."
    public static let youLost = "You lost"
    public static let thisRound = "this round."
    public static let youReceived = "You received"
    public static let inEarnings = "in earnings this round."
    public static let youHave = "You have"
    public static let toSpend = "to spend."
    public static let left = "left."
    public static let leftInBank = "left in the bank."
    public static let nothing = "nothing"

    public static func money(_ amount: Int64) -> String { World.formatMillions(World.sayable(amount)) }
    public static func points(_ n: Int) -> String {
        let p = Swift.min(Swift.max(n, 0), World.pointsMax)
        return "\(p) \(pts(p))."
    }

    /// Who a score line is about: "you" or a country.
    public static func subject(_ ref: String?) throws -> String {
        guard let ref else { return "you" }
        return try v(ref)
    }

    /// "You are in second with" / "France are in last with".
    public static func placing(_ ref: String?, _ place: String) throws -> String {
        "\(cap(try subject(ref))) are in \(place) with"
    }
    public static func tiePlacing(_ place: String) -> String {
        place == "last" ? "are last with" : "are \(place) equal with"
    }
    public static func endPlacing(_ ref: String?, _ place: String) throws -> String {
        "\(cap(try subject(ref))) came \(place) with"
    }
    public static func endTiePlacing(_ place: String) -> String {
        switch place {
        case "last": "came last with"
        case "first": "came joint first with"
        default: "came \(place) equal with"
        }
    }

    // ----- Game over -----

    public static let gameOver = "Game Over."
    public static let everyCountry = "Every country has been destroyed!"
    public static func victory(_ ref: String) throws -> String {
        "You have successfully brought \(try v(ref)) to victory!"
    }
    public static let lightning = "A lightning bolt is flying through the skies."
    public static let warStopped = "The war was stopped due to the environment being so heavily damaged."

    public static let everyoneDestroyed = [
        "Every country has been blown to smithereens.", "Every country has been nuked to kingdom come.",
        "Every country has had their cities reduced to rubble.",
        "Every country has been devastated beyond recognition.",
        "Every country has been wiped off the face of the earth.", "Every country has been annihilated.",
        "Every country has been left in ruins.", "Every country has been erased from the map of the world.",
    ]

    public static let weLose = [
        "Uh-oh! All your cities are destroyed, so you're out of the war.",
        "Sorry, your cities got destroyed, and you can't fight anymore.",
        "Your cities are gone, so you're out of the fight, my friend.",
        "Looks like you're out of the war since all your cities are destroyed.",
        "Bad news, all your cities have been destroyed, and you can't fight anymore.",
        "Unfortunately, your cities have been destroyed, so you're out of the fight.",
        "All your cities are destroyed, so you're out of the war.",
        "Your cities have been destroyed, and you're out of the battle.",
        "Your cities have been destroyed, so you're out of the battlefield.",
        "All your cities have been destroyed, and you're out of the war.",
    ]

    // ----- Lists said a name at a time -----

    /// How a list ends: "and Moscow." (the sentence ends), "and Moscow" (it carries on), "and you," (", are ...").
    public enum Last: Sendable {
        case end
        case on
        case comma
    }

    /**
     * A list of names as pieces: "Paris," "Lyon" "and Moscow." The first is capitalised (a list of countries can start
     * a sentence: "The UK," ...). A single name is "Paris." or "Paris".
     */
    public static func items(_ names: [String], _ last: Last) -> [String] {
        if names.count == 1 { return [cap(names[0]) + (last == .end ? "." : "")] }
        return names.enumerated().map { i, n in
            let name = i == 0 ? cap(n) : n
            switch i {
            case names.count - 1:
                switch last {
                case .end: return "and \(name)."
                case .on: return "and \(name)"
                case .comma: return "and \(name),"
                }
            case names.count - 2: return name
            default: return "\(name),"
            }
        }
    }

    // ----- Everything Don says -----

    public static func all() throws -> [Phrase] {
        var out = LinkedMap<Phrase>()
        func add(_ text: String) throws {
            if !out.contains(text) { out[text] = Phrase(text, try speak(text)) }
        }
        func part(_ text: String, _ before: String, _ after: String) throws {
            if !out.contains(text) { out[text] = Phrase(text, try speak(text), try speak(before), try speak(after)) }
        }
        func addAll(_ texts: [String]) throws { for t in texts { try add(t) } }
        let refs = World.refs
        let cities = World.cities
        let bombsRange = 1...World.bombsMax
        func subsets(_ min: Int, _ max: Int) -> [[String]] {
            (1..<(1 << refs.count)).map { m in refs.enumerated().filter { m & (1 << $0.offset) != 0 }.map(\.element) }
                .filter { $0.count >= min && $0.count <= max }
        }

        try addAll([welcome, playAs, welcomeBack, whichCountry, chooseFrom, meetFirst, techStart, tech,
            techSpend, techDone, envStart, env, envBack, envExtra, spentAll, doneAll, everyCity, allCities,
            costs, shieldOrResearch, shieldOrResearchAgain, removeAny, addAny, addAnyLong, sanctionAny,
            removeFromOne, removeMore, sanctionedAll, sanctionAnother, sanctionOwn, unsanctionOwn, sanctionedYou,
            directedOne, directedTwo, useIt, useAnother, useAnotherAgain, useOne, useABomb, useABombLong,
            buyAny, buyNuclear, bombCost, howMany, howManySay, didntCatch, onePerCity, ownCountry,
            canYouRepeat, answer, finalMove, finalRound, scores, scoreParts, noEarnings, gameOver, everyCountry,
            lightning, warStopped])
        try addAll(pickUp + noCalls + instaHangUp + tripleSanction + everyoneDestroyed + weLose)
        for p in stride(from: 0, through: World.percentMax, by: 5) { try add(envAt(p)) }
        for r in 1...4 { try add(roundComplete(r)) }
        for r in 2...4 { try add(callsDone(r)) }

        for ref in refs {
            try addAll([leaderOf(ref), meet(ref), meetFinally(ref), meetLeader(ref), sanctionOne(ref), sanctioned(ref),
                alreadySanctioned(ref), cantSanction(ref), removeOne(ref), youRemoved(ref), noSanctionsOn(ref),
                notToUnsanction(ref), removedOnYou(ref), wantAttack(ref), wouldAttack(ref), cantBomb(ref), allSet(ref),
                noCitiesLeft(ref), notEnoughForAll(ref), sureBomb(ref), sureBombAll(ref), definitely(ref),
                callIncoming(ref), callImportant(ref), callAgain(ref), victory(ref)])
            try addAll(longCall(ref) + onHold(ref) + enemyAngry(ref) + singleNoTalk(ref))
            for lead in try isBombing(ref) { try part(lead, "", "London and Cardiff.") }
            let own = try World.land(ref).cities
            for order in permutations(own) { try add(threeCities(order[0], order[1], order[2])) }
            for n in 2...3 {
                for sub in combinations(own, n) {
                    try add(attackCities(sub))
                    try add(whichCity(sub))
                    if n == 3 { try add(attackAll(sub)) }
                }
            }
        }
        for pair in subsets(2, 2) { try addAll(twoNoTalk(pair[0], pair[1])) }
        for sub in subsets(1, 3) { try addAll(countriesDestroyed(sub)) }
        for sub in subsets(2, 4) {
            try addAll([sanctionList(sub), removeList(sub), removeListAgain(sub), attackCountries(sub),
                whichCountryAttack(sub)])
        }

        for city in cities {
            try addAll([wantUpgrade(city), anyUpgradesOn(city), upgradesTo(city), anyUpgradesTo(city), howAbout(city),
                upgradesOn(city), researchFor(city), researchProductivity(city), shieldFor(city), productivity(city),
                protectedNow(city), alreadyShield(city), noMoneyShield(city), alreadyResearch(city),
                wouldAttackCity(city),
                wantAttackCity(city), oneLeft(city), launched(city), alreadyDestroyed(city)])
            try addAll(bombSelf(city) + destroyCity(city) + destroyShield(city))
            // In lists: "You will bomb Paris, Lyon and Moscow." / "Paris and Lyon have been vaporized."
            try part(picked(city), "You will bomb", "")
            try part("\(city),", "You will bomb", "Lyon and Moscow.")
            try part(city, "You will bomb Paris,", "and Moscow.")
            try part("and \(city).", "You will bomb Paris, Lyon", "")
            try part("and \(city)", "Paris, Lyon", "have been vaporized.")
        }
        for tail in destroyCities { try part(tail, "Paris, Lyon and Moscow", "") }
        for (lead, tail) in destroyShields {
            try part(lead, "", "Paris and Lyon \(tail)")
            try part(tail, "\(lead) Paris and Lyon", "")
        }
        try part(youWillBomb, "", "Paris, Lyon and Moscow.")
        try part(alsoBombing, "", "Paris and Lyon.")
        // Set, not getOrPut: a countdown text already there keeps its place and takes this.
        for (i, n) in countdown.enumerated() { out[n] = Phrase(n, "\(["Three", "Two", "One"][i]).") }

        for n in bombsRange {
            try addAll([bombsLeft(n), haveBombs(n), buyMore(n), buyMoreAgain(n), keepForLater(n), reserve(n)])
            try part(nowHave(n), "", "4 million left in the bank.")
        }
        for n in 0...World.bombsMax { try add(affordUpTo(n)) }
        for n in 3...World.bombsMax { try add(directedAll(n)) }
        try add(dontUse(1))
        try add(dontUse(2))

        // Scores
        for n in 1...5 { try add(envPoints(n)) }
        for c in [5, 10, 15] {
            try add(citiesOnly(c))
            for r in [2, 4, 6] { try add(researchAndCities(r, c)) }
            for s in 1...3 {
                try add(shieldsAndCities(s, c))
                for r in [2, 4, 6] { try add(shieldsResearchAndCities(s, r, c)) }
            }
        }
        for n in 1...3 {
            try add(citiesNoUpgrades(n))
            try add(citiesUpgraded(n))
        }
        for p in [2, 4] { try part(bankPoints(p), "", "12 million in the bank.") }
        let places = ["first", "second", "third", "fourth", "fifth", "last"]
        let everyone: [String?] = [nil] + refs.map(Optional.some)
        for who in everyone {
            for place in places {
                try part(placing(who, place), "", "12 points.")
                try part(endPlacing(who, place), "", "12 points.")
            }
        }
        for place in places {
            // (a comma before them: Don runs "you came" together, with no gap to cut in)
            try part(tiePlacing(place), "France and you,", "12 points.")
            try part(endTiePlacing(place), "France and you,", "12 points.")
        }
        for n in 0...World.pointsMax { try part(points(n), "You are in second with", "") }
        // Ties: "France, the UK and you, are second equal with"
        for who in everyone {
            let name = try subject(who)
            try part("\(cap(name)),", "", "Russia and you, are second equal with 12 points.")
            try part(cap(name), "", "and you, are second equal with 12 points.")
            try part("\(name),", "France,", "Russia and you, are second equal with 12 points.")
            try part(name, "France,", "and you, are second equal with 12 points.")
            try part("and \(name),", "France, Russia", "are second equal with 12 points.")
            try part("and \(name)", "France, Russia", "came second equal with 12 points.")
        }

        // Money: "You have 12 million left."
        for lead in [youHave, youLost, youReceived] { try part(lead, "", "12 million left.") }
        for amount in World.sayableAmounts() { try part(World.formatMillions(amount), "You have", "left.") }
        try part(nothing, "You now have 3 bombs and", "left in the bank.")
        for tail in [left, toSpend, thisRound, inEarnings, inTheBank, leftInBank] {
            try part(tail, "You have 12 million", "")
        }
        return out.values
    }

    private static func permutations<T: Equatable>(_ items: [T]) -> [[T]] {
        if items.count <= 1 { return [items] }
        return items.flatMap { x in
            // Kotlin's `items - x`: the first x taken out.
            var rest = items
            if let i = rest.firstIndex(of: x) { rest.remove(at: i) }
            return permutations(rest).map { [x] + $0 }
        }
    }

    private static func combinations<T>(_ items: [T], _ n: Int) -> [[T]] {
        if n == 0 { return [[]] }
        if items.count < n { return [] }
        let rest = Array(items.dropFirst())
        return combinations(rest, n - 1).map { [items[0]] + $0 } + combinations(rest, n)
    }

    /// Kotlin's list[i]: an index out of range fails (IndexOutOfBoundsException) instead of trapping.
    static func at<T>(_ list: [T], _ i: Int) throws -> T {
        guard list.indices.contains(i) else { throw PlayError("Index \(i) out of bounds for length \(list.count)") }
        return list[i]
    }
}
