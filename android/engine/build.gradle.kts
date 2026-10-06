// The game engine: pure Kotlin (no Android), so it runs and is tested on the JVM. The app uses it as a library.
plugins {
    kotlin("jvm")
    application
}

kotlin {
    jvmToolchain(17)
}

dependencies {
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.6.3")
    testImplementation("junit:junit:4.13.2")
}

val repoRoot = rootProject.projectDir.parentFile

application {
    mainClass.set("com.epicaudiogames.engine.CliKt")
}

// `gradlew :engine:run --args="noodle-rush" --console=plain`: play a game by typing, from the repo root.
tasks.named<JavaExec>("run") {
    workingDir = repoRoot
    standardInput = System.`in`
}

tasks.test {
    systemProperty("games.dir", File(repoRoot, "games").path)
    testLogging {
        events("failed")
        showStandardStreams = true
        exceptionFormat = org.gradle.api.tasks.testing.logging.TestExceptionFormat.FULL
    }
}
