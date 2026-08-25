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
        }
    }

    buildFeatures { compose = true }

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
}

dependencies {
    implementation(project(":core:designsystem"))
    implementation(project(":core:model"))
    implementation(project(":feature:library"))
    implementation(project(":feature:reader"))
    implementation(project(":feature:epubreader"))
    coreLibraryDesugaring(libs.desugar.jdk.libs)
    implementation(project(":core:persistence"))

    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.activity.compose)
    // viewModel(), to hand the library screen its state holder. :feature:library
    // already depends on this; the app needs it to construct one.
    implementation(libs.androidx.lifecycle.viewmodel.compose)

    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.material3)
    debugImplementation(libs.androidx.compose.ui.tooling)

    testImplementation(libs.junit)
    androidTestImplementation(libs.androidx.test.junit)
    androidTestImplementation(platform(libs.androidx.compose.bom))
    androidTestImplementation(libs.androidx.compose.ui.test.junit4)
    debugImplementation(libs.androidx.compose.ui.test.manifest)
}
