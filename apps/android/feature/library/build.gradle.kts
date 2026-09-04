plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.compose)
}

android {
    namespace = "app.storyarc.feature.library"
    compileSdk = 37
    defaultConfig { minSdk = 31 }

    buildFeatures { compose = true }

    // Robolectric composes real widgets, and a chip's label is a string resource. Without
    // the packaged resources on the unit-test classpath every label resolves to nothing and
    // a layout test measures empty chips.
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

// `SmbTransferWiringTest` guards the share browser's transfer by reading its source as text,
// so the test JVM is handed the path rather than left to find it. Discovery by walking up from
// the working directory escapes the module: this repository nests agent worktrees at
// `.claude/worktrees/<name>/`, so the walk climbs out of the worktree under test and reads the
// parent checkout's copy of a file that was never built here.
//
// Declaring the file as an input is the other half. A `Test` task's inputs are its classpath
// and its candidate classes, never the module's Kotlin sources, so nothing otherwise ties this
// task's up-to-date check to the file the test opens and reads. `:feature:epubreader` hands
// `ReaderChromeWiringTest` its own source over the same way.
tasks.withType<Test>().configureEach {
    systemProperty("storyarc.library.projectDir", projectDir.absolutePath)
    // `inputs.files` rather than `inputs.file`: the guarded file going missing should reach the
    // test, which says what it was looking for, rather than failing input snapshotting with a
    // path and no explanation.
    inputs.files(
        layout.projectDirectory.file(
            "src/main/kotlin/app/storyarc/feature/library/SmbBrowserScreen.kt",
        ),
    )
        .withPropertyName("smbTransferWiringSource")
        .withPathSensitivity(PathSensitivity.RELATIVE)
    // `LibrarySearchBarTest` reads this one for the same reason: which material3 API is called
    // with which state partner is not decidable from a JVM unit test that cannot compose a
    // `@Composable`, and two of the things it pins are *absences* — no clear affordance and no
    // back-icon API exist to call, so both are hand-written and nothing else would notice them
    // going.
    // Two files: the bar, and the screen that owns the `Scaffold` it is the top bar of. The
    // scroll behaviour has to be created by the screen — the scaffold's content is what reports
    // the scroll to it — so the assertion spans both.
    inputs.files(
        layout.projectDirectory.file(
            "src/main/kotlin/app/storyarc/feature/library/LibrarySearchBar.kt",
        ),
        layout.projectDirectory.file(
            "src/main/kotlin/app/storyarc/feature/library/SearchScreen.kt",
        ),
    )
        .withPropertyName("librarySearchBarWiringSource")
        .withPathSensitivity(PathSensitivity.RELATIVE)
    // And the screen again, for `BulkSelectionChromeTest`. Its other six tests compose
    // `LibrarySelectionTopBar` and ask the bar about itself; the two that matter here ask the
    // *screen* whether the two top bars can be up at once, which is a property of the
    // `Scaffold`'s slots and of neither bar. Reaching it by composition would need a view
    // model with a populated library before the first assertion — see the test's own note.
    inputs.files(
        layout.projectDirectory.file(
            "src/main/kotlin/app/storyarc/feature/library/LibraryScreen.kt",
        ),
    )
        .withPropertyName("bulkSelectionChromeSource")
        .withPathSensitivity(PathSensitivity.RELATIVE)
    // And the view model, for `SkippedScanTest`. Its other three tests walk a real folder of
    // real refused files; the fourth asks the view model the one thing a walk cannot show it,
    // which is that no scan path throws the walk's refusals away. There were two paths and
    // only one had been fixed.
    inputs.files(
        layout.projectDirectory.file(
            "src/main/kotlin/app/storyarc/feature/library/LibraryViewModel.kt",
        ),
    )
        .withPropertyName("skippedScanWiringSource")
        .withPathSensitivity(PathSensitivity.RELATIVE)
}

dependencies {
    implementation(project(":core:designsystem"))
    implementation(project(":core:model"))
    implementation(project(":core:persistence"))
    implementation(project(":core:format"))
    implementation(project(":core:catalogue"))
    implementation(project(":core:kavita"))
    implementation(project(":core:smb"))

    implementation(libs.androidx.lifecycle.viewmodel.compose)
    // rememberLauncherForActivityResult, for the folder picker. Android gives no
    // other way to reach a folder the user owns.
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.compose.material.icons.extended)
    // `SupportingPaneScaffold`, for the publication page on a wide window. The `adaptive`
    // half of the pair already arrives through the design system; the layout half is only
    // needed where a pane scaffold is actually drawn, which so far is here.
    implementation(libs.androidx.compose.material3.adaptive.layout)
    implementation(libs.androidx.compose.ui.tooling.preview)
    debugImplementation(libs.androidx.compose.ui.tooling)

    testImplementation(libs.junit)
    // `runTest`, for the two suspend decisions behind the share browser. See
    // `ShareOpeningTest`.
    testImplementation(libs.kotlinx.coroutines.test)
    // A composition on the JVM, for layout claims the unit gate has to be able to check.
    // See `ListOrderChipsWrapTest`.
    testImplementation(libs.robolectric)
    testImplementation(libs.androidx.test.junit)
    testImplementation(platform(libs.androidx.compose.bom))
    testImplementation(libs.androidx.compose.ui.test.junit4)
    testImplementation(libs.androidx.compose.ui.test.manifest)
    // A working XmlPullParser on the JVM, so a feed can be parsed in a unit test without a
    // device. Android ships the same implementation; the catalogue declares the versions.
    testImplementation(libs.xmlpull)
    testImplementation(libs.kxml2)
}
