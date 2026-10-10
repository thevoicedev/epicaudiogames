// No Kotlin counterpart: a launch argument (Debug builds) that shows the watch app in a game without an iPhone, for
// screenshots and checks (docs/WATCH.md). The iPhone app's are Debug/DebugLaunch.swift's.

#if DEBUG
import Foundation

/**
 * `-EpicWatchDemo <speaking|turn|listening|paused|wait|refused|end|none>`: the watch app shows Noodle Rush in that
 * state, worded as the iPhone sends it (WatchBridge.swift's state(of:)), and doesn't start its session, so no iPhone
 * changes it. `xcrun simctl launch <watch> com.epicaudiogames.app.watchkitapp -EpicWatchDemo listening`.
 */
enum WatchDemo {
    /// The state the launch asks for, if any.
    static var chosen: WatchState? {
        UserDefaults.standard.string(forKey: "EpicWatchDemo").flatMap { state($0) }
    }

    static func state(_ name: String) -> WatchState? {
        let title = "Noodle Rush"
        switch name {
        case "speaking":
            return WatchState(
                title: title, state: "Speaking", action: .skip, label: "Skip", enabled: true, listening: false,
                canPause: true)
        case "turn":
            return WatchState(
                title: title, state: "Your turn", action: .talk, label: "Talk", enabled: true, listening: false,
                canPause: true)
        case "listening":
            return WatchState(
                title: title, state: "Listening…", action: .stopListening, label: "Stop listening", enabled: true,
                listening: true, canPause: true)
        case "paused":
            return WatchState(
                title: title, state: "Paused", action: .carryOn, label: "Carry on", enabled: true, listening: false,
                canPause: false)
        case "wait":
            return WatchState(
                title: title, state: "Wait for the question", action: .wait, label: "Talk", enabled: false,
                listening: false, canPause: true)
        case "refused":
            return WatchState(
                title: title, state: "Your turn", action: .micRefused, label: "Talk (the microphone is off)",
                enabled: false, listening: false, canPause: true)
        case "end":
            return WatchState(
                title: title, state: "Chapter complete", action: nil, label: "", enabled: false, listening: false,
                canPause: false)
        case "none":
            return WatchState.none
        default:
            return nil
        }
    }
}
#endif
