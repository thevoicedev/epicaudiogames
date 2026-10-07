// No Kotlin counterpart: iOS hands the app a pack download that finished while the app wasn't running.

import UIKit

/// The app's UIKit delegate: a background download's events, delivered by launching the app (PackDownloader).
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier == PackDownloader.identifier else {
            completionHandler()
            return
        }
        PackDownloader.shared.handOver(completionHandler)
    }
}
