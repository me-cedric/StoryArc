plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.roborazzi)
}

android {
    namespace = "app.storyarc.feature.reader"
    compileSdk = 37
    defaultConfig { minSdk = 31 }

    buildFeatures { compose = true }

    // Robolectric, so `ReaderViewModelScrollOffsetTest` can build a `ReaderViewModel`
    // against a real `ContentResolver` rather than one this module has no framework
    // to construct on the host otherwise.
    testOptions { unitTests { isIncludeAndroidResources = true } }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }

    kotlin {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_21)
            allWarningsAsErrors.set(true)
        }
    }
}

// `SolidArchiveHasNoNoticeTest` asserts an *absence* across this module's whole source tree,
// so the test JVM is handed the module directory rather than left to find it. Discovery by
// walking up from the working directory escapes the module: this repository nests agent
// worktrees at `.claude/worktrees/<name>/`, so the walk climbs out of the worktree under test
// and reads the parent checkout's sources. `:feature:library` and `:feature:epubreader` hand
// their own guards a path the same way.
//
// The source directory is declared an input as well. A `Test` task's inputs are its classpath
// and its candidate classes, never the module's Kotlin sources, so nothing otherwise ties this
// task's up-to-date check to the tree it reads — and this guard is only worth having if adding
// a file re-runs it.
tasks.withType<Test>().configureEach {
    systemProperty("storyarc.reader.projectDir", projectDir.absolutePath)
    inputs.files(layout.projectDirectory.dir("src/main/kotlin"))
        .withPropertyName("solidArchiveNoticeSources")
        .withPathSensitivity(PathSensitivity.RELATIVE)
}

roborazzi { outputDir.set(layout.projectDirectory.dir("src/test/snapshots")) }

dependencies {
    implementation(project(":core:designsystem"))
    implementation(project(":core:model"))
    implementation(project(":core:persistence"))
    implementation(project(":core:format"))
    implementation(project(":core:smb"))
    // D18: opening a comic or a PDF has to silence a voice already speaking, through the one
    // authority both engines answer to. `:feature:epubreader` already depends on this module
    // and never the reverse — see `SpokenAudio`'s own header.
    implementation(project(":core:playback"))

    // `LocalActivity`, to hold the screen at one orientation. `comic-reader`'s lock is
    // an activity-level request and there is nowhere else in Compose to make it.
    implementation(libs.androidx.activity.compose)
    // `WindowInsetsControllerCompat`, to take the system bars away with the chrome. It
    // arrives transitively through the line above; declared here because this module
    // calls it, and a transitive it happens to get is not a dependency it has.
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.compose.material.icons.extended)
    implementation(libs.androidx.compose.ui.tooling.preview)
    debugImplementation(libs.androidx.compose.ui.tooling)

    testImplementation(libs.junit)
    testImplementation(project(":core:snapshots"))
    testImplementation(libs.robolectric)
    // A composition on the JVM, so the unit gate can ask what a screen reader is offered.
    // `PageTurnSemanticsTest` asks whether the page surface carries the two named turns and
    // a live region on the position, and semantics are only observable in a laid-out tree.
    // `:feature:epubreader`, `:core:designsystem` and `:app` carry the same three.
    testImplementation(platform(libs.androidx.compose.bom))
    testImplementation(libs.androidx.compose.ui.test.junit4)
    // The `ComponentActivity` the compose rule launches into. Without it Robolectric has no
    // activity to resolve and every test using the rule fails at the rule.
    testImplementation(libs.androidx.compose.ui.test.manifest)
}
