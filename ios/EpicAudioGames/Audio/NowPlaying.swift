// No Kotlin counterpart (Android has no media session): the lock screen's Now Playing, and the headphones' button.

import MediaPlayer
import UIKit

/**
 * While a game is open: the lock screen and Control Center show it (its title, "Epic Audio Games", its cover, and
 * whether it's speaking or listening). Their buttons and the headphones' act on it ([press]):
 * - play/pause as one button (togglePlayPause: AirPods' press, a wired headset's click) does what the talking
 *   circle's Magic Tap does (GameController.magicTap): skip the voice while it speaks, start or stop listening while
 *   it waits, carry on after a pause;
 * - pause pauses the game (the Paused overlay): AirPods send it when an earbud is taken out;
 * - play carries on after a pause, or starts listening while the game waits.
 * There's nothing to skip to or seek in: those commands are off. Everything is cleared when the game closes.
 */
final class NowPlaying {
    static let artist = "Epic Audio Games"

    /// The commands that act on the game.
    enum Command: CaseIterable {
        case togglePlayPause, play, pause
    }

    private(set) var game: GameController?
    private let center: MPNowPlayingInfoCenter
    private let commands: MPRemoteCommandCenter
    private var targets: [(MPRemoteCommand, Any)] = []
    /// Bumped by each show and clear: an observation of the last game is let go.
    private var shown = 0

    init(center: MPNowPlayingInfoCenter = .default(), commands: MPRemoteCommandCenter = .shared()) {
        self.center = center
        self.commands = commands
    }

    /// The play/pause commands.
    var playPause: [MPRemoteCommand] { Command.allCases.map(command) }

    func command(_ c: Command) -> MPRemoteCommand {
        switch c {
        case .togglePlayPause: commands.togglePlayPauseCommand
        case .play: commands.playCommand
        case .pause: commands.pauseCommand
        }
    }

    /// The commands a game has no use for: there's no next or last track, and nothing to seek in.
    var unused: [MPRemoteCommand] {
        [
            commands.nextTrackCommand, commands.previousTrackCommand, commands.skipForwardCommand,
            commands.skipBackwardCommand, commands.seekForwardCommand, commands.seekBackwardCommand,
            commands.changePlaybackPositionCommand, commands.changePlaybackRateCommand, commands.changeRepeatModeCommand,
            commands.changeShuffleModeCommand,
        ]
    }

    /// [game] is open: it's what's playing, and the buttons act on it.
    func show(_ game: GameController, cover: UIImage?) {
        clear()
        self.game = game
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: game.info.title,
            MPMediaItemPropertyArtist: Self.artist,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyIsLiveStream: true,
        ]
        if let cover { info[MPMediaItemPropertyArtwork] = Self.artwork(cover) }
        center.nowPlayingInfo = info
        for c in unused { c.isEnabled = false }
        for c in Command.allCases {
            let remote = command(c)
            remote.isEnabled = true
            let target = remote.addTarget(handler: Self.handler { [weak self] in
                self?.press(c) ?? .noActionableNowPlayingItem
            })
            targets.append((remote, target))
        }
        update()
        watch()
    }

    /// The game closed: nothing is playing, and the buttons do nothing.
    func clear() {
        shown += 1
        game = nil
        for (command, target) in targets { command.removeTarget(target) }
        targets = []
        for c in playPause { c.isEnabled = false }
        center.nowPlayingInfo = nil
        center.playbackState = .stopped
    }

    /**
     * A command, from the headphones or the lock screen. Play/pause as one button is Magic Tap; pause pauses (not at
     * an end, nor when already paused); play carries on after a pause, or starts listening while the game waits. They
     * listen only if the mic is allowed (the permission dialog can't be shown from the lock screen).
     */
    func press(_ command: Command) -> MPRemoteCommandHandlerStatus {
        guard let game else { return .noActionableNowPlayingItem }
        switch command {
        case .togglePlayPause:
            game.magicTap {
                if game.micAllowed { game.mic() }
            }
        case .pause:
            if !game.paused && game.end == nil { game.pause() }
        case .play:
            if game.paused {
                game.carryOn()
            } else if !game.speaking && !game.listening && game.end == nil && game.micAllowed {
                game.mic()
            }
        }
        update()
        return .success
    }

    /// Playing while the game speaks or listens; paused while it waits, is paused, or is at an end.
    var isPlaying: Bool {
        guard let game else { return false }
        return !game.paused && (game.speaking || game.listening)
    }

    private func update() {
        guard game != nil else { return }
        let playing = isPlaying
        center.playbackState = playing ? .playing : .paused
        var info = center.nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyPlaybackRate] = playing ? 1.0 : 0.0
        center.nowPlayingInfo = info
    }

    /// The playback state follows the game (observed, as the screen may not be drawn while the phone is locked).
    private func watch() {
        let id = shown
        withObservationTracking {
            _ = isPlaying
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.shown == id else { return }
                self.update()
                self.watch()
            }
        }
    }

    /**
     * A command's handler. MediaPlayer calls it on the main thread, but its closure must not inherit the main actor
     * (Swift 6 traps if it ever runs elsewhere), so it's made here and hops to the main actor itself.
     */
    nonisolated private static func handler(
        _ action: @escaping @MainActor @Sendable () -> MPRemoteCommandHandlerStatus
    ) -> (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        { _ in
            if Thread.isMainThread { return MainActor.assumeIsolated { action() } }
            DispatchQueue.main.async { MainActor.assumeIsolated { _ = action() } }
            return .success
        }
    }

    /// The cover for the lock screen. MediaPlayer asks for it on its own queue: the closure is made here, nonisolated.
    nonisolated private static func artwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
}
