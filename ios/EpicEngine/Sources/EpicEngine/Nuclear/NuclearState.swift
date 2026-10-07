// nuclear/State.kt (lines 1-215): the question the game waits at, the countries, and one game's state as JSON.

/// The skill's SkillStates for Nuclear War: the question the game waits at (its raw value is Kotlin's Q name).
public enum Q: String, CaseIterable, Sendable {
    case chooseCountry = "CHOOSE_COUNTRY"
    case countrySelect = "COUNTRY_SELECT"
    case nuclearPrompt = "NUCLEAR_PROMPT"
    case environmentPrompt = "ENVIRONMENT_PROMPT"
    case cityPrompt = "CITY_PROMPT"
    case upgradePrompt = "UPGRADE_PROMPT"
    case researchPrompt = "RESEARCH_PROMPT"
    case shieldPrompt = "SHIELD_PROMPT"
    case sanction = "SANCTION"
    case sanctionCountry = "SANCTION_COUNTRY"
    case sanctionSpecific = "SANCTION_SPECIFIC"
    case removeSanctionPrompt = "REMOVE_SANCTION_PROMPT"
    case removeSanction = "REMOVE_SANCTION"
    case removeIndividualSanction = "REMOVE_INDIVIDUAL_SANCTION"
    case phoneCountry = "PHONE_COUNTRY"
    case bombPrompt = "BOMB_PROMPT"
    case bombNumberPrompt = "BOMB_NUMBER_PROMPT"
    case useBombs = "USE_BOMBS"
    case chooseBombCountry = "CHOOSE_BOMB_COUNTRY"
    case chooseBombCity = "CHOOSE_BOMB_CITY"
    case confirmBombPrompt = "CONFIRM_BOMB_PROMPT"
    case bombIndividual = "BOMB_INDIVIDUAL"
    case gameOver = "GAME_OVER"
}

/**
 * A Kotlin Int, kept in a Swift Int: 32 bits that wrap, as Kotlin's arithmetic does (Int.MAX_VALUE + 1 is
 * Int.MIN_VALUE). Each value stored keeps only its low 32 bits, so `x += 15` and `x -= n * 5` give what Kotlin's do
 * (a save made by hand can hold a count near the ends, and a count that went past them couldn't be read again).
 */
@propertyWrapper
public struct KotlinInt: Sendable {
    private var bits: Int32

    public init(wrappedValue: Int) { bits = Int32(truncatingIfNeeded: wrappedValue) }

    public var wrappedValue: Int {
        get { Int(bits) }
        set { bits = Int32(truncatingIfNeeded: newValue) }
    }
}

/**
 * A city: its shield and research (counts, as the skill keeps them), and whether it's been destroyed. A class, as in
 * Kotlin: the game changes cities it finds through filtered lists.
 */
public final class City {
    public let name: String
    @KotlinInt public var shield = 0
    @KotlinInt public var research = 0
    public var destroyed = false

    public init(_ name: String) { self.name = name }
}

/**
 * A country in the war (the skill's createCountrySessionObj, and the fields its code adds on the way). Ints are
 * Kotlin Ints ([KotlinInt]); [balance] is a Long, so the game changes it with &+ and &-, which wrap as Kotlin's do.
 */
public final class Nation {
    public let ref: String
    public var balance: Int64 = 10_000_000
    public var motivator = ""
    @KotlinInt public var strikesToUse = 0
    @KotlinInt public var contributions = 0
    @KotlinInt public var bombs = 0
    public var bombedBy: [String] = []
    public var sanctionedBy: [String] = []
    public var countriesBombed: [String] = []
    public var tech = false
    public var cities: [City] = []
    public var bombify: [String] = []
    @KotlinInt public var score = 0
    public var sanctioned = false
    public var wasSanctioned = false
    public var stillSanctioned = false
    public var destroyed = false
    /// A count in the skill (and "angry" whenever it isn't 0, even below it).
    @KotlinInt public var attackUs = 0
    public var hasAttackedUs = false
    public var hasMet = false
    /// The leaders' recorded lines already played, per kind ("general", "defense", "friendly", "nuclear").
    public var used = LinkedMap<[Int]>()
    /// Ours: the skill's "shield-<i>" and "research-<i>" flags (set when bought, never cleared). A set in insertion
    /// order (Kotlin's LinkedHashSet): use [mark] to add one.
    public private(set) var done: [String] = []

    public init(_ ref: String) { self.ref = ref }

    public func alive() -> [City] { cities.filter { !$0.destroyed } }

