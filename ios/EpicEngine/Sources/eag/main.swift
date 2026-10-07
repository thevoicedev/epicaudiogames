// Cli.kt: play a game by typing, with the same output as `gradlew :engine:run`.

import EpicConformance
import EpicEngine
import Foundation

/*
 * Play a game by typing: `swift run -q --package-path ios/EpicEngine eag noodle-rush` (from the repo root).
 * Every line the game says is printed as it would be shown in the app. Type an answer; an empty line is silence.
 * Commands: /vars (the variables), /restart, /quit.
 *
 * Options Cli.kt doesn't have:
 *   --choose first|seed:N   random gos, picks and rands always take the first option, or come from Kotlin's
 *                           Random(N), so a run can be compared with the Kotlin engine's (default: random);
 *                           Nuclear War takes seed:N only, as its Random;
 *   --packs                 the game with its packs (games/<id>/packs/<pack>.json, in the catalog's order);
 *   --check-content <dir>   checks that every clip the free maps and Nuclear War play, and every game's cover, is
 *                           in <dir> (content/), with the exact case: <game>/<path>.m4a, .mp3 or .opus (a pack's
 *                           own clips are in its zip, not content/);
 *   --dump <spec>           prints a golden walk's lines, a map's node canon or a Nuclear War game's lines, as
 *                           `gradlew :engine:goldens -Pgoldens.dump=<spec>` writes them (fixtures/engine/README.md,
 *                           section 11), to compare the two with diff.
 */

/// What the command line asked for.
struct Options {
    var name: String?
    var choose: String?
    var packs = false
    var checkContent: String?
    var dump: String?
    /// --nuclear-lines: the file to write Nuclear War's lines to.
    var nuclearLines: String?
}

func parseOptions(_ args: [String]) -> Options? {
    var o = Options()
    var i = 0
    while i < args.count {
        let a = args[i]
        switch a {
        case "--choose", "--check-content", "--dump":
            guard i + 1 < args.count else { return nil }
            if a == "--choose" { o.choose = args[i + 1] }
            if a == "--check-content" { o.checkContent = args[i + 1] }
            if a == "--dump" { o.dump = args[i + 1] }
            i += 1
        case "--packs":
            o.packs = true
        case "--nuclear-lines":
            // As Cli.kt: the next argument, else games/nuclear-war/lines.json.
            guard i == 0 else { return nil }
            o.nuclearLines = i + 1 < args.count ? args[i + 1] : "games/nuclear-war/lines.json"
            i = args.count
        default:
            // Cli.kt reads only the first argument: the rest are ignored.
            if o.name == nil { o.name = a }
        }
        i += 1
    }
    return o
}

/// Cli.kt's usage line, and with [eagOptions] a second line for the options only eag has.
func usage(eagOptions: Bool = true) {
    print("Usage: run --args=\"<game id or path to map.json>\"  or  --args=\"--nuclear-lines <file>\"")
    if !eagOptions { return }
    print("       eag <game id or path to map.json> [--packs] [--choose first|seed:N]  or  eag --check-content <dir>"
        + "  or  eag --dump <spec>")
}

/// java.io.File's getPath() on Unix: runs of "/" made one, and no "/" at the end (Cli.kt prints a File).
func javaFilePath(_ path: String) -> String {
    var out = ""
    for c in path where !(c == "/" && out.hasSuffix("/")) { out.append(c) }
    if out.count > 1 && out.hasSuffix("/") { out.removeLast() }
    return out
}

func fail(_ message: String) -> Int32 {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    return 1
}

func isFile(_ path: String) -> Bool {
    var dir: ObjCBool = false
    return FileManager.default.fileExists(atPath: path, isDirectory: &dir) && !dir.boolValue
}

