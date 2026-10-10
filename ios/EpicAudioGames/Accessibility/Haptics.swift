// Haptics.kt: the ticks that go with the app's sounds.

import UIKit

/**
 * The ticks that go with the app's sounds (docs/DESIGN.md › Sounds, haptics and the microphone): a firm one as the
 * microphone opens, a soft one as it closes (Settings › Vibrate when listening starts), and the system's success when
 * a pack installs. For a player who can't hear the listening sounds, they're the cue. The game's audio session lets
 * them through while the mic records (AudioSessionController.setUp); a phone that can't tap (an iPad, some iPods) just
 * stays still, as does one with System Haptics off. Android's Haptics.kt.
 */
enum Haptics {
    /// The microphone opening: a firm tick (Android's EFFECT_TICK).
    static func micOpened() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }

    /// The microphone closing: a soft tick, told apart from the opening one as the sounds are (Android's LOW_TICK).
    static func micClosed() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    /// A pack installed: the system's success (Android's DOUBLE_CLICK).
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
