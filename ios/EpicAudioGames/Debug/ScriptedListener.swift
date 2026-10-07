// No Kotlin counterpart: a listener that hears what a UI test tells it to (Debug builds, -EpicHear).

#if DEBUG
import EpicAppCore
import Foundation

/**
 * Hears a script instead of the mic, one entry each time the game listens: a word or words are heard (after a moment
 * showing as the partial result, with the level up); "~" is a silence; "?" is speech it couldn't make out. Once the
 * script runs out, it listens and hears nothing. The mic counts as allowed, with no permission asked.
 */
final class ScriptedListener: Listening {
    var events = ListenerEvents()
    var isAvailable: Bool { true }
    private var script: [String]
    private var session = 0

    init(_ script: [String]) {
        self.script = script
    }

    func start(hints: [String]) {
        session += 1
        let id = session
        guard !script.isEmpty else { return }
        let next = script.removeFirst()
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            guard let self, self.session == id else { return }
            switch next {
            case "~":
                self.events.silence()
            case "?":
                self.events.heard([])
            default:
                self.events.level(0.6)
                self.events.partial(next)
                try? await Task.sleep(for: .milliseconds(2000))
                guard self.session == id else { return }
                self.events.heard([next])
            }
        }
    }

    func stop() { session += 1 }

    func release() { session += 1 }
}
#endif