    /// Adds a flag to [done], once (by its UTF-16 units, as Kotlin's set has it).
    public func mark(_ flag: String) {
        if !done.kContains(flag) { done.append(flag) }
    }

    public func toJSON() -> JSONObject {
        var o = JSONObject()
        o["ref"] = .string(ref)
        o["balance"] = .literal(String(balance))
        o["motivator"] = .string(motivator)
        o["strikesToUse"] = int(strikesToUse)
        o["contributions"] = int(contributions)
        o["bombs"] = int(bombs)
        o["bombedBy"] = strings(bombedBy)
        o["sanctionedBy"] = strings(sanctionedBy)
        o["countriesBombed"] = strings(countriesBombed)
        o["tech"] = .bool(tech)
        o["cities"] = .array(cities.map { c in
            var city = JSONObject()
            city["name"] = .string(c.name)
            city["shield"] = int(c.shield)
            city["research"] = int(c.research)
            city["destroyed"] = .bool(c.destroyed)
            return .object(city)
        })
        o["bombify"] = strings(bombify)
        o["score"] = int(score)
        o["sanctioned"] = .bool(sanctioned)
        o["wasSanctioned"] = .bool(wasSanctioned)
        o["stillSanctioned"] = .bool(stillSanctioned)
        o["destroyed"] = .bool(destroyed)
        o["attackUs"] = int(attackUs)
        o["hasAttackedUs"] = .bool(hasAttackedUs)
        o["hasMet"] = .bool(hasMet)
        o["used"] = .object(used.mapValues { list in .array(list.map(int)) })
        o["done"] = strings(done)
        return o
    }

    public static func fromJSON(_ o: JSONObject) throws -> Nation {
        let n = Nation(try o.str("ref"))
        n.balance = try o.value("balance").primitive().long()
        n.motivator = try o.str("motivator")
        n.strikesToUse = try o.int("strikesToUse")
        n.contributions = try o.int("contributions")
        n.bombs = try o.int("bombs")
        n.bombedBy += try o.strings("bombedBy")
        n.sanctionedBy += try o.strings("sanctionedBy")
        n.countriesBombed += try o.strings("countriesBombed")
        n.tech = try o.bool("tech")
        n.cities = try o.value("cities").jsonArray().map { e in
            let c = try e.jsonObject()
            let city = City(try c.str("name"))
            city.shield = try c.int("shield")
            city.research = try c.int("research")
            city.destroyed = try c.bool("destroyed")
            return city
        }
        n.bombify += try o.strings("bombify")
        n.score = try o.int("score")
        n.sanctioned = try o.bool("sanctioned")
        n.wasSanctioned = try o.bool("wasSanctioned")
        n.stillSanctioned = try o.bool("stillSanctioned")
        n.destroyed = try o.bool("destroyed")
        n.attackUs = try o.int("attackUs")
        n.hasAttackedUs = try o.bool("hasAttackedUs")
        n.hasMet = try o.bool("hasMet")
        if let used = o["used"] {
            for (k, v) in try used.jsonObject() {
                n.used[k] = try v.jsonArray().map { Int(try $0.primitive().int()) }
            }
        }
        for flag in try o.strings("done") { n.mark(flag) }
        return n
    }
}

/// One game of Nuclear War (the skill's ad.Session.nuclear and its SkillState), and what it keeps between games.
public final class NuclearState {
    public var q = Q.chooseCountry
    public var countries: [Nation] = []
    public var us: Nation?
    @KotlinInt public var environment = 0
    @KotlinInt public var prevEnvironment = 0
    @KotlinInt public var round = 1
    public var citiesToBomb: [String] = []
    @KotlinInt public var cityIndex = 0
    @KotlinInt public var countryIndex = 0
    /// Who asked to have whom bombed (from, to).
    public var requestToBomb: [(from: String, to: String)] = []
    public var doneLongCall = false
    public var midGame = false
    public var countryToBomb: String?
    @KotlinInt public var cityBombIndex = 0

    // The skill's Settings, kept between games: the first game's tutorial, rundown and city list are said once.
    public var playedNuclear = false
    public var rundown = false
    public var completed = false

    public init() {}

    public func toJSON() -> JSONObject {
        var o = JSONObject()
        o["q"] = .string(q.rawValue)
        o["countries"] = .array(countries.map { .object($0.toJSON()) })
        o["us"] = us.map { JSON.object($0.toJSON()) } ?? .null
        o["environment"] = int(environment)
        o["prevEnvironment"] = int(prevEnvironment)
        o["round"] = int(round)
        o["citiesToBomb"] = strings(citiesToBomb)
        o["cityIndex"] = int(cityIndex)
        o["countryIndex"] = int(countryIndex)
        o["requestToBomb"] = .array(requestToBomb.map { .array([.string($0.from), .string($0.to)]) })
        o["doneLongCall"] = .bool(doneLongCall)
        o["midGame"] = .bool(midGame)
        o["countryToBomb"] = countryToBomb.map(JSON.string) ?? .null
        o["cityBombIndex"] = int(cityBombIndex)
        putSettings(&o)
        return o
    }

