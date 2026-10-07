// expr.json (README section 9.3): every map expression and the hand-written ones, under 4 variable sets; parse errors.

import EpicConformance
import EpicEngine
import Testing

@Suite struct ExprConfTests {
    private struct VarSets {
        var initial: [String: VarStore] = [:]
        var missing = VarStore()
        var mixed = VarStore()
        var numbers = VarStore()
    }

    private func varsets(_ f: JSONObject) throws -> VarSets {
        var out = VarSets()
        for s in try f.fx("varsets").fxArray() {
            let vars = try s.fx("vars").fxVars()
            switch try s.fx("name").fxString() {
            case "initial": out.initial[try s.fx("game").fxString()] = vars
            case "missing": out.missing = vars
            case "mixed": out.mixed = vars
            case "numbers": out.numbers = vars
            case let name: throw ConformanceError("no such var set \(name)")
            }
        }
        return out
    }

    /// [value, test, key] for each var set, as Kotlin's Expr gave them.
    private func check(_ e: Expr, _ sets: [VarStore], _ results: JSON, _ what: String, _ diffs: inout Diffs) throws {
        let rows = try results.fxArray()
        guard rows.count == sets.count else { throw ConformanceError("\(what): \(rows.count) results") }
        for (i, (vars, row)) in zip(sets, rows).enumerated() {
            let r = try row.fxArray()
            let value = e.eval(vars)
            let got = Canon.json(Canon.value(value))
            if !same(got, Canon.reencode(r[0])) {
                diffs.add("\(what), var set \(i): eval kotlin \(Canon.reencode(r[0])), swift \(got)")
            }
            if e.test(vars) != (try r[1].fxBool()) { diffs.add("\(what), var set \(i): test kotlin \(r[1].short)") }
            let key = Expr.key(value)
            if !same(key, try r[2].fxString()) {
                diffs.add("\(what), var set \(i): key kotlin \(r[2].short), swift \(Canon.json(.string(key)))")
            }
        }
    }

    @Test func mapExpressions() throws {
        let f = try goldens().readJSON("expr.json")
        let sets = try varsets(f)
        var diffs = Diffs()
        var n = 0
        for row in try f.fx("exprs").fxArray() {
            let r = try row.fxArray()
            let variant = try r[0].fxString()
            let source = try r[1].fxString()
            let what = "\(variant) \(Canon.json(.string(source)))"
            let e: Expr
            do {
                e = try Expr.parse(source)
            } catch {
                diffs.add("\(what): doesn't parse: \(error)")
                continue
            }
            let names = try r[3].fxArray().map { try $0.fxString() }
            if e.orderedNames != names { diffs.add("\(what): names kotlin \(names), swift \(e.orderedNames)") }
            guard let initial = sets.initial[variant] else { throw ConformanceError("no initial var set for \(variant)") }
            try check(e, [initial, sets.missing, sets.mixed, sets.numbers], r[4], what, &diffs)
            n += 1
        }
        diffs.report("expr.json exprs")
        #expect(n > 500)
    }

    @Test func extraExpressions() throws {
        let f = try goldens().readJSON("expr.json")
        let sets = try varsets(f)
        var diffs = Diffs()
        for row in try f.fx("extra").fxArray() {
            let r = try row.fxArray()
            let source = try r[0].fxString()
            let what = Canon.json(.string(source))
            let e: Expr
            do {
                e = try Expr.parse(source)
            } catch {
                diffs.add("\(what): doesn't parse: \(error)")
                continue
            }
            let names = try r[1].fxArray().map { try $0.fxString() }
            if e.orderedNames != names { diffs.add("\(what): names kotlin \(names), swift \(e.orderedNames)") }
            try check(e, [sets.missing, sets.mixed, sets.numbers], r[2], what, &diffs)
        }
        diffs.report("expr.json extra")
    }

    @Test func parseErrors() throws {
        var diffs = Diffs()
        for row in try goldens().readJSON("expr.json").fx("errors").fxArray() {
            let r = try row.fxArray()
            let source = try r[0].fxString()
            let want = try r[1].fxString()
            do {
                _ = try Expr.parse(source)
                diffs.add("\(Canon.json(.string(source))) parses; kotlin: \(want)")
            } catch let e as MapError where e.kind == .map {
                if !same(e.message, want) { diffs.add("\(Canon.json(.string(source))): kotlin \(want)\n    swift  \(e.message)") }
            } catch {
                diffs.add("\(Canon.json(.string(source))): not a MapError: \(error); kotlin: \(want)")
            }
        }
        diffs.report("expr.json errors")
    }

    /// Each game's initial var set is its fullest variant's map.vars, in order.
    @Test func initialVarSets() throws {
        let g = try goldens()
        let f = try g.readJSON("expr.json")
        for s in try f.fx("varsets").fxArray() where try s.fx("name").fxString() == "initial" {
            let game = try s.fx("game").fxString()
            #expect(Canon.json(Canon.vars(try g.map(game).vars)) == Canon.reencode(try s.fx("vars")), "\(game)")
        }
    }
}
