plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.compose)
}

android {
    namespace = "app.storyarc.core.designsystem"
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
    // `api`, because `AppearanceMode` is part of this module's surface: a caller
    // theming the app has to name one.
    api(project(":core:model"))

    // `PredictiveBackHandler` lives here. `native-experience` asks for predictive back,
    // and the design system is where the gesture's transform belongs — every screen that
    // can be left uses the same one.
    implementation(libs.androidx.activity.compose)
    implementation(libs.kotlinx.coroutines.core)

    api(platform(libs.androidx.compose.bom))
    api(libs.androidx.compose.ui)
    api(libs.androidx.compose.ui.graphics)
    api(libs.androidx.compose.material3)
    // The navigation shell and the window measurement it adapts on. `api`, because
    // `NavigationSuiteType` appears in this module's own surface: a caller asking for
    // the adaptive shell names one.
    api(libs.androidx.compose.material3.adaptive.navigation.suite)
    api(libs.androidx.compose.material3.adaptive)
    implementation(libs.androidx.compose.ui.tooling.preview)
    debugImplementation(libs.androidx.compose.ui.tooling)

    testImplementation(libs.junit)
}
