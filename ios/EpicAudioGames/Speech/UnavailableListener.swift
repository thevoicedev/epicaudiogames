// Listener.kt's onUnavailable: a phone with no recogniser (Debug's -EpicMic off, and tests): answers are typed or tapped.

import EpicAppCore
import Foundation

/**
 * A listener with no speech recogniser behind it: it says so whenever it's asked to listen, as Listener.kt does when
 * there's no recogniser for the language. The mic shows as off; typing and the answer chips work as ever.
 */
final class UnavailableListener: Listening {
    var events = ListenerEvents()
    var isAvailable: Bool { false }
    private var active = false

    func start(hints: [String]) {
        active = true
        // Reported later, as the recogniser's errors are, and not once listening has been stopped.
        Task { @MainActor [weak self] in
            guard let self, self.active else { return }
            self.active = false
            self.events.unavailable()
        }
    }

    func stop() {
        active = false
    }

    func release() {
        active = false
    }
}
