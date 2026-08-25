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

dependencies {
    implementation(project(":core:designsystem"))
    implementation(project(":core:model"))
    implementation(project(":core:persistence"))

    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.fragment)
    implementation(libs.androidx.compose.material.icons.extended)
    implementation(libs.androidx.lifecycle.viewmodel.compose)

    // The one thing none of the above can do: lay out XHTML as pages.
    implementation(libs.readium.shared)
    implementation(libs.readium.streamer)
    implementation(libs.readium.navigator)

    testImplementation(libs.junit)
}
