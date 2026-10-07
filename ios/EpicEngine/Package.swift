// swift-tools-version: 6.0
// The game engine in Swift: a port of android/engine (Kotlin), checked against the Kotlin engine by the fixtures in
// fixtures/engine/. Foundation and CryptoKit only, so it builds and tests on macOS (`swift test`) as well as iOS.
import PackageDescription

let package = Package(
    name: "EpicEngine",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "EpicEngine", targets: ["EpicEngine"]),
        .library(name: "EpicAppCore", targets: ["EpicAppCore"]),
        .executable(name: "eag", targets: ["eag"]),
    ],
    targets: [
        // Maps, answers, saves and Nuclear War: android/engine/src/main/kotlin.
        .target(name: "EpicEngine"),
        // The app's logic that needs no AVFoundation or UIKit: catalog, saves, transcript timing, packs.
        .target(name: "EpicAppCore", dependencies: ["EpicEngine"]),
        // Replays the Kotlin engine's fixtures (tests and eag only; not linked by the app).
        .target(name: "EpicConformance", dependencies: ["EpicEngine"]),
        // Play a game by typing: android/engine/.../Cli.kt.
        .executableTarget(name: "eag", dependencies: ["EpicEngine", "EpicConformance"]),
        .testTarget(name: "EpicEngineTests", dependencies: ["EpicEngine", "EpicConformance"]),
        .testTarget(name: "EpicConformanceTests", dependencies: ["EpicEngine", "EpicConformance"]),
        .testTarget(name: "EpicAppCoreTests", dependencies: ["EpicAppCore", "EpicConformance"]),
    ],
    swiftLanguageModes: [.v6]
)