/// The repo (the folder with games/catalog.json): EPIC_REPO_ROOT, or up from here, or up from this source file.
func repoRoot() -> URL? {
    if let env = ProcessInfo.processInfo.environment["EPIC_REPO_ROOT"], !env.isEmpty {
        return URL(fileURLWithPath: env)
    }
    for start in [FileManager.default.currentDirectoryPath, #filePath] {
        var dir = URL(fileURLWithPath: start).resolvingSymlinksInPath()
        while dir.path != "/" {
            if isFile(dir.appendingPathComponent("games/catalog.json").path) { return dir }
            dir.deleteLastPathComponent()
        }
    }
    return nil
}

/// The games folder's catalog: each game's id and its packs' ids, in order.
func catalog(_ games: URL) throws -> [(id: String, packs: [String])] {
    let root = try JSONParser.parse(Data(contentsOf: games.appendingPathComponent("catalog.json")))
    return (root["games"]?.arrayValue ?? []).compactMap { g in
        guard let id = g["id"]?.content else { return nil }
        return (id, (g["packs"]?.arrayValue ?? []).compactMap { $0["id"]?.content })
    }
}

/// A game's pack files, in the catalog's order (the ones that are there).
func packFiles(_ map: URL, gameId: String) -> [URL] {
    let gameDir = map.deletingLastPathComponent()
    let games = gameDir.deletingLastPathComponent()
    let ids = (try? catalog(games))?.first { $0.id == gameId }?.packs ?? []
    return ids.map { gameDir.appendingPathComponent("packs/\($0).json") }.filter { isFile($0.path) }
}

func chooser(_ spec: String?) -> ((Int) throws -> Int)? {
    guard let spec else { return Session.randomChooser() }
    if spec == "first" { return { _ in 0 } }
    if spec.hasPrefix("seed:"), let seed = Int64(spec.dropFirst(5)) {
        let random = Int32(exactly: seed).map { XorWowRandom(seed: $0) } ?? XorWowRandom(longSeed: seed)
        return { n in try random.nextInt(until: n) }
    }
    return nil
}

/// Nuclear War's Random: from the system, or Kotlin's Random(N) for --choose seed:N.
func nuclearRandom(_ spec: String?) -> (any KotlinRandom)? {
    guard let spec else { return XorWowRandom() }
    guard spec.hasPrefix("seed:"), let seed = Int64(spec.dropFirst(5)) else { return nil }
    return Int32(exactly: seed).map { XorWowRandom(seed: $0) } ?? XorWowRandom(longSeed: seed)
}

func prompt() -> String? {
    print("> ", terminator: "")
    fflush(nil)
    return readLine(strippingNewline: true).map(Kt.trim)
}

/// A turn's lines as the app shows them: a line that carries on joins the one before.
func show(_ who: LinkedMap<String>, _ turn: Turn) {
    var carry: String?
    for step in turn.steps {
        switch step {
        case .play(let clip):
            for line in clip.lines {
                let text = carry.map { "\($0) \(line.text)" } ?? "\(who[line.who] ?? line.who): \(line.text)"
                if line.more {
                    carry = text
                } else {
                    print(text)
                    carry = nil
                }
            }
        case .num(let variable):
            print("   [\(variable)]")
        case .bed(let path?, _, _):
            print("   (\(path.split(separator: "/", omittingEmptySubsequences: false).last!) plays underneath)")
        default:
            break
        }
    }
    if let carry { print(carry) }
    let buttons = turn.ask?.buttons ?? []
    if !buttons.isEmpty { print("   " + buttons.map { "[\($0.label)]" }.joined(separator: "  ")) }
}

