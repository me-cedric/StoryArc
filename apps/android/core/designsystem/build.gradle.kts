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
    // The pane scaffolds. `api`, because `PaneAdaptedValue` and the scaffold's own scope
    // appear in this module's surface: a caller drawing two panes names them.
    api(libs.androidx.compose.material3.adaptive.layout)
    // Two glyphs, both this module's own: the rail's menu button, open and shut. A
    // destination's icon still arrives from the app — what a destination *is* belongs
    // there — but the control that opens the rail is chrome, and chrome is this module's.
    implementation(libs.androidx.compose.material.icons.extended)
    implementation(libs.androidx.compose.ui.tooling.preview)
    debugImplementation(libs.androidx.compose.ui.tooling)

    testImplementation(libs.junit)
}

// `AdaptiveNavigationTest` reads this module's own source to check that the bar's icon
// position and arrangement are actually *passed*, not merely computed correctly — the two
// property assertions beside it stay green if both arguments are deleted from the call site.
//
// The path is handed over rather than discovered, for the reason `:feature:epubreader`
// records at length: walking up from the working directory escapes the module, because this
// repository nests agent worktrees at `.claude/worktrees/<name>/`, and the walk then reads
// the parent checkout's copy of a file that was never built here.
//
// Declaring the file as an input is the other half. A `Test` task's inputs are its classpath
// and its candidate classes, never the module's Kotlin sources, so nothing otherwise ties
// this task's up-to-date check to the file the test opens and reads.
tasks.withType<Test>().configureEach {
    systemProperty("storyarc.designsystem.projectDir", projectDir.absolutePath)
    // `inputs.files` rather than `inputs.file`: the guarded file going missing should reach
    // the test, which says what it was looking for, rather than failing input snapshotting
    // with a path and no explanation.
    inputs.files(
        layout.projectDirectory.file(
            "src/main/kotlin/app/storyarc/core/designsystem/navigation/AdaptiveNavigation.kt",
        ),
    )
        .withPropertyName("adaptiveNavigationWiringSource")
        .withPathSensitivity(PathSensitivity.RELATIVE)
}
