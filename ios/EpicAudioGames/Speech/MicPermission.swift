// GameScreen.kt's RECORD_AUDIO request (lines 92-101): the mic, and on iOS speech recognition too.

import AVFoundation
import Speech

/**
 * Whether the games may listen: iOS asks for the mic and for speech recognition separately, and both are needed.
 * The system asks each once; after a "no" its answer stays no until the player changes it in Settings, which the mic
 * button then leads to (Android asks twice, then the same).
 */
enum MicPermission {
    /// Both allowed.
    static var granted: Bool {
        AVAudioApplication.shared.recordPermission == .granted && SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    /**
     * Asking can still allow both: neither has been refused, and one hasn't been asked yet (a dialog shows). Else
     * only Settings can allow them. fixed: the mic refused at the first ask left speech recognition unasked, so this
     * said yes, and the mic button asked again with no dialog, doing nothing.
     */
    static var canAsk: Bool {
        let mic = AVAudioApplication.shared.recordPermission
        let speech = SFSpeechRecognizer.authorizationStatus()
        guard mic != .denied, speech != .denied, speech != .restricted else { return false }
        return mic == .undetermined || speech == .notDetermined
    }

    /// Asks for whichever hasn't been answered yet (a dialog each), then whether both are allowed.
    static func request() async -> Bool {
        guard await AVAudioApplication.requestRecordPermission() else { return false }
        return await speech() == .authorized
    }

    /// The speech recognition dialog. Its answer comes on another thread: the handler is made here, nonisolated.
    nonisolated private static func speech() async -> SFSpeechRecognizerAuthorizationStatus {
        let status = SFSpeechRecognizer.authorizationStatus()
        guard status == .notDetermined else { return status }
        return await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
    }
}
