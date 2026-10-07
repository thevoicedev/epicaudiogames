// map-errors.json (README section 9.4): small maps and packs that fail to load (with MapException's message), some
// that load (their map hash), and calls that fail at run time.

import EpicConformance
import EpicEngine
import Testing

@Suite struct MapErrorConfTests {
    @Test func cases() throws {
        var diffs = Diffs()
        var n = 0
        for c in try goldens().readJSON("map-errors.json").fx("cases").fxArray() {
            let name = try c.fx("name").fxString()
            let text = try c.fx("map").fxString()
            let packs = try c.fx("packs").fxArray().map { try $0.fxString() }
            let o = try c.fxObject()
            // What Kotlin did: loaded it (its map hash), threw a MapException (its message), or threw another
            // exception (compared only as failing).
            let ok = try o["ok"]?.fxString()
            let message = o["error"]?.isString == true ? try o.fx("error").fxString() : nil
            let kotlin = ok.map { "loads it (map hash \($0))" } ?? message.map { "MapException: \($0)" } ?? "another exception"
            n += 1
            do {
                let map = try GameMap.parse(text, packs: packs)
                let got = Canon.hash(Canon.Encoder().map(map))
                if ok == nil {
                    diffs.add("\(name): kotlin \(kotlin), swift loads it")
                } else if !same(got, ok!) {
                    diffs.add("\(name): map hash kotlin \(ok!), swift \(got)\n    \(Canon.json(Canon.Encoder().map(map)))")
                }
            } catch let e as MapError where e.kind == .map {
                if let message {
                    if !same(e.message, message) { diffs.add("\(name):\n    kotlin \(message)\n    swift  \(e.message)") }
                } else {
                    diffs.add("\(name): kotlin \(kotlin), swift MapError: \(e.message)")
                }
            } catch {
                if ok != nil || message != nil { diffs.add("\(name): kotlin \(kotlin), swift: \(error)") }
            }
        }
        diffs.report("map-errors.json cases")
        #expect(n > 100)
    }

    @Test func runtime() throws {
        var diffs = Diffs()
        for c in try goldens().readJSON("map-errors.json").fx("runtime").fxArray() {
            let name = try c.fx("name").fxString()
            let want = try c.fx("error").fxString()
            let calls = try c.fx("calls").fxArray()
            let map = try GameMap.parse(c.fx("map").fxString())
            func session() -> Session { Session(map, choose: { _ in 0 }) }
            var s = session()
            for input in calls.dropLast() {
                _ = try call(input, &s, last: nil, newSession: session)
            }
            do {
                _ = try call(calls.last!, &s, last: nil, newSession: session)
                diffs.add("\(name): the last call doesn't fail; kotlin: \(want)")
            } catch let e as MapError where e.kind == .map {
                if !same(e.message, want) { diffs.add("\(name):\n    kotlin \(want)\n    swift  \(e.message)") }
            } catch let e as PlayError {
                if !same(e.message, want) { diffs.add("\(name):\n    kotlin \(want)\n    swift  \(e.message)") }
            } catch {
                diffs.add("\(name): kotlin \(want), swift \(error)")
            }
        }
        diffs.report("map-errors.json runtime")
    }
}
