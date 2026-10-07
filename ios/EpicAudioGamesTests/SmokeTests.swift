// The app as built: the games, content and font bundled as android/app/build.gradle.kts bundles assets, and Info.plist.

import Foundation
import Testing
import UIKit

/// Whether the build bundled any content (CI builds without content/ skip the content checks).
let contentPresent = Bundle.main.url(forResource: "Content", withExtension: nil) != nil

@MainActor
struct SmokeTests {
    let app = Bundle.main       // the tests run inside the app
    let ids = ["frootopia", "noodle-rush", "signal-decoders", "pirate-quest", "leaning-tower-of-pizza", "alien-customs",
               "the-werewolf", "nuclear-war"]

    @Test func catalogHasTheEightGamesInOrder() throws {
        let url = try #require(app.url(forResource: "catalog", withExtension: "json", subdirectory: "Games"))
        let catalog = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let games = try #require(catalog["games"] as? [[String: Any]])
        #expect(games.compactMap { $0["id"] as? String } == ids)
    }

    @Test func eachGameHasItsMapOrClips() {
        for id in ids {
            let file = id == "nuclear-war" ? "clips" : "map"
            #expect(app.url(forResource: file, withExtension: "json", subdirectory: "Games/\(id)") != nil, "\(id)")
        }
    }

    /// Packs come in their own downloads, and lines.json isn't the app's (Android's ignoreAssetsPatterns).
    @Test func noPacksOrLinesInTheApp() throws {
        let files = try relativePaths(under: app.bundleURL)
        #expect(!files.contains { $0.hasSuffix("/lines.json") || $0 == "lines.json" })
        #expect(!files.contains { $0.contains("/packs/") || $0.hasPrefix("packs/") })
        // Config/Info.plist makes the app's Info.plist; it isn't copied in as a resource.
        #expect(!files.contains { $0.hasSuffix("Info.plist") && $0 != "Info.plist" })
        #expect(files.contains("PrivacyInfo.xcprivacy"))
    }

    @Test func lilitaOneIsRegistered() {
        #expect(UIFont.fontNames(forFamilyName: "Lilita One").contains("LilitaOne"))
        #expect(UIFont(name: "LilitaOne", size: 17) != nil)
    }

    @Test func infoPlist() throws {
        let info = try #require(app.infoDictionary)
        #expect(info["CFBundleIdentifier"] as? String == "com.epicaudiogames.app")
        #expect(info["CFBundleDisplayName"] as? String == "Epic Audio Games")
        #expect((info["NSMicrophoneUsageDescription"] as? String)?.isEmpty == false)
        #expect((info["NSSpeechRecognitionUsageDescription"] as? String)?.isEmpty == false)
        #expect(info["UISupportedInterfaceOrientations"] as? [String] == ["UIInterfaceOrientationPortrait"])
        #expect(info["UIUserInterfaceStyle"] as? String == "Light")
        #expect(info["UIAppFonts"] as? [String] == ["Fonts/lilita_one.ttf"])
        #expect((info["UILaunchScreen"] as? [String: Any])?["UIColorName"] as? String == "LaunchBackground")
        #expect(info["EpicPacksURL"] is String)
        #expect(info["ITSAppUsesNonExemptEncryption"] as? Bool == false)
        let ats = info["NSAppTransportSecurity"] as? [String: Any]
        #expect(ats?["NSAllowsLocalNetworking"] as? Bool == true)
    }

    @Test(.enabled(if: contentPresent, "no content was bundled"))
    func eachGameHasACover() {
        for id in ids {
            #expect(app.url(forResource: "cover", withExtension: "jpg", subdirectory: "Content/\(id)") != nil, "\(id)")
        }
    }

    /// Every file in a folder, as a path relative to it; the test bundle's own folders are left out.
    private func relativePaths(under root: URL) throws -> [String] {
        let base = root.standardizedFileURL.path + "/"
        guard let walk = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return [] }
        var out: [String] = []
        for case let url as URL in walk {
            let path = String(url.standardizedFileURL.path.dropFirst(base.count))
            if path.hasPrefix("PlugIns/") || path.hasPrefix("Frameworks/") || path.hasPrefix("_CodeSignature/") {
                continue
            }
            out.append(path)
        }
        return out
    }
}
