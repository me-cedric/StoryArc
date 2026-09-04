plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.compose)
}

android {
    namespace = "app.storyarc.core.designsystem"
    compileSdk = 37
    defaultConfig { minSdk = 31 }

    buildFeatures { compose = true }

    // Robolectric composes against real resources, and a Material component that cannot
    // resolve a theme attribute throws rather than degrading.
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
    // The compact bar's claims are layout claims — that it does not displace the
    // navigation control, that its height returns to the content when it is absent, that
    // it grows rather than truncating at the largest text size. None of those is
    // answerable by asserting a composable was called, and the unit gate has no device to
    // compose on. The same trade `:feature:settings` and `:feature:library` already make.
    testImplementation(libs.robolectric)
    testImplementation(libs.androidx.compose.ui.test.junit4)
    // The `ComponentActivity` the compose rule launches into. Without it Robolectric has
    // no activity to resolve and every test in the suite fails at the rule.
    testImplementation(libs.androidx.compose.ui.test.manifest)
    testImplementation(platform(libs.androidx.compose.bom))
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

    // `ArcStopsAreNotChromeTest` reads **every** module's main sources, not just this
    // one's: the rule it enforces is that the mark's later arc stops never reach a chrome
    // accent, and the controls that would break it live in `:feature:*` and `:app`. So the
    // Android root is handed over the same way the module directory above is, and for the
    // same reason — a walk that climbs looking for a marker leaves this checkout.
    systemProperty("storyarc.android.rootDir", rootDir.absolutePath)
    // And every file it reads is declared an input. Without this the task is UP-TO-DATE
    // after a change in another module, so a violation added to `:feature:library` would
    // not re-run the guard that exists to catch it — the same hole the note above
    // describes, one module wider.
    //
    // The pattern is depth-independent, because the three globs it replaced
    // (`app/`, `core/*/`, `feature/*/`) matched exactly one directory level and the sweep
    // matches none: a nested module — `core/net/http` — would be read by the guard and
    // declared by nobody, which is this same UP-TO-DATE hole one level further down.
    // `build` is excluded because generated sources are not what the guard is auditing and
    // the sweep prunes them too.
    inputs.files(
        fileTree(rootDir) {
            include("**/src/main/**/*.kt")
            exclude("**/build/**")
        },
    )
        .withPropertyName("arcStopsGuardSources")
        .withPathSensitivity(PathSensitivity.RELATIVE)
}
