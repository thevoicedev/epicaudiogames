// No Kotlin counterpart: VoiceOver and the mic (the plan's D8).

import AudioToolbox
import UIKit

/**
 * With VoiceOver on, the game doesn't open the mic by itself after a question: it would hear VoiceOver reading the
 * screen. The player opens it (Magic Tap, or the Talk button), and a short sound says it's listening, as the ring
 * can't be seen.
 */
enum A11y {
    static var voiceOver: Bool { UIAccessibility.isVoiceOverRunning }

    /// The system's "begin recording" sound.
    private static let micOpens: SystemSoundID = 1113

    /// The mic has opened: its sound, with VoiceOver on.
    static func micOpened() {
        if voiceOver { AudioServicesPlaySystemSound(micOpens) }
    }
}
