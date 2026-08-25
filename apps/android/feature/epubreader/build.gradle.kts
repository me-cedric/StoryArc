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
