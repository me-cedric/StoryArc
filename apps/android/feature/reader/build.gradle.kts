plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.compose)
}

android {
    namespace = "app.storyarc.feature.reader"
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

// `SolidArchiveHasNoNoticeTest` asserts an *absence* across this module's whole source tree,
// so the test JVM is handed the module directory rather than left to find it. Discovery by
// walking up from the working directory escapes the module: this repository nests agent
// worktrees at `.claude/worktrees/<name>/`, so the walk climbs out of the worktree under test
// and reads the parent checkout's sources. `:feature:library` and `:feature:epubreader` hand
// their own guards a path the same way.
//
// The source directory is declared an input as well. A `Test` task's inputs are its classpath
// and its candidate classes, never the module's Kotlin sources, so nothing otherwise ties this
// task's up-to-date check to the tree it reads — and this guard is only worth having if adding
// a file re-runs it.
tasks.withType<Test>().configureEach {
    systemProperty("storyarc.reader.projectDir", projectDir.absolutePath)
    inputs.files(layout.projectDirectory.dir("src/main/kotlin"))
        .withPropertyName("solidArchiveNoticeSources")
        .withPathSensitivity(PathSensitivity.RELATIVE)
}

dependencies {
    implementation(project(":core:designsystem"))
    implementation(project(":core:model"))
    implementation(project(":core:persistence"))
    implementation(project(":core:format"))

    // `LocalActivity`, to hold the screen at one orientation. `comic-reader`'s lock is
    // an activity-level request and there is nowhere else in Compose to make it.
    implementation(libs.androidx.activity.compose)
    // `WindowInsetsControllerCompat`, to take the system bars away with the chrome. It
    // arrives transitively through the line above; declared here because this module
    // calls it, and a transitive it happens to get is not a dependency it has.
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.compose.material.icons.extended)
    implementation(libs.androidx.compose.ui.tooling.preview)
    debugImplementation(libs.androidx.compose.ui.tooling)

    testImplementation(libs.junit)
}
