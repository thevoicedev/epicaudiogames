// GameController.kt's open (lines 97-101) and MainActivity.kt's packInstalled (105-109): what opening a game plays.

/// What opening a game plays, and what the controller is to do with it.
public struct Opening {
    /// The game to play on: the one given, or a fresh one when its save couldn't be opened.
    public let game: any Play
    public let turn: Turn
    /// The save is picked up where it was left: the feed says "Welcome back!" before the turn.
    public let welcomeBack: Bool
    /// The save couldn't be opened, so it is to be cleared, and the game started afresh (docs/IOS_PARITY.md, L11).
    public let clearSave: Bool
}

/**
 * The one place that decides what opening a game plays: the game's `open(saved)`, as on Android. A save at a
 * question, or a map game's save at a chapter end whose next chapter is in its map (the end screen comes back, with
 * NEXT CHAPTER), is picked up; any other save starts the game again, a map game with its "keep" variables, as PLAY
 * AGAIN does (Session.open). That once was D15 (an ended save started afresh, keep variables and all).
 *
 * [unlocking] is D7's hook: a save at one of [ends] (the free map's locked chapter ends: [lockedChapterEnds]) opens
 * at that end once the pack is installed. Session.open now does that for every chapter end, so it opens as [android]
 * does.
 */
public enum OpenPolicy: Equatable, Sendable {
    case android
    case unlocking(ends: [String])

    /**
     * Opens [game] at [saved] (nil: no save). When the save can't be opened (Kotlin would crash), the game from
     * [fresh] is started instead and the save is to be cleared; an error with no save to blame is thrown.
     */
    public func open(_ game: any Play, saved: Saved?, fresh: () -> any Play) throws -> Opening {
        guard let saved else {
            return Opening(game: game, turn: try game.open(nil), welcomeBack: false, clearSave: false)
        }
        do {
            let welcome = game.canResume(saved)
            return Opening(game: game, turn: try game.open(saved), welcomeBack: welcome, clearSave: false)
        } catch {
            let new = fresh()
            return Opening(game: new, turn: try new.start(), welcomeBack: false, clearSave: true)
        }
    }

    /// The chapter ends of a free map (no packs merged) that a pack unlocks: they name it in "locked".
    public static func lockedChapterEnds(_ freeMap: GameMap) -> [String] {
        freeMap.nodes.compactMap { node in
            guard let end = node.value.end, end.kind == "chapter", end.next != nil, end.locked != nil else {
                return nil
            }
            return node.key
        }
    }
}

extension End {
    /// A chapter's end whose next chapter is in the game (GameController.canGoOn): NEXT CHAPTER shows.
    public func canGoOn(in game: any Play) -> Bool {
        guard kind == "chapter", let next else { return false }
        return game.hasChapter(next)
    }
}

extension OpenPolicy {
    /**
     * What opening [game] goes by (D7). [lockedEnds]: its free map's locked chapter ends ([lockedChapterEnds]; empty
     * for a game with no packs, and for Nuclear War). Either way the game opens as Android opens it: a save at one of
     * those ends opens there once the next chapter is in its map, so NEXT CHAPTER shows.
     */
    public static func opening(_ game: GameInfo, installedPack: PackInfo? = nil, lockedEnds: [String]) -> OpenPolicy {
        if let installedPack, installedPack.game != game.id { return .android }
        return lockedEnds.isEmpty ? .android : .unlocking(ends: lockedEnds)
    }
}
