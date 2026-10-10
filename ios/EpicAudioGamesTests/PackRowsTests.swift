// PackUiStateTest.kt: a pack's state in the Shop and the store sheet, and what its buttons are called.

import EpicAppCore
import Testing
@testable import EpicAudioGames

/**
 * A pack's state in the Shop and the store sheet (docs/DESIGN.md › Shop and the store sheet): every state, which wins
 * when the store knows several things at once, the download's percent and milestones, and the names VoiceOver reads,
 * each starting with the button's own words. iOS has three download states Android hasn't (installing, waiting for
 * Wi-Fi, waiting for a connection). Android: PackUiStateTest.kt.
 */
@MainActor
struct PackRowsTests {
    private func of(
        installed: Bool = false, download: DownloadState? = nil, owned: Bool = false, pending: Bool = false,
        price: String? = nil, loading: Bool = false
    ) -> PackUiState {
        PackUiState.of(installed: installed, download: download, owned: owned, pending: pending, price: price,
                       loading: loading)
    }

    @Test func eachStateOnItsOwn() {
        #expect(of(installed: true) == .installed)
        #expect(of(download: .downloading(0.4)) == .downloading(percent: 40))
        #expect(of(download: .installing) == .installing)
        #expect(of(download: .waitingForWiFi) == .waitingForWiFi)
        #expect(of(download: .waitingForNetwork) == .waitingForNetwork)
        #expect(of(owned: true) == .bought)
        #expect(of(pending: true) == .pending)
        #expect(of(price: "£1.99") == .forSale(price: "£1.99"))
        #expect(of(loading: true) == .priceUnknown(loading: true))
        #expect(of() == .priceUnknown(loading: false))
    }

    /// Over every combination: installed, then the download, bought, pending, a price, and last no price.
    @Test func theFirstThatAppliesWins() {
        let downloads: [DownloadState?] = [nil, .downloading(0.5), .installing, .waitingForWiFi, .waitingForNetwork]
        for installed in [false, true] {
            for download in downloads {
                for owned in [false, true] {
                    for pending in [false, true] {
                        for price in [nil, "£1.99"] {
                            for loading in [false, true] {
                                let expected: PackUiState
                                if installed {
                                    expected = .installed
                                } else if let download {
                                    switch download {
                                    case .downloading: expected = .downloading(percent: 50)
                                    case .installing: expected = .installing
                                    case .waitingForWiFi: expected = .waitingForWiFi
                                    case .waitingForNetwork: expected = .waitingForNetwork
                                    }
                                } else if owned {
                                    expected = .bought
                                } else if pending {
                                    expected = .pending
                                } else if let price {
                                    expected = .forSale(price: price)
                                } else {
                                    expected = .priceUnknown(loading: loading)
                                }
                                let got = of(installed: installed, download: download, owned: owned, pending: pending,
                                             price: price, loading: loading)
                                #expect(got == expected, """
                                    installed \(installed), download \(String(describing: download)), owned \(owned), \
                                    pending \(pending), price \(price ?? "nil"), loading \(loading)
                                    """)
                            }
                        }
                    }
                }
            }
        }
    }

    @Test func aDownloadIsAWholePercentFrom0To100() {
        #expect(PackUiState.percent(0) == 0)
        #expect(PackUiState.percent(0.399) == 39)
        #expect(PackUiState.percent(1) == 100)
        // A download that runs over its size (or a bad number) stays within the bar.
        #expect(PackUiState.percent(1.3) == 100)
        #expect(PackUiState.percent(-0.2) == 0)
        #expect(PackUiState.percent(.nan) == 0)
        #expect(PackUiState.percent(.infinity) == 100)
    }

    @Test func voiceOverHearsADownloadAtItsMilestonesOnly() {
        let milestones = [0: 0, 1: 0, 24: 0, 25: 25, 49: 25, 50: 50, 74: 50, 75: 75, 99: 75, 100: 75]
        for (percent, milestone) in milestones {
            #expect(PackUiState.downloading(percent: percent).milestone == milestone, "\(percent)%")
        }
        for state in notForSale + [PackUiState.forSale(price: "£1.99")] where state != .downloading(percent: 10) {
            #expect(state.milestone == nil, "\(state)")
        }
        #expect(downloadingLabel(pack: "45 more mysteries", milestone: 50) == "45 more mysteries: downloading, 50%")
    }

    @Test func theBuyButtonsWords() {
        #expect(buyText(.forSale(price: "£1.99")) == "Buy for £1.99")
        #expect(buyText(.priceUnknown(loading: true)) == "Get")
        #expect(buyText(.priceUnknown(loading: false)) == "Get")
        for state in notForSale {
            #expect(buyText(state) == nil, "\(state)")
        }
    }

    @Test func theBuyButtonsNameSaysWhichPack() {
        #expect(buyLabel(.forSale(price: "£1.99"), game: "The Werewolf", pack: "45 more mysteries")
            == "Buy for £1.99: The Werewolf, 45 more mysteries")
        #expect(buyLabel(.priceUnknown(loading: true), game: "The Werewolf", pack: "45 more mysteries")
            == "Get The Werewolf, 45 more mysteries, loading the price")
        #expect(buyLabel(.priceUnknown(loading: false), game: "The Werewolf", pack: "45 more mysteries")
            == "Get The Werewolf, 45 more mysteries")
        for state in notForSale {
            #expect(buyLabel(state, game: "The Werewolf", pack: "45 more mysteries") == nil, "\(state)")
        }
    }

    /// So Voice Control finds a button by what it shows (docs/DESIGN.md › Principles).
    @Test func eachNameStartsWithTheButtonsOwnWords() throws {
        for state in [PackUiState.forSale(price: "€2,29"), .priceUnknown(loading: true), .priceUnknown(loading: false)] {
            let label = try #require(buyLabel(state, game: "Alien Customs", pack: "10 more levels"))
            let words = try #require(buyText(state))
            #expect(label.hasPrefix(words), "\(label)")
        }
        let download = downloadLabel(game: "The Kingdom of Frootopia", pack: "Stories 2 to 5")
        #expect(download == "Download Stories 2 to 5 for The Kingdom of Frootopia")
        #expect(download.hasPrefix("Download Stories 2 to 5"))
    }

    /// The catalog's sizes, to the nearest megabyte (PackInfo.megabytes rounds the same way).
    @Test func aDownloadsSizeToTheNearestMegabyte() {
        #expect(downloadSize(14_558_828) == "15 MB download")
        #expect(downloadSize(25_619_378) == "26 MB download")
        #expect(downloadSize(133_444_602) == "133 MB download")
        #expect(downloadSize(500_000) == "1 MB download")
        let pack = PackInfo(id: "p", game: "g", title: "P", description: "", product: "p", version: 1,
                            size: 25_619_378, sha256: "")
        #expect(downloadSize(pack.size) == "\(pack.megabytes) MB download")
    }

    private let notForSale: [PackUiState] = [
        .installed, .downloading(percent: 10), .installing, .waitingForWiFi, .waitingForNetwork, .bought, .pending,
    ]
}
