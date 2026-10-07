// ui/HomeScreen.kt's rememberAssetImage (lines 140-147): a game's cover, decoded once.

import UIKit

/// Each game's cover (Content/<id>/cover.jpg), decoded once and kept; nil when the build has none.
enum Covers {
    private static var cache: [String: UIImage?] = [:]

    static func image(_ game: String) -> UIImage? {
        if let hit = cache[game] { return hit }
        let url = Bundle.main.url(forResource: "cover", withExtension: "jpg", subdirectory: "Content/\(game)")
        let image = url.flatMap { UIImage(contentsOfFile: $0.path) }.flatMap { $0.preparingForDisplay() ?? $0 }
        cache[game] = image
        return image
    }
}
