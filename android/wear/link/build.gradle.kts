// What the phone app and the Wear OS app say to each other (docs/WEAR_OS.md): plain Kotlin (no Android), so both apps
// use the same words for it and its tests run on the JVM, as the engine's do. iOS has the same in
// ios/EpicEngine/Sources/EpicAppCore/WatchLink.swift.
plugins {
    kotlin("jvm")
}

kotlin {
    jvmToolchain(17)
}

dependencies {
    testImplementation("junit:junit:4.13.2")
}

tasks.withType<Test>().configureEach {
    testLogging {
        events("failed")
        exceptionFormat = org.gradle.api.tasks.testing.logging.TestExceptionFormat.FULL
    }
}
