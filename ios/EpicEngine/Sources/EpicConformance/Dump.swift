// GoldenTest.kt's dump mode (fixtures/engine/README.md, section 11): the lines `eag --dump <spec>` prints.

import EpicEngine

/// The canonical lines for a dump spec, the same as `./gradlew :engine:goldens -Pgoldens.dump=<spec>` writes.
public enum Dump {
    /**
     * `<variant>/walk/<w>`: walk w's walk line and turn lines, as in walks.jsonl; `<variant>/nodes`: each node's
     * canonical text, in map order; `nuclear-war/game/<seed>`: the game line and turn lines, as in games.jsonl.
     */
    public static func lines(_ spec: String, _ goldens: Goldens) throws -> [String] {
        let parts = spec.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        if parts.count == 3 && parts[0] == NuclearWar.id && parts[1] == "game" {
            guard let seed = Int32(parts[2]).map(Int.init) else {
                throw ConformanceError("can't read the seed in \(spec)")
            }
            var lines: [String] = []
            let game = try NuclearPlayer(goldens.nuclearAudio()).game(seed) { lines.append($0) }
            return [NuclearPlayer.gameLine(seed, game)] + lines
        }
        guard goldens.variants.contains(where: { Kt.utf16Equal($0.name, parts[0]) }) else {
            throw ConformanceError("no variant \(parts[0]) in \(spec)")
        }
        let map = try goldens.map(parts[0])
        if parts.count == 2 && parts[1] == "nodes" {
            let encoder = Canon.Encoder()
            return map.nodes.map { Canon.json(encoder.node($0.value)) }
        }
        if parts.count == 3 && parts[1] == "walk", let w = Int32(parts[2]).map(Int.init) {
            var lines = [Canon.json(.object([("walk", .int(w)), ("seed", .int(MapWalker.seed(w)))]))]
            try MapWalker(map, entries: goldens.entries(parts[0])).walk(w) { lines.append($0) }
            return lines
        }
        throw ConformanceError("can't read the dump spec \(spec) (fixtures/engine/README.md, section 11)")
    }
}