/// Plays until the player quits or the input ends.
func play(_ name: String, _ game: Play, vars: () -> String) throws {
    print("== \(name) ==  (type your answers; an empty line is silence; /vars, /restart, /quit)")
    var turn = try game.start()
    while true {
        show(game.who, turn)
        if turn.quit {
            print("[you left the game]")
            return
        }
        if let end = turn.end {
            let next = end.next
            let canNext = end.kind == "chapter" && next != nil && game.hasChapter(next!)
            let hint: String
            if canNext {
                hint = "  type next for the next chapter, again to start over, or /quit"
            } else if let locked = end.locked {
                hint = "  (the next part is in the pack \"\(locked)\")  type again to start over, or /quit"
            } else {
                hint = "  type again to start over, or /quit"
            }
            print("[THE END: \(end.title)]" + hint)
            guard let line = prompt() else { return }
            if line == "/quit" { return }
            if line == "next" && canNext {
                turn = try game.nextChapter()
            } else if end.kind == "gameover", let retry = end.retry {
                turn = try game.restart(at: retry)
            } else {
                turn = try game.restart()
            }
            continue
        }
        guard let line = prompt() else { return }
        switch line {
        case "/quit":
            return
        case "/vars":
            print("   \(vars())")
            continue
        case "/restart":
            turn = try game.restart()
        case "":
            turn = try game.silence()
        default:
            if AppCommands.isPause(line) {
                print("[paused: press Enter to carry on]")
                guard prompt() != nil else { return }
                turn = try game.silence()
                continue
            }
            turn = try game.answer(line)
        }
        if let heard = turn.heard { print("   (heard: \(heard.how))") }
    }
}

// ----- --nuclear-lines -----

/**
 * Cli.kt's --nuclear-lines: every line of Nuclear War's announcer (Lines.all()), for tools/games/nuclearwar.py, as
 * kotlinx writes the list, with one object per line: "speak" only where it differs from "text", "before" and "after"
 * only where they aren't empty.
 */
func writeNuclearLines(_ path: String) throws -> Int32 {
    let lines = try Lines.all().map { p -> JSON in
        var o = JSONObject()
        o["text"] = .string(p.text)
        if !Kt.utf16Equal(p.speak, p.text) { o["speak"] = .string(p.speak) }
        if !p.before.isEmpty { o["before"] = .string(p.before) }
        if !p.after.isEmpty { o["after"] = .string(p.after) }
        return .object(o)
    }
    let text = JSONWriter.write(.array(lines)).replacingOccurrences(of: "},{", with: "},\n{", options: .literal) + "\n"
    let file = URL(fileURLWithPath: path)
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: file)
    print("\(lines.count) lines -> \(javaFilePath(path))")
    return 0
}

// ----- --check-content -----

/// Every clip path the steps can play (play and bed), whatever the variables.
func clipPaths(_ steps: [Step], into out: inout [String]) {
    for s in steps {
        switch s {
        case .play(let clip): out.append(clip.path)
        case .bed(let path?, _, _): out.append(path)
        case .when(_, let inner): clipPaths(inner, into: &out)
        case .pick(let options): for o in options { clipPaths(o, into: &out) }
        case .by(_, let cases, let otherwise):
            for (_, c) in cases { clipPaths(c, into: &out) }
            clipPaths(otherwise, into: &out)
        default: break
        }
    }
}

func clipPaths(_ map: GameMap) -> [String] {
    var out: [String] = []
    for (_, n) in map.nodes {
        clipPaths(n.say, into: &out)
        if let ask = n.ask {
            clipPaths(ask.reprompt, into: &out)
            if let e = ask.otherwise { clipPaths(e.say, into: &out) }
        }
    }
    return out
}

