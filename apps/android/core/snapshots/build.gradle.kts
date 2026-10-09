plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.compose)
}

// Test support for the screen catalogue (`lighter-visual-check`). No product module depends on
// this one except through `testImplementation`, so none of it reaches the APK.
android {
    namespace = "app.storyarc.core.snapshots"
    compileSdk = 37
    defaultConfig { minSdk = 31 }

    buildFeatures { compose = true }

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

dependencies {
    api(project(":core:designsystem"))

    api(libs.junit)
    api(libs.robolectric)
    api(libs.roborazzi)
    api(libs.roborazzi.compose)
    api(platform(libs.androidx.compose.bom))
    api(libs.androidx.compose.ui.test.junit4)

    // The `ComponentActivity` the compose rule launches into.
    testImplementation(libs.androidx.compose.ui.test.manifest)
}
