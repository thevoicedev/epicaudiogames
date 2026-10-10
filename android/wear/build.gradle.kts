// The Wear OS app (docs/WEAR_OS.md; docs/DESIGN.md › Watches): a remote for the game on the phone, which plays the
// audio and listens (a watch has no speech recognition for apps, and the games are about 190 MB). It shows the game's
// state and has its one button and Pause, through Wear OS's Data Layer (PhoneLink.kt; the phone's side is the app's
// WearBridge.kt). It has the phone app's applicationId and is signed with the same key, as the Data Layer requires, and
// ships in the same Play listing, on its Wear OS track.
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

// The phone app's version (android/app/build.gradle.kts, where fastlane reads it), which the watch app's follows.
evaluationDependsOn(":app")
val phone = project(":app").extensions.getByType<com.android.build.api.dsl.ApplicationExtension>().defaultConfig

android {
    namespace = "com.epicaudiogames.wear"
    compileSdk = 36

    defaultConfig {
        // The phone app's: the Data Layer only joins apps with the same package name and signature on both devices.
        applicationId = "com.epicaudiogames.app"
        // Wear OS 3 (Android 11) and later: every watch Play sells Wear OS apps to now.
        minSdk = 30
        targetSdk = 36
        // Each build in the listing needs its own versionCode, whatever the device: the phone's plus one. The phone's
        // next release then has to be at least two higher (docs/WEAR_OS.md, Shipping), which fastlane's check of
        // every track's versionCodes already asks for.
        versionCode = checkNotNull(phone.versionCode) + 1
        versionName = phone.versionName
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            // As the phone app's: the debug key until the release key is set up; fastlane's upload key takes over
            // through the injected signing properties (docs/WEAR_OS.md).
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
    buildFeatures {
        compose = true
    }

    // The screen's tests run on the JVM under Robolectric, with the app's resources (src/testDebug: WatchScreenTest),
    // as they need no watch. -PwearShots=<folder> also saves each state's picture there (docs/WEAR_OS.md).
    testOptions {
        unitTests.isIncludeAndroidResources = true
        unitTests.all {
            it.systemProperty("wear.shots", project.findProperty("wearShots")?.toString().orEmpty())
        }
    }
}

dependencies {
    implementation(project(":wear:link"))

    // Compose UI 1.8, as the phone app's, under Compose for Wear OS 1.5 (Material 3: its first stable, built on 1.8).
    val composeBom = platform("androidx.compose:compose-bom:2025.05.01")
    implementation(composeBom)
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.wear.compose:compose-material3:1.5.0")
    implementation("androidx.wear.compose:compose-foundation:1.5.0")
    // Ambient mode: with the wrist down the game stays on the screen, dimmed, and the buzzes still come.
    implementation("androidx.wear:wear:1.3.0")
    // The Data Layer: the phone's state in, the buttons out.
    implementation("com.google.android.gms:play-services-wearable:19.0.0")

    // JVM tests: the colours, the buzzes, the icon (wear/src/test); the screen in each state, as TalkBack finds it
    // (wear/src/testDebug, under Robolectric; the test manifest gives Compose's test rule an activity, debug only).
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.robolectric:robolectric:4.14.1")
    testImplementation("androidx.test.ext:junit:1.2.1")
    testImplementation(composeBom)
    testImplementation("androidx.compose.ui:ui-test-junit4")
    debugImplementation("androidx.compose.ui:ui-test-manifest")
}
