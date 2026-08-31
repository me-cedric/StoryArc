import javax.inject.Inject

plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

android {
    namespace = "app.storyarc.feature.settings"
    compileSdk = 37
    defaultConfig { minSdk = 31 }

    buildFeatures { compose = true }

    // Robolectric composes real widgets, and a `FilterChip` label is a string resource.
    // Without the packaged resources on the unit-test classpath every label resolves to
    // nothing and a layout test measures empty chips.
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

// The licence inventory lives in `packages/licences`, one copy read by both apps.
//
// Staged rather than pointed at, for the reason `:feature:epubreader` stages the fonts:
// an `assets.srcDir` on that directory would also package its README. And staged at all
// rather than read from the repository, because BSD and Apache require the notice to
// travel with the *binary* — a notices file only a developer can see does not discharge
// that.
abstract class StageLicences : DefaultTask() {
    @get:InputDirectory
    abstract val source: DirectoryProperty

    @get:OutputDirectory
    abstract val outputDirectory: DirectoryProperty

    @get:Inject
    abstract val files: FileSystemOperations

    @TaskAction
    fun stage() {
        files.sync {
            from(source) { include("notices.json", "texts/*.txt") }
            into(outputDirectory.dir("licences"))
        }
    }
}

val stageLicences = tasks.register<StageLicences>("stageLicences") {
    source.set(rootProject.layout.projectDirectory.dir("../../packages/licences"))
}

// Through the variant API rather than as a plain source directory: that is what makes
// asset merging, lint's model and packaging all depend on the staging task without each
// one having to be named.
androidComponents {
    onVariants { variant ->
        variant.sources.assets?.addGeneratedSourceDirectory(
            stageLicences,
            StageLicences::outputDirectory,
        )
    }
}

dependencies {
    implementation(project(":core:designsystem"))
    implementation(project(":core:model"))
    implementation(project(":core:persistence"))

    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.compose.material.icons.extended)
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.androidx.compose.ui.tooling.preview)
    debugImplementation(libs.androidx.compose.ui.tooling)

    testImplementation(libs.junit)
    // A composition on the JVM, for layout claims the unit gate has to be able to check.
    // See `DownloadLimitWrapTest`.
    testImplementation(libs.robolectric)
    testImplementation(libs.androidx.test.junit)
    testImplementation(platform(libs.androidx.compose.bom))
    testImplementation(libs.androidx.compose.ui.test.junit4)
    testImplementation(libs.androidx.compose.ui.test.manifest)

    androidTestImplementation(libs.androidx.test.junit)
    androidTestImplementation(platform(libs.androidx.compose.bom))
    androidTestImplementation(libs.androidx.compose.ui.test.junit4)
    // Compose's ui-test pulls Espresso 3.5.0 transitively, which reflects on an
    // InputManager method API 36 removed — every test dies on a modern emulator
    // before it asks anything. The catalogue's version knows the new API.
    androidTestImplementation(libs.androidx.test.espresso.core)
    // The activity createComposeRule launches. Without it the test APK has no
    // manifest entry to resolve, and every test fails before composing anything.
    androidTestImplementation(libs.androidx.compose.ui.test.manifest)
}
