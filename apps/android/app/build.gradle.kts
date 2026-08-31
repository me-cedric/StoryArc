plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
}

android {
    namespace = "app.storyarc"
    compileSdk = 37

    defaultConfig {
        applicationId = "app.storyarc"
        // ADR-0003: API 31 is the floor because that is where dynamic colour
        // starts. Compose renders Material 3 Expressive identically below 36.
        minSdk = 31
        targetSdk = 37
        versionCode = 1
        versionName = "0.1.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    // `localization`: only the four supported languages are packaged.
    androidResources {
        localeFilters += listOf("en", "fr", "de", "es")
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            // No signing config yet — see README. Release builds are unsigned.
        }
        debug {
            applicationIdSuffix = ".debug"
            // `localization` asks for the interface to survive "an expanded pseudo-locale".
            // Without this the `en-XA` resources are never generated, so setting the device
            // to en-XA falls back to English and the test passes without testing anything.
            // Debug only: the pseudo-locales are a development aid and would be dead weight
            // in a release APK.
            isPseudoLocalesEnabled = true
        }
    }

    buildFeatures { compose = true }

    // Robolectric composes real widgets, and this module's cells reach for string resources.
    // `:feature:library` carries the same line for the same reason.
    testOptions { unitTests { isIncludeAndroidResources = true } }

    lint {
        lintConfig = file("lint.xml")
        warningsAsErrors = true
        abortOnError = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
        // Required by Readium, which states it in its AAR metadata rather than
        // leaving it to be discovered at runtime. It backfills java.time and
        // friends on API levels that lack them.
        isCoreLibraryDesugaringEnabled = true
    }

    kotlin {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_21)
            // Warnings are errors so the codebase never accumulates a tolerated tail.
            allWarningsAsErrors.set(true)
        }
    }

    bundle {
        language {
            // Every language ships in the base install. `localization` lets a reader choose
            // one from inside the app, and a bundle split by language delivers only the
            // device's own -- the other three would resolve to English on a device that
            // never asked for them.
            enableSplit = false
        }
    }
}

dependencies {
    implementation(project(":core:designsystem"))
    implementation(project(":core:model"))
    // Added for the open-in flow. The system hands the app a `Uri` and the app layer is
    // where routing lives, so the app is what has to decide what those bytes are.
    implementation(project(":core:format"))
    implementation(project(":feature:library"))
    implementation(project(":feature:reader"))
    implementation(project(":feature:epubreader"))
    implementation(project(":feature:settings"))
    coreLibraryDesugaring(libs.desugar.jdk.libs)
    implementation(project(":core:persistence"))
    implementation(project(":core:catalogue"))
    implementation(project(":core:kavita"))
    implementation(project(":core:smb"))

    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.activity.compose)
    // viewModel(), to hand the library screen its state holder. :feature:library
    // already depends on this; the app needs it to construct one.
    implementation(libs.androidx.lifecycle.viewmodel.compose)

    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.material3)
    // The three destinations' own glyphs. Already in the APK by way of :feature:library;
    // the app needs the compile dependency to name them.
    implementation(libs.androidx.compose.material.icons.extended)
    debugImplementation(libs.androidx.compose.ui.tooling)

    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
    // A composition on the JVM, so this module's own cells can be asserted in the unit gate.
    //
    // `ShelvesDrawOneWellTest` and `CoverlessWellTest` both used to say, correctly, that
    // `:app` declared neither Robolectric nor a Compose test rule — which is why the shelf the
    // coverless-well defect was actually *reported* on had nothing but a source grep behind
    // it, and why a mutation reinstating the blank well passed the whole suite. The same five
    // declarations `:feature:library` already carried, plus the `isIncludeAndroidResources`
    // line above.
    testImplementation(libs.robolectric)
    testImplementation(libs.androidx.test.junit)
    testImplementation(platform(libs.androidx.compose.bom))
    testImplementation(libs.androidx.compose.ui.test.junit4)
    testImplementation(libs.androidx.compose.ui.test.manifest)
    androidTestImplementation(libs.androidx.test.junit)
    androidTestImplementation(platform(libs.androidx.compose.bom))
    androidTestImplementation(libs.androidx.compose.ui.test.junit4)
    debugImplementation(libs.androidx.compose.ui.test.manifest)
}

/*
 * `ShelvesAskOneRuleTest` reads Kotlin source, so Kotlin source is one of its inputs.
 *
 * Gradle knows nothing about a file a test opens by path: it tracks the classpath, and every
 * module's *test* sources are outside `:app`'s. So appending the cover ladder to, say,
 * `:core:designsystem`'s test sources left `:app:testDebugUnitTest` UP-TO-DATE with the
 * assertion violated — reproduced, and it is what this declaration fixes. Declaring the tree
 * makes the task re-run when any of it changes, which is the only thing that makes the test's
 * own promise — that it fails the moment a shelf stops asking — true on an incremental build.
 *
 * The tree is the same one the test walks: every `.kt` under the Gradle root, `build/`
 * excluded because it holds generated and copied sources nothing a reviewer writes.
 * Relative path sensitivity, so moving the checkout does not invalidate it.
 */
tasks.withType<Test>().configureEach {
    inputs.files(
        fileTree(rootDir) {
            include("**/*.kt")
            exclude("**/build/**")
        },
    )
        .withPropertyName("androidKotlinSources")
        .withPathSensitivity(PathSensitivity.RELATIVE)
}
