import javax.inject.Inject

plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.compose)
}

// Reflowable EPUB rendering, in its own module.
//
// ADR-0005 puts Readium behind reflowable text, and Readium's EPUB navigator is a
// Fragment. Keeping it here means `:feature:reader` — which is Compose all the way
// down and renders comics and PDFs — never acquires a Fragment dependency, and the
// heaviest dependency in the app sits behind one screen. iOS splits this the same
// way, into its own SwiftPM package.
android {
    namespace = "app.storyarc.feature.epubreader"
    compileSdk = 37
    defaultConfig { minSdk = 31 }

    buildFeatures { compose = true }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
        // Readium's AAR metadata demands it, and this module's own test APK is a
        // standalone artifact — `:app` enabling it does not reach here.
        isCoreLibraryDesugaringEnabled = true
    }

    kotlin {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_21)
            allWarningsAsErrors.set(true)
        }
    }
}

// The bundled typefaces live in `packages/fonts`, one copy read by both apps.
//
// Staged rather than pointed at: an `assets.srcDir` on that directory would also
// package its README, its build script and its SwiftPM manifest. Copying only the
// shippable files keeps the APK to what Readium actually serves, and puts them under
// `fonts/` where its `servedAssets` pattern expects them.
abstract class StageFonts : DefaultTask() {
    @get:InputDirectory
    abstract val source: DirectoryProperty

    @get:OutputDirectory
    abstract val outputDirectory: DirectoryProperty

    @get:Inject
    abstract val files: FileSystemOperations

    @TaskAction
    fun stage() {
        files.sync {
            from(source) { include("*.ttf", "OFL-*.txt") }
            into(outputDirectory.dir("fonts"))
        }
    }
}

val stageFonts = tasks.register<StageFonts>("stageFonts") {
    source.set(rootProject.layout.projectDirectory.dir("../../packages/fonts"))
}

// Registered through the variant API rather than as a plain source directory. That
// is what makes every consumer — asset merging, lint's model, packaging — depend on
// the staging task without each one having to be named.
androidComponents {
    onVariants { variant ->
        variant.sources.assets?.addGeneratedSourceDirectory(stageFonts, StageFonts::outputDirectory)
    }
}

// `ReaderChromeWiringTest` guards one line of this module's source by reading it as
// text, so the test JVM is handed the path rather than left to find it. Discovery by
// walking up from the working directory escapes the module: this repository nests agent
// worktrees at `.claude/worktrees/<name>/`, so the walk climbs out of the worktree under
// test and reads the parent checkout's copy of a file that was never built here.
// Declaring the file as an input is the other half. A `Test` task's inputs are its
// classpath and its candidate classes, never the module's Kotlin sources, so nothing
// otherwise ties this task's up-to-date check to the file the test opens and reads.
// `:core:format` hands its fixture corpus to its own tests the same way.
tasks.withType<Test>().configureEach {
    systemProperty("storyarc.epubreader.projectDir", projectDir.absolutePath)
    // `inputs.files` rather than `inputs.file`: the guarded file going missing should reach
    // the test, which says what it was looking for, rather than failing input snapshotting
    // with a path and no explanation.
    inputs.files(
        layout.projectDirectory.file(
            "src/main/kotlin/app/storyarc/feature/epubreader/EpubReaderActivity.kt",
        ),
    )
        .withPropertyName("readerChromeWiringSource")
        .withPathSensitivity(PathSensitivity.RELATIVE)
    // `SolidArchiveHasNoNoticeTest` asserts an *absence* across this module's whole source
    // tree, so the tree itself is the input: this guard is only worth having if adding a file
    // re-runs it. `:feature:reader` declares its twin the same way.
    inputs.files(layout.projectDirectory.dir("src/main/kotlin"))
        .withPropertyName("solidArchiveNoticeSources")
        .withPathSensitivity(PathSensitivity.RELATIVE)
}

dependencies {
    implementation(project(":core:designsystem"))
    implementation(project(":core:model"))
    implementation(project(":core:persistence"))
    // `api`, not `implementation`: `ReadAloudHost.session` is a `PlaybackSession`, and the
    // app module observes it to draw the compact bar. A type on a public signature has to
    // be on the consumer's compile classpath.
    api(project(":core:playback"))

    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.fragment)
    implementation(libs.androidx.compose.material.icons.extended)
    implementation(libs.androidx.lifecycle.viewmodel.compose)

    // The one thing none of the above can do: lay out XHTML as pages.
    implementation(libs.readium.shared)
    implementation(libs.readium.streamer)
    implementation(libs.readium.navigator)

    testImplementation(libs.junit)
    // The theme sheet's accessibility semantics are only observable through a
    // composition. `uiautomator dump` reports a Compose slider as an unnamed
    // SeekBar whatever its semantics say, so it cannot answer the question this
    // module has to answer: does a screen reader learn which axis it is on.
    coreLibraryDesugaring(libs.desugar.jdk.libs)

    androidTestImplementation(libs.androidx.test.junit)
    androidTestImplementation(platform(libs.androidx.compose.bom))
    androidTestImplementation(libs.androidx.compose.ui.test.junit4)
    debugImplementation(libs.androidx.compose.ui.test.manifest)
}
