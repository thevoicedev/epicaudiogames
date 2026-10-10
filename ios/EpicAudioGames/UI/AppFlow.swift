// ui/AppFlow.kt: the way into the app as it starts (the intro, then onboarding, then the tabs), onboarding's pages and
// steps, and the intro's times.

/**
 * What shows before the tabs as the app starts (docs/DESIGN.md › Structure): the launch screen, then the intro (the
 * sting, once per process, with Settings › Play the intro sound on), then onboarding (until it's been finished or
 * skipped once), then the tabs. Plain Swift, as AppModel decides it, unit-tested (AppFlowTests). Android's AppStart.
 */
nonisolated struct AppStart: Equatable, Sendable {
    let intro: Bool
    let onboarding: Bool

    /// settings.onboardingVersion once onboarding is finished or skipped: a new one, with new pages, would be 2.
    /// Android's ONBOARDING_VERSION.
    static let onboardingVersion = 1

    /**
     * The intro on the process's first launch ([firstLaunch]) when the intro sound is on (off, there's no intro screen
     * at all), and onboarding while [onboardingVersion] is older than this app's.
     */
    static func of(introSound: Bool, firstLaunch: Bool, onboardingVersion: Int) -> AppStart {
        AppStart(intro: introSound && firstLaunch, onboarding: onboardingVersion < Self.onboardingVersion)
    }
}

/**
 * Where the player goes as onboarding ends: Start playing goes to Games, and so does Skip the first time; Skip in the
 * onboarding opened again ("Show the welcome again", from Help or Settings) goes back to that tab ([openedFrom]).
 */
nonisolated func tabAfterOnboarding(completed: Bool, openedFrom: AppTab?) -> AppTab {
    if completed { return .games }
    return openedFrom ?? .games
}

/// Onboarding's pages (docs/DESIGN.md › Onboarding), in order; [tag] is the page's test identifier. Android's
/// OnboardingPage.
nonisolated enum OnboardingPage: CaseIterable, Hashable, Sendable {
    /// The welcome, read aloud, and the line about usage data with its Turn off.
    case welcome
    /// "Answer out loud": why the microphone, before iOS asks for it.
    case mic
    /// "Make it comfortable": the theme and the text size.
    case comfort
    /// "Playing with VoiceOver": only with it on.
    case screenReader
    /// "You're ready", and Start playing.
    case ready

    var tag: String {
        switch self {
        case .welcome: "onboarding-welcome"
        case .mic: "onboarding-mic"
        case .comfort: "onboarding-comfort"
        case .screenReader: "onboarding-screen-reader"
        case .ready: "onboarding-ready"
        }
    }

    /**
     * The pages a player goes through: VoiceOver's with it on, or while it's the page [showing] (VoiceOver turned off
     * there doesn't take the page from under the player); the others always.
     */
    static func pages(screenReader: Bool, showing: OnboardingPage? = nil) -> [OnboardingPage] {
        allCases.filter { $0 != .screenReader || screenReader || showing == .screenReader }
    }
}

/**
 * Where onboarding is: [page], among the [pages] the player goes through. Its place in words ("Step 2 of 4"), and where
 * Next and Back go; the last page has Start playing instead of Next, the first no Back. Android's OnboardingStep.
 */
nonisolated struct OnboardingStep: Equatable, Sendable {
    let page: OnboardingPage
    let pages: [OnboardingPage]
    private let index: Int

    init(page: OnboardingPage, pages: [OnboardingPage]) {
        precondition(pages.contains(page), "\(page) isn't one of \(pages)")
        self.page = page
        self.pages = pages
        index = pages.firstIndex(of: page) ?? 0
    }

    /// 1 for the first page.
    var number: Int { index + 1 }
    var count: Int { pages.count }
    var words: String { "Step \(number) of \(count)" }
    var next: OnboardingPage? { index + 1 < pages.count ? pages[index + 1] : nil }
    var previous: OnboardingPage? { index > 0 ? pages[index - 1] : nil }
    var last: Bool { next == nil }

    /// [page], among the pages for VoiceOver on or off.
    static func of(_ page: OnboardingPage, screenReader: Bool) -> OnboardingStep {
        OnboardingStep(page: page, pages: OnboardingPage.pages(screenReader: screenReader, showing: page))
    }
}

/// The intro's times (docs/DESIGN.md › Intro). Android's IntroTimes.
nonisolated enum IntroTimes {
    /// With VoiceOver on, the sting waits this long, so the intro's name is read first.
    static let screenReaderDelay: Duration = .milliseconds(700)
    /// The intro ends this long after the sting.
    static let afterSting: Duration = .milliseconds(300)
    /// With no sting (none in the build, another app's audio playing), the intro lasts this long.
    static let withoutSting: Duration = .milliseconds(2500)
    /// The wordmark (and the circle round the emblem) fade in over this long, in seconds; at once with Reduce Motion.
    static let fadeIn: Double = 0.3
}
