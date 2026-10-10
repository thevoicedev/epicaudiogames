pluginManagement {
    repositories {
        google {
            content {
                includeGroupByRegex("com\\.android.*")
                includeGroupByRegex("com\\.google.*")
                includeGroupByRegex("androidx.*")
            }
        }
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "EpicAudioGames"
include(":engine")
include(":app")
// The Wear OS app (android/wear: a remote for the game on the phone; docs/WEAR_OS.md), and what it and the phone app
// say to each other through Wear OS's Data Layer (android/wear/link: plain Kotlin, used by both, tested on the JVM).
include(":wear")
include(":wear:link")
