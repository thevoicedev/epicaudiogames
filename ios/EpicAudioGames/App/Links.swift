// Links.kt: the website's pages and the support address.

import Foundation

/**
 * The website's pages and the support address, opened from the game's menu, Help and Settings (the stores want the
 * help and privacy pages reachable in the app). The same as Android's Links.kt. SwiftUI's openURL opens them: a page in
 * Safari, [mailto] in the Mail app.
 */
enum Links {
    static let support = URL(string: "https://epicaudiogames.com/support")!
    static let privacy = URL(string: "https://epicaudiogames.com/privacy")!
    static let accessibility = URL(string: "https://epicaudiogames.com/accessibility")!
    /// The website's support address (support.html).
    static let email = "james@hugo.fm"
    /// A new email to [email], its subject the app's name (as the website's link).
    static let mailto = URL(string: "mailto:\(email)?subject=Epic%20Audio%20Games")!
}
