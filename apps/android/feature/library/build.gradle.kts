plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.compose)
}

android {
    namespace = "app.storyarc.feature.library"
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
    implementation(project(":core:format"))
    implementation(project(":core:catalogue"))
    implementation(project(":core:kavita"))
    implementation(project(":core:smb"))

    implementation(libs.androidx.lifecycle.viewmodel.compose)
    // rememberLauncherForActivityResult, for the folder picker. Android gives no
    // other way to reach a folder the user owns.
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.compose.material.icons.extended)
    // `SupportingPaneScaffold`, for the publication page on a wide window. The `adaptive`
    // half of the pair already arrives through the design system; the layout half is only
    // needed where a pane scaffold is actually drawn, which so far is here.
    implementation(libs.androidx.compose.material3.adaptive.layout)
    implementation(libs.androidx.compose.ui.tooling.preview)
    debugImplementation(libs.androidx.compose.ui.tooling)

    testImplementation(libs.junit)
    // A working XmlPullParser on the JVM, so a feed can be parsed in a unit test without a
    // device. Android ships the same implementation; the catalogue declares the versions.
    testImplementation(libs.xmlpull)
    testImplementation(libs.kxml2)
}
