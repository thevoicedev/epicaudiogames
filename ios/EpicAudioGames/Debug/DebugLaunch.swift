// No Kotlin counterpart: launch arguments (Debug builds) that drive the app, for screenshots and checks.

#if DEBUG
import EpicAppCore
import Foundation

/**
 * Plays the app without touching it, from its launch arguments (they arrive as UserDefaults):
 * - `-EpicReset YES`: every game's save is cleared, so the list shows no CONTINUE (the UI tests start so);
 * - `-EpicFresh YES`: the game's save is cleared first;
 * - `-EpicOpen <game id>`: opens the game;
 * - `-EpicSay "yes|no|fight"`: answers each question in turn with these, once the game waits; a last answer
 *   ending in "*" ("yes*") is given again and again, until the game ends;
 * - `-EpicSkip YES`: skips each turn's voice as soon as it plays;
 * - `-EpicPauseAt <seconds>`: pauses the game that long after it opens;
 * - `-EpicStore <game id>`: opens that game's store sheet;
 * - `-EpicLab YES`: opens the Audio Lab (RootView);
 * - `-EpicMic off`: the games don't listen (as on a phone with no recogniser: no mic, no permission asked);
 * - `-EpicHear "~|yes|?"`: the games hear these instead of the mic (ScriptedListener), the mic counting as allowed;
 * - `-EpicPacksURL <url>`: the pack server, in place of the build's.
 *
 * `xcrun simctl launch booted com.epicaudiogames.app -EpicOpen noodle-rush -EpicSkip YES -EpicSay "yes|yes"`.
 */
enum DebugLaunch {
    /// How the games listen, if the launch says (-EpicMic off, -EpicHear).
    static var hearing: AppModel.Hearing? {
        let defaults = UserDefaults.standard
        if let script = defaults.string(forKey: "EpicHear") {
            return .script(script.split(separator: "|", omittingEmptySubsequences: false).map(String.init))
        }
        if defaults.string(forKey: "EpicMic") == "off" { return AppModel.Hearing.none }
        return nil
    }

    /// The pack server, if the launch names one (-EpicPacksURL).
    static var packsURL: String? { UserDefaults.standard.string(forKey: "EpicPacksURL") }

    static func run(_ model: AppModel) async {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "EpicReset") {
            for game in model.games { model.saves.clear(game.id) }
            model.home()
        }
        if let id = defaults.string(forKey: "EpicStore"), let game = model.games.first(where: { $0.id == id }) {
            model.showStore(game)
        }
        guard let id = defaults.string(forKey: "EpicOpen"), let info = model.games.first(where: { $0.id == id })
        else { return }
        if defaults.bool(forKey: "EpicFresh") { model.saves.clear(id) }
        model.open(info)
        let answers = (defaults.string(forKey: "EpicSay") ?? "").split(separator: "|").map(String.init)
        let skip = defaults.bool(forKey: "EpicSkip")
        let pauseAt = defaults.double(forKey: "EpicPauseAt")
        let opened = Date()
        var next = 0
        var paused = false
        while !Task.isCancelled && Date().timeIntervalSince(opened) < 600 {
            try? await Task.sleep(for: .milliseconds(250))
            guard let game = model.game else { continue }
            if pauseAt > 0 && !paused && Date().timeIntervalSince(opened) >= pauseAt {
                paused = true
                game.pause()
            }
            if game.paused { continue }
            if skip && game.speaking { game.skip() }
            if !game.speaking && game.ask != nil && next < answers.count {
                let answer = answers[next]
                if answer.hasSuffix("*") && next == answers.count - 1 {
                    game.answer(String(answer.dropLast()))
                } else {
                    game.answer(answer)
                    next += 1
                }
            }
            if game.end != nil && answers.last?.hasSuffix("*") == true { next = answers.count }
            if next >= answers.count && !game.speaking && (pauseAt <= 0 || paused) { return }
        }
    }
}
#endif
