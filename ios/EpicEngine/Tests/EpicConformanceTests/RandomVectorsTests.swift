// random.json (README section 9.1): Kotlin's Random(seed), XorWow, draw for draw, and shuffled(Random(seed)).

import EpicConformance
import EpicEngine
import Testing

@Suite struct RandomVectorsTests {
    /// Each vector's calls, made on a fresh XorWowRandom(seed), give Kotlin's results.
    @Test func vectors() throws {
        let file = try goldens().readJSON("random.json")
        var diffs = Diffs()
        var draws = 0
        for vector in try file.fx("vectors").fxArray() {
            let seed = try vector.fx("seed").fxInt()
            let r = LoggingRandom(XorWowRandom(seed: Int32(seed)))
            for (i, d) in try vector.fx("draws").fxArray().enumerated() {
                let want = try Draw(d)
                switch want {
                case .nextInt: _ = try r.nextInt()
                case .nextIntUntil(let until, _): _ = try r.nextInt(until: until)
                case .nextIntFrom(let from, let until, _): _ = try r.nextInt(from: from, until: until)
                case .nextBits(let n, _): _ = try r.nextBits(n)
                case .nextDouble: _ = try r.nextDouble()
                case .nextBoolean: _ = try r.nextBoolean()
                }
                let got = r.take()
                draws += 1
                if got != [want] { diffs.add("seed \(seed), draw \(i): kotlin \(want), swift \(got)") }
            }
        }
        diffs.report("random.json vectors")
        #expect(draws > 1000)
    }

    @Test func shuffles() throws {
        let file = try goldens().readJSON("random.json")
        var diffs = Diffs()
        for s in try file.fx("shuffles").fxArray() {
            let seed = try s.fx("seed").fxInt()
            let size = try s.fx("size").fxInt()
            let want = try s.fx("result").fxArray().map { try $0.fxInt() }
            let got = try Array(0..<size).kShuffled(XorWowRandom(seed: Int32(seed)))
            if got != want { diffs.add("seed \(seed), size \(size): kotlin \(want), swift \(got)") }
        }
        diffs.report("random.json shuffles")
    }

    /// ReplayRandom gives the logged results back, and fails at the first call that differs, naming the draw.
    @Test func replayFailsAtTheFirstDifference() throws {
        let r = ReplayRandom([.nextIntUntil(until: 5, 3), .nextDouble(0.25)])
        #expect(try r.nextInt(until: 5) == 3)
        do {
            _ = try r.nextInt(until: 4)
            Issue.record("a different bound was taken")
        } catch let e as ConformanceError {
            #expect(e.message.hasPrefix("draw 1: the game called nextInt(4)"))
        }
        #expect(try r.nextDouble() == 0.25)
        try r.finish()
        #expect(throws: ConformanceError.self) { try r.nextBoolean() }

        let c = ReplayChooser()
        try c.load(JSONParser.parse("[[3,2],[6,5]]"))
        #expect(try c(3) == 2)
        #expect(throws: ConformanceError.self) { try c(5) }
        #expect(throws: ConformanceError.self) { try c.finish() }
    }
}
