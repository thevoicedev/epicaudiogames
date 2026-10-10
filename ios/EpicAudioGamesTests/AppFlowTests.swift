// AppFlowTest.kt: the way into the app (AppFlow.swift; docs/DESIGN.md › Structure, › Intro, › Onboarding): what shows
// before the tabs, onboarding's pages and steps, where it ends, and the intro's and Listen's times.

import Foundation
import Testing
@testable import EpicAudioGames

@MainActor
struct AppFlowTests {
    @Test func theIntroShowsOnTheProcesssFirstLaunchWithItsSoundOn() {
        #expect(AppStart.of(introSound: true, firstLaunch: true, onboardingVersion: 1).intro)
        // Once per process: another model in the same process (the unit tests') has none.
        #expect(!AppStart.of(introSound: true, firstLaunch: false, onboardingVersion: 1).intro)
        // "Play the intro sound" off skips the intro screen too, not just its sound.
        #expect(!AppStart.of(introSound: false, firstLaunch: true, onboardingVersion: 1).intro)
    }

    @Test func onboardingShowsUntilItsBeenFinishedOrSkippedOnce() {
        #expect(AppStart.of(introSound: true, firstLaunch: true, onboardingVersion: 0).onboarding)
        #expect(!AppStart.of(introSound: true, firstLaunch: true, onboardingVersion: AppStart.onboardingVersion)
            .onboarding)
        // Without the intro, onboarding is the first thing on the first run, and the tabs after that.
        #expect(AppStart.of(introSound: false, firstLaunch: true, onboardingVersion: 0)
            == AppStart(intro: false, onboarding: true))
        #expect(AppStart.of(introSound: false, firstLaunch: false, onboardingVersion: 1)
            == AppStart(intro: false, onboarding: false))
        #expect(AppStart.onboardingVersion == 1)
    }

    @Test func voiceOversPageOnlyWithItOn() {
        let without: [OnboardingPage] = [.welcome, .mic, .comfort, .ready]
        #expect(OnboardingPage.pages(screenReader: false) == without)
        #expect(OnboardingPage.pages(screenReader: true) == OnboardingPage.allCases)
        // VoiceOver turned off on that page doesn't take the page from under the player.
        #expect(OnboardingPage.pages(screenReader: false, showing: .screenReader) == OnboardingPage.allCases)
    }

    @Test func eachStepSaysWhereItIsAndWhereNextAndBackGo() {
        let first = OnboardingStep.of(.welcome, screenReader: false)
        #expect(first.words == "Step 1 of 4")
        #expect(first.previous == nil)
        #expect(first.next == .mic)
        #expect(!first.last)
        // Without VoiceOver, the comfort page is followed by the last.
        let comfort = OnboardingStep.of(.comfort, screenReader: false)
        #expect(comfort.words == "Step 3 of 4")
        #expect(comfort.next == .ready)
        // With it, by VoiceOver's page, and there are five.
        let withVoiceOver = OnboardingStep.of(.comfort, screenReader: true)
        #expect(withVoiceOver.words == "Step 3 of 5")
        #expect(withVoiceOver.next == .screenReader)
        let ready = OnboardingStep.of(.ready, screenReader: true)
        #expect(ready.words == "Step 5 of 5")
        #expect(ready.last)
        #expect(ready.next == nil)
        #expect(ready.previous == .screenReader)
    }

    @Test func walkingThroughVisitsEveryPageOnceInOrder() {
        for screenReader in [false, true] {
            var seen: [OnboardingPage] = []
            var page: OnboardingPage? = .welcome
            while let at = page {
                seen.append(at)
                page = OnboardingStep.of(at, screenReader: screenReader).next
            }
            #expect(seen == OnboardingPage.pages(screenReader: screenReader))
            // And back again, from the last.
            var back: [OnboardingPage] = []
            var previous: OnboardingPage? = seen.last
            while let at = previous {
                back.append(at)
                previous = OnboardingStep.of(at, screenReader: screenReader).previous
            }
            #expect(back == seen.reversed())
        }
    }

    @Test func theOnboardingPagesHaveDesignsIdentifiers() throws {
        #expect(OnboardingPage.allCases.map(\.tag) == [
            "onboarding-welcome", "onboarding-mic", "onboarding-comfort", "onboarding-screen-reader",
            "onboarding-ready",
        ])
        // As docs/DESIGN.md's table of test identifiers names them (Android's tests use the same).
        let design = try String(contentsOf: Self.repo.appendingPathComponent("docs/DESIGN.md"), encoding: .utf8)
        #expect(design.contains("`onboarding-welcome`, `-mic`, `-comfort`, `-screen-reader`, `-ready`"))
    }

    @Test func onboardingEndsOnGamesOrBackWhereItWasOpened() {
        // The first run: Games, finished or skipped.
        #expect(tabAfterOnboarding(completed: true, openedFrom: nil) == .games)
        #expect(tabAfterOnboarding(completed: false, openedFrom: nil) == .games)
        // Opened again from Settings or Help: Start playing goes to Games, Skip back.
        #expect(tabAfterOnboarding(completed: true, openedFrom: .settings) == .games)
        #expect(tabAfterOnboarding(completed: false, openedFrom: .settings) == .settings)
        #expect(tabAfterOnboarding(completed: false, openedFrom: .help) == .help)
    }

    @Test func theIntrosAndListensTimesAreDesigns() {
        #expect(IntroTimes.screenReaderDelay == .milliseconds(700))
        #expect(IntroTimes.afterSting == .milliseconds(300))
        #expect(IntroTimes.withoutSting == .milliseconds(2500))
        #expect(IntroTimes.fadeIn == 0.3)
        #expect(A11y.listenDelay == .milliseconds(400))
        #expect(A11y.focusDelay == .milliseconds(300))
        // After a page is pushed or a sheet rises, past iOS's own move of VoiceOver to the new screen.
        #expect(A11y.focusAfterTransition > .milliseconds(350))
    }

    /// The repository: EPIC_REPO_ROOT (the scheme sets it for the tests), else from this file's place in it
    /// (ios/EpicAudioGamesTests/).
    private static var repo: URL {
        if let root = ProcessInfo.processInfo.environment["EPIC_REPO_ROOT"], !root.isEmpty {
            return URL(fileURLWithPath: root)
        }
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
