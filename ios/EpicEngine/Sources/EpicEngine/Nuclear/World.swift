// nuclear/World.kt (lines 1-87): the five countries, the prices and the money as Alexa said it.

/**
 * A country as the skill's COUNTRY_MAP has it: [voice] is how its name is said ("the UK"), [leader] the leader's name
 * as shown and [leaderSays] as Don says it, [who] the leader's speaker key in the transcript, [cities] in the skill's
 * order.
 */
public struct Land: Equatable, Sendable {
    public let ref: String
    public let voice: String
    public let leader: String
    public let leaderSays: String
    public let who: String
    public let cities: [String]

    public init(
        _ ref: String, _ voice: String, _ leader: String, _ leaderSays: String, _ who: String, _ cities: [String]
    ) {
        self.ref = ref
        self.voice = voice
        self.leader = leader
        self.leaderSays = leaderSays
        self.who = who
        self.cities = cities
    }
}

/// The five countries, the prices and the money as Alexa said it (Constants.js: COUNTRY_MAP, NW_ROUNDS).
public enum World {
    public static let lands: [Land] = [
        Land("France", "France", "Alex Craimant", "Alex Cremonne", "FR", ["Paris", "Marseille", "Lyon"]),
        Land("USA", "the USA", "Iona Butt", "Iona Butt", "US", ["New York", "Los Angeles", "Houston"]),
        Land("UK", "the UK", "Roger Shufflebottom", "Roger Shufflebottom", "UK", ["London", "Edinburgh", "Cardiff"]),
        Land("China", "China", "Hoo Flung Dung", "Hoo Flung Dung", "CN", ["Shanghai", "Beijing", "Wuhan"]),
        Land("Russia", "Russia", "Yuri Poo-tin", "Yuri Poo-tin", "RU", ["Moscow", "St Petersburg", "Sochi"]),
    ]
    public static let refs = lands.map(\.ref)
    public static let cities = lands.flatMap(\.cities)

    /// A country by its ref; Kotlin's `first { }` fails (NoSuchElementException) when there's none.
    public static func land(_ ref: String) throws -> Land {
        guard let l = lands.first(where: { $0.ref.kEquals(ref) }) else { throw noSuchElement }
        return l
    }

    public static func landOf(_ city: String) throws -> Land {
        guard let l = lands.first(where: { $0.cities.kContains(city) }) else { throw noSuchElement }
        return l
    }

    public static func voice(_ ref: String) throws -> String { try land(ref).voice }

    /// Countries in the skill's COUNTRY_MAP order, the order lists of them are said in.
    public static func ordered<C: Collection<String>>(_ refs: C) -> [String] { Self.refs.filter { refs.kContains($0) } }

    /// A country's cities in that order.
    public static func orderedCities<C: Collection<String>>(_ names: C) -> [String] {
        cities.filter { names.kContains($0) }
    }

    static var noSuchElement: PlayError { PlayError("Collection contains no element matching the predicate.") }

    public static let research: Int64 = 2_000_000
    public static let shield: Int64 = 3_000_000
    public static let environment: Int64 = 1_000_000
    public static let tech: Int64 = 5_000_000
    public static let bomb: Int64 = 3_000_000

    /// Money with a clip of its own: every 100,000 up to 40 million, then every half million up to 150 million.
    public static let moneyFine: Int64 = 40_000_000
    public static let moneyMax: Int64 = 150_000_000

    /// The amount said for this much money: the nearest with a clip.
    public static func sayable(_ money: Int64) -> Int64 {
        let m = Swift.min(Swift.max(money, 0), moneyMax)
        let tenth = (m + 50_000) / 100_000 * 100_000
        return tenth <= moneyFine || tenth % 500_000 == 0 ? tenth : (m + 250_000) / 500_000 * 500_000
    }

    /// All the amounts [sayable] gives.
    public static func sayableAmounts() -> [Int64] {
        Array(stride(from: 0, through: moneyFine, by: 100_000))
            + Array(stride(from: moneyFine + 500_000, through: moneyMax, by: 500_000))
    }

    /**
     * The skill's formatMillions: "12 million", "12 and a half million", "12.4 million", "half a million"; under half a
     * million, the number itself ("300,000").
     */
    public static func formatMillions(_ num: Int64) -> String {
        if num < 500_000 { return num == 0 ? "0" : grouped(num) }
        let millions = num / 1_000_000
        let remaining = num % 1_000_000
        if millions == 0 && remaining == 500_000 { return "half a million" }
        if remaining == 500_000 { return "\(millions) and a half million" }
        if remaining > 0 { return "\(millions).\(remaining / 100_000) million" }
        return "\(millions) million"
    }

    /// Java's `String.format(Locale.US, "%,d", n)`: digits in threes, with commas.
    private static func grouped(_ n: Int64) -> String {
        let digits = Array(String(n.magnitude))
        var out = ""
        for (i, d) in digits.enumerated() {
            if i > 0 && (digits.count - i) % 3 == 0 { out.append(",") }
            out.append(d)
        }
        return n < 0 ? "-" + out : out
    }

    /// "first" to "fifth".
    public static func ordinal(_ n: Int) -> String {
        let words = ["first", "second", "third", "fourth", "fifth"]
        return words.indices.contains(n - 1) ? words[n - 1] : "\(n)th"
    }

    /// Points with a clip of their own (a game's score stays well under this).
    public static let pointsMax = 200

    /// Bombs with lines of their own.
    public static let bombsMax = 25

    /// The environment said in steps of 5 percent, up to this.
    public static let percentMax = 300
}