    /// [toJSON] as kotlinx writes it (`State.toJson().toString()`): the save's "state".
    public func toJSONString() -> String { JSONWriter.write(.object(toJSON())) }

    public func settingsJSON() -> JSONObject {
        var o = JSONObject()
        putSettings(&o)
        return o
    }

    private func putSettings(_ o: inout JSONObject) {
        o["playedNuclear"] = .bool(playedNuclear)
        o["rundown"] = .bool(rundown)
        o["completed"] = .bool(completed)
    }

    /// Takes the settings kept between games from a saved state (or its settings alone).
    public func takeSettings(_ o: JSONObject) throws {
        playedNuclear = try o.bool("playedNuclear")
        rundown = try o.bool("rundown")
        completed = try o.bool("completed")
    }

    /**
     * A state from its JSON. A missing value takes its default (where Kotlin's reader has one), but a value that's
     * there and isn't what it should be fails, as kotlinx's `int` and `boolean` do.
     */
    public static func fromJSON(_ o: JSONObject) throws -> NuclearState {
        let s = NuclearState()
        let name = try o.str("q")
        guard let q = Q(rawValue: name) else {
            throw PlayError("No enum constant com.epicaudiogames.engine.nuclear.Q.\(name)")
        }
        s.q = q
        s.countries = try o.value("countries").jsonArray().map { try Nation.fromJSON($0.jsonObject()) }
        if let us = o["us"]?.objectValue { s.us = try Nation.fromJSON(us) }
        s.environment = try o.int("environment")
        s.prevEnvironment = try o.int("prevEnvironment")
        s.round = try o.int("round")
        s.citiesToBomb += try o.strings("citiesToBomb")
        s.cityIndex = try o.int("cityIndex")
        s.countryIndex = try o.int("countryIndex")
        for p in try o.value("requestToBomb").jsonArray() {
            let a = try p.jsonArray()
            guard a.count >= 2 else { throw PlayError("Index \(a.count) out of bounds for length \(a.count)") }
            s.requestToBomb.append((try a[0].primitiveContent(), try a[1].primitiveContent()))
        }
        s.doneLongCall = try o.bool("doneLongCall")
        s.midGame = try o.bool("midGame")
        if case .string(let c)? = o["countryToBomb"] { s.countryToBomb = c }
        s.cityBombIndex = try o.int("cityBombIndex")
        try s.takeSettings(o)
        return s
    }
}

// ----- Writing and reading the JSON, as kotlinx's builders and accessors do -----

private func int(_ n: Int) -> JSON { .literal(String(n)) }

private func strings(_ list: [String]) -> JSON { .array(list.map(JSON.string)) }

extension JSON {
    /// `.jsonPrimitive`: the value itself, or a failure for an object or array.
    fileprivate func primitive() throws -> JSON {
        guard isPrimitive else { throw MapError.other("Element class \(kotlinxClass) is not a JsonPrimitive") }
        return self
    }
}

extension LinkedMap where V == JSON {
    /// `getValue(k)`: a missing key fails.
    fileprivate func value(_ k: String) throws -> JSON {
        guard let v = self[k] else { throw PlayError("Key \(k) is missing in the map.") }
        return v
    }

    /// `getValue(k).jsonPrimitive.content`.
    fileprivate func str(_ k: String) throws -> String { try value(k).primitive().content ?? "" }

    /// `(this[k] as? JsonPrimitive)?.int ?: 0`: missing (or not a primitive) is 0; a primitive that isn't an Int fails.
    fileprivate func int(_ k: String) throws -> Int {
        guard let v = self[k], v.isPrimitive else { return 0 }
        return Int(try v.int())
    }

    /// `(this[k] as? JsonPrimitive)?.boolean ?: false`: likewise for true and false.
    fileprivate func bool(_ k: String) throws -> Bool {
        guard let v = self[k], v.isPrimitive else { return false }
        return try v.boolean()
    }

    /// `(this[k] as? JsonArray)?.map { it.jsonPrimitive.content } ?: emptyList()`.
    fileprivate func strings(_ k: String) throws -> [String] {
        guard let list = self[k]?.arrayValue else { return [] }
        return try list.map { try $0.primitiveContent() }
    }
}