func checkContent(_ dir: String) throws -> Int32 {
    guard let root = repoRoot() else { return fail("can't find the repo (games/catalog.json); set EPIC_REPO_ROOT") }
    let games = root.appendingPathComponent("games")
    let content = URL(fileURLWithPath: dir)
    var listings: [String: Set<String>] = [:]
    // Exact case, as on a device: the folder's listing must have the name.
    func exists(_ path: String) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        let folder = parts.dropLast().joined(separator: "/")
        if listings[folder] == nil {
            let url = folder.isEmpty ? content : content.appendingPathComponent(folder)
            listings[folder] = Set((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? [])
        }
        return listings[folder]!.contains(parts.last!)
    }
    func clip(_ path: String) -> Bool { [".m4a", ".mp3", ".opus"].contains { exists(path + $0) } }
    var missing: [String] = []
    var checked = 0
    var packOnly = 0
    func check(_ path: String, _ found: Bool) {
        checked += 1
        if !found { missing.append(path) }
    }
    for game in try catalog(games) {
        if game.id == "nuclear-war" {
            let clips = try JSONParser.parse(Data(contentsOf: games.appendingPathComponent("nuclear-war/clips.json")))
            for key in ["voice", "clips", "mixes"] {
                for (_, v) in clips[key]?.objectValue ?? JSONObject() {
                    if let p = v["play"]?.content { check("nuclear-war/\(p)", clip("nuclear-war/\(p)")) }
                }
            }
        } else {
            // content/<id>/ has what the free map plays (tools/prune.py); a pack's own clips are in its zip
            // (tools/make_pack.py), so they're counted, not checked.
            let mapFile = games.appendingPathComponent("\(game.id)/map.json")
            let free = clipPaths(try GameMap.load(mapFile)).uniqued()
            for p in free { check("\(game.id)/\(p)", clip("\(game.id)/\(p)")) }
            let packs = game.packs.map { games.appendingPathComponent("\(game.id)/packs/\($0).json") }
                .filter { isFile($0.path) }
            if !packs.isEmpty {
                let inFree = Set(free)
                packOnly += clipPaths(try GameMap.load(mapFile, packs: packs)).uniqued().filter { !inFree.contains($0) }.count
            }
        }
        check("\(game.id)/cover.jpg", exists("\(game.id)/cover.jpg"))
    }
    for m in missing { print("missing: \(m)") }
    print("\(missing.count) unresolved of \(checked) paths in \(dir) (\(packOnly) more are packs' own, in their zips)")
    return missing.isEmpty ? 0 : 1
}

// ----- main -----

func run(_ args: [String]) -> Int32 {
    guard let options = parseOptions(args) else {
        usage()
        return 2
    }
    do {
        if let dir = options.checkContent { return try checkContent(dir) }
        if let spec = options.dump {
            for line in try Dump.lines(spec, Goldens(root: Repo.root(from: #filePath))) { print(line) }
            return 0
        }
        if let file = options.nuclearLines { return try writeNuclearLines(file) }
        guard let name = options.name else {
            // With no arguments, Cli.kt's one line.
            usage(eagOptions: !args.isEmpty)
            return 0
        }
        if name == NuclearWar.id {
            guard let random = nuclearRandom(options.choose) else {
                usage()
                return 2
            }
            // As Cli.kt: games/nuclear-war/clips.json from here (then from the repo), else every clip a placeholder.
            var clips = URL(fileURLWithPath: "games/\(NuclearWar.id)/clips.json")
            if !isFile(clips.path), let root = repoRoot() {
                clips = root.appendingPathComponent("games/\(NuclearWar.id)/clips.json")
            }
            let audio = isFile(clips.path) ? try NuclearAudio.load(clips) : NuclearAudio.placeholder()
            let game = NuclearWar(audio: audio, random: random)
            try play(name, game, vars: { game.save().vars["state"]?.kotlinString ?? "" })
            return 0
        }
        guard let choose = chooser(options.choose) else {
            usage()
            return 2
        }
        // As Cli.kt: the path given, else games/<name>/map.json from here; then from the repo, wherever eag runs.
        var file = isFile(name) ? URL(fileURLWithPath: name) : URL(fileURLWithPath: "games/\(name)/map.json")
        if !isFile(file.path), let root = repoRoot(), isFile(root.appendingPathComponent("games/\(name)/map.json").path) {
            file = root.appendingPathComponent("games/\(name)/map.json")
        }
        if !isFile(file.path) {
            print("No map at \(javaFilePath("games/\(name)/map.json"))")
            return 0
        }
        var map = try GameMap.load(file)
        if options.packs { map = try GameMap.load(file, packs: packFiles(file, gameId: map.id)) }
        let session = Session(map, choose: choose)
        try play(name, session, vars: { session.vars.kotlinDescription })
        return 0
    } catch {
        fflush(nil)
        return fail("error: \(error)")
    }
}

let status = run(Array(CommandLine.arguments.dropFirst()))
fflush(nil)
exit(status)
