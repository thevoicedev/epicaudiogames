plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

val repoRoot = rootProject.projectDir.parentFile

android {
    namespace = "com.epicaudiogames.app"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.epicaudiogames.app"
        minSdk = 24
        targetSdk = 36
        versionCode = 3
        versionName = "1.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        // Where packs are downloaded from (<url>/<pack>-<version>.zip): gradle property epicPacksUrl, set in
        // ~/.gradle/gradle.properties or with -PepicPacksUrl=... Empty: the store can't download packs yet.
        buildConfigField("String", "PACKS_URL", "\"${project.findProperty("epicPacksUrl") ?: ""}\"")
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            // Signed with the debug key until the release key is set up (phase 5): for testing only.
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
        buildConfig = true
    }

    // The games ship inside the app for now: games/ (catalog.json and each game's map.json) and content/ (each
    // game's audio and cover, built by the tools) merge into assets/<id>/. The audio can come from another folder
    // (gradle property epicContentDir, -PepicContentDir=...; as iOS's EPIC_CONTENT_DIR), e.g. placeholder audio.
    val contentDir = project.findProperty("epicContentDir")?.toString()?.let(::File) ?: File(repoRoot, "content")
    sourceSets["main"].assets.srcDirs(File(repoRoot, "games"), contentDir)
    // The JVM tests read the app's own content as the app gets it (app.json, the earcons): the same folder.
    testOptions {
        unitTests.all {
            it.systemProperty("content.dir", contentDir.path)
            it.inputs.files(it.project.fileTree(File(contentDir, "app")) { include("app.json", "earcons/**") })
                .withPropertyName("appContent")
        }
    }
    androidResources {
        noCompress += listOf("m4a", "mp3", "opus")
        // A game's packs (games/<id>/packs/) come in their own downloads, not in the app; Nuclear War's lines.json
        // is what its clips were made from (the app reads clips.json). Setting any pattern replaces aapt's own list,
        // so that comes first: no dotfiles, _folders, Thumbs.db or the like.
        ignoreAssetsPatterns += "!.svn:!.git:!.ds_store:!*.scc:.*:<dir>_*:!CVS:!thumbs.db:!picasa.ini:!*~".split(":") +
            listOf("<dir>packs", "<file>lines.json")
    }
    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }
}

dependencies {
    implementation(project(":engine"))

    // Compose UI 1.8: the first with ui-test-junit4-accessibility (the UI tests' accessibility checks).
    val composeBom = platform("androidx.compose:compose-bom:2025.05.01")
    implementation(composeBom)
    implementation("androidx.core:core-ktx:1.13.1")
    // The system splash (navy, the logo) before the intro screen, on Android 7 to 11 as on 12 and later.
    implementation("androidx.core:core-splashscreen:1.0.1")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.7")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.7")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3")
    // Tablets, foldables and Chromebooks (docs/DESIGN.md › Tablets…): the window's width class, the tab bar that turns
    // into a rail on medium and expanded widths, and the list-detail layout (Help). The BOM's versions (adaptive 1.1.0,
    // navigation suite 1.3.2, as material3).
    implementation("androidx.compose.material3.adaptive:adaptive")
    implementation("androidx.compose.material3.adaptive:adaptive-layout")
    implementation("androidx.compose.material3:material3-adaptive-navigation-suite")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.media3:media3-exoplayer:1.4.1")
    implementation("com.android.billingclient:billing-ktx:8.0.0")
    // The Wear OS app (android/wear; WearBridge.kt): the game's state goes to the watch and its buttons come back,
    // phone to watch through Google Play services' Data Layer (never to our server). What they say is wear/link's.
    implementation(project(":wear:link"))
    implementation("com.google.android.gms:play-services-wearable:19.0.0")
    // The app's own audio and help text (assets/app/app.json, AppManifest.kt): read as the engine reads its maps, in
    // plain Kotlin, so the JVM tests read the real file too (Android's org.json is only a stub there).
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.6.3")
    debugImplementation("androidx.compose.ui:ui-tooling")
    implementation("androidx.compose.ui:ui-tooling-preview")

    // JVM tests (app/src/test): what needs no phone, such as the settings and the mic policy.
    testImplementation("junit:junit:4.13.2")
    // Compose UI tests on a phone or the emulator (app/src/androidTest), with Android's accessibility checks; the
    // test manifest gives them an activity to show screens in (debug builds only).
    androidTestImplementation(composeBom)
    androidTestImplementation("androidx.compose.ui:ui-test-junit4")
    androidTestImplementation("androidx.compose.ui:ui-test-junit4-accessibility")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    androidTestImplementation("androidx.test:runner:1.6.2")
    debugImplementation("androidx.compose.ui:ui-test-manifest")
}
