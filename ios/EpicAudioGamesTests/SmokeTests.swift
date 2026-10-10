// The app as built: the games, content and fonts bundled as android/app/build.gradle.kts bundles assets; Info.plist.

import Foundation
import Testing
import UIKit
@testable import EpicAudioGames

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

    /// docs/DESIGN.md's type: Atkinson Hyperlegible Next's Regular, Bold and ExtraBold (Android's res/font files), by
    /// the names Typography.swift asks for. Lilita One, the old design's font, is gone.
    @Test func atkinsonHyperlegibleNextIsRegistered() {
        for name in [Atkinson.regular, Atkinson.bold, Atkinson.extraBold] {
            #expect(UIFont(name: name, size: 17) != nil, "\(name)")
        }
        #expect([Atkinson.regular, Atkinson.bold, Atkinson.extraBold] == [
            "AtkinsonHyperlegibleNext-Regular", "AtkinsonHyperlegibleNext-Bold", "AtkinsonHyperlegibleNext-ExtraBold",
        ])
        let family = UIFont.fontNames(forFamilyName: "Atkinson Hyperlegible Next")
        #expect(family.contains("AtkinsonHyperlegibleNext-Regular"))
        #expect(family.contains("AtkinsonHyperlegibleNext-Bold"))
        #expect(UIFont.fontNames(forFamilyName: "Lilita One").isEmpty)
        #expect(UIFont(name: "LilitaOne", size: 17) == nil)
    }

    /// The font goes with its licence (the SIL Open Font License asks for it), in the app's own content/app/, which
    /// bundle_content.sh bundles whichever games' content it does.
    @Test(.enabled(if: contentPresent, "no content was bundled"))
    func theFontsLicenceIsBundled() {
        #expect(app.url(forResource: "OFL-AtkinsonHyperlegibleNext", withExtension: "txt",
                        subdirectory: "Content/app/licences") != nil)
    }

    @Test func infoPlist() throws {
        let info = try #require(app.infoDictionary)
        #expect(info["CFBundleIdentifier"] as? String == "com.epicaudiogames.app")
        #expect(info["CFBundleDisplayName"] as? String == "Epic Audio Games")
        #expect((info["NSMicrophoneUsageDescription"] as? String)?.isEmpty == false)
        #expect((info["NSSpeechRecognitionUsageDescription"] as? String)?.isEmpty == false)
        // Light or dark as the theme says (EpicTheme), the status bar with it: nothing forced once the app is up. The
        // launch screen is navy whatever the theme, so its status bar is light (the style as the app launches only).
        #expect(info["UIUserInterfaceStyle"] == nil)
        #expect(info["UIStatusBarStyle"] as? String == "UIStatusBarStyleLightContent")
        #expect(info["UIViewControllerBasedStatusBarAppearance"] == nil)
        #expect(info["UIAppFonts"] as? [String] == [
            "Fonts/atkinson_hyperlegible_next_regular.ttf", "Fonts/atkinson_hyperlegible_next_bold.ttf",
            "Fonts/atkinson_hyperlegible_next_extrabold.ttf",
        ])
        // The launch screen: navy, the emblem in the middle of the whole screen, where the intro draws it again.
        let launch = info["UILaunchScreen"] as? [String: Any]
        #expect(launch?["UIColorName"] as? String == "LaunchBackground")
        #expect(launch?["UIImageName"] as? String == "LaunchLogo")
        #expect(launch?["UIImageRespectsSafeAreaInsets"] as? Bool == false)
        #expect(info["EpicPacksURL"] is String)
        #expect(info["ITSAppUsesNonExemptEncryption"] as? Bool == false)
        let ats = info["NSAppTransportSecurity"] as? [String: Any]
        #expect(ats?["NSAllowsLocalNetworking"] as? Bool == true)
    }

    /// The launch screen's emblem, which the intro draws in the same place at the same size (IntroView: 160 pt).
    @Test func theLaunchLogoIsInTheApp() throws {
        let logo = try #require(UIImage(named: "LaunchLogo"))
        #expect(logo.size == CGSize(width: IntroView.emblem, height: IntroView.emblem))
    }

    /**
     * iPhone and iPad (docs/DESIGN.md › Tablets…): phones portrait only, an iPad every way round and any window size
     * (no UIRequiresFullScreen). Read from the built Info.plist as it's written: the bundle's infoDictionary gives an
     * iPad its ~ipad keys in place of the plain ones, so it would differ by device.
     */
    @Test func iPhoneAndIPad() throws {
        let data = try Data(contentsOf: app.bundleURL.appendingPathComponent("Info.plist"))
        let written = try #require(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        #expect(written["UIDeviceFamily"] as? [Int] == [1, 2])
        #expect(written["UISupportedInterfaceOrientations"] as? [String] == ["UIInterfaceOrientationPortrait"])
        #expect(written["UISupportedInterfaceOrientations~ipad"] as? [String] == [
            "UIInterfaceOrientationPortrait", "UIInterfaceOrientationPortraitUpsideDown",
            "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight",
        ])
        #expect(written["UIRequiresFullScreen"] == nil)
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
