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

// The maps the tests read: games/, or another copy with -Pgames.dir=<dir>.
val gamesDir = (findProperty("games.dir") as String?)?.let { file(it) } ?: File(repoRoot, "games")
// The golden fixtures the Swift engine replays (fixtures/engine/README.md).
val fixturesDir = File(repoRoot, "fixtures/engine")
val engineSrc = file("src/main/kotlin")

tasks.withType<Test>().configureEach {
    systemProperty("games.dir", gamesDir.path)
    systemProperty("fixtures.dir", fixturesDir.path)
    systemProperty("engine.src", engineSrc.path)
    maxHeapSize = "2g"                  // the bot's walk of the bigger maps (The Werewolf has 110 variables)
    // The tests read the maps: a change to them runs the tests again.
    inputs.dir(gamesDir)
    testLogging {
        events("failed")
        showStandardStreams = true
        exceptionFormat = org.gradle.api.tasks.testing.logging.TestExceptionFormat.FULL
    }
}

tasks.test {
    // And the Alexa recordings, when there are any (a file tree of a missing folder is empty, so a fresh checkout
    // without tools/cache still builds).
    inputs.files(fileTree(File(repoRoot, "tools/cache/parity"))).withPropertyName("parity")
}

// `gradlew :engine:goldens` writes fixtures/engine; `gradlew :engine:goldensCheck` fails when they're out of date.
// `-Pgoldens.dump=<spec>` writes one walk or game to build/golden-dump instead (fixtures/engine/README.md, Dump mode).
fun registerGoldens(name: String, mode: String, what: String) = tasks.register<Test>(name) {
    description = what
    group = "verification"
    testClassesDirs = sourceSets["test"].output.classesDirs
    classpath = sourceSets["test"].runtimeClasspath
    filter { includeTestsMatching("*GoldenTest*") }
    systemProperty("goldens.$mode", "true")
    systemProperty("goldens.dumpDir", layout.buildDirectory.dir("golden-dump").get().asFile.path)
    (findProperty("goldens.dump") as String?)?.let { systemProperty("goldens.dump", it) }
    inputs.files(fileTree(fixturesDir)).withPropertyName("fixtures")
    inputs.dir(file("src/main")).withPropertyName("engine")
    outputs.upToDateWhen { false }
}

registerGoldens("goldens", "write", "Writes the golden fixtures in fixtures/engine.")
registerGoldens("goldensCheck", "check", "Fails when fixtures/engine isn't what the engine makes now.")
