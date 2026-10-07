// No Kotlin counterpart: the game playing and listening with the phone locked, through the headphones' mic.

import AVFoundation
import Speech
import Testing
@testable import EpicAudioGames

@MainActor
struct BackgroundAudioTests {
    /// The app keeps playing in the background (the phone locked): UIBackgroundModes has "audio".
    @Test func theAppPlaysInTheBackground() {
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]
        #expect(modes?.contains("audio") == true)
    }

    /// The session lets Bluetooth headsets be heard through and listened with (HFP, and from iOS 26 high-quality
    /// recording), keeps A2DP headphones, and plays to the speaker rather than the earpiece.
    @Test func theSessionListensThroughHeadsets() {
        let options = AudioSessionController.options
        #expect(options.contains(.allowBluetoothHFP))
        #expect(options.contains(.allowBluetoothA2DP))
        #expect(options.contains(.defaultToSpeaker))
        #expect(!options.contains(.mixWithOthers))
        if #available(iOS 26.0, *) {
            #expect(options.contains(.bluetoothHighQualityRecording))
        }
    }

    /// A headset's mic is preferred to the iPhone's; with none, the iPhone's.
    @Test func theHeadsetsMicIsPreferred() {
        #expect(AudioSessionController.preferredInput([.builtInMic, .bluetoothHFP]) == 1)
        #expect(AudioSessionController.preferredInput([.builtInMic, .headsetMic]) == 1)
        #expect(AudioSessionController.preferredInput([.usbAudio, .builtInMic]) == 0)
        #expect(AudioSessionController.preferredInput([.builtInMic]) == 0)
        #expect(AudioSessionController.preferredInput([.lineIn]) == nil)
        #expect(AudioSessionController.preferredInput([]) == nil)
    }

    /// The mic, on for the whole game, feeds only the answer being listened for: a later answer's feed isn't taken
    /// away by an earlier one ending.
    @Test func theMicFeedsOnlyTheAnswerListenedFor() {
        let mic = MicInput()
        let first = SFSpeechAudioBufferRecognitionRequest()
        let second = SFSpeechAudioBufferRecognitionRequest()
        #expect(!mic.isFeeding)
        mic.feed(first) { _ in }
        #expect(mic.isFeeding)
        mic.feed(second) { _ in }
        mic.unfeed(first)
        #expect(mic.isFeeding, "an earlier answer stopped the later one's feed")
        mic.unfeed(second)
        #expect(!mic.isFeeding)
        #expect(!mic.isWanted)
        mic.stop()
        #expect(!mic.isRunning)
    }
}
