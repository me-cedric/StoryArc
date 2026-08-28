plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.serialization)
}

android {
    namespace = "app.storyarc.core.catalogue"
    compileSdk = 37
    defaultConfig { minSdk = 31 }

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

    testOptions {
        // The Atom parser uses `org.xmlpull`, which is an Android API with no JVM
        // implementation. Unit tests need the real one rather than a stub that throws.
        unitTests.isReturnDefaultValues = false
    }
}

dependencies {
    implementation(project(":core:model"))
    implementation(libs.kotlinx.coroutines.core)
    api(libs.kotlinx.serialization.json)

    testImplementation(libs.junit)
    // A working XmlPullParser on the JVM, so the Atom parser can be tested without a
    // device. Android ships the same implementation.
    testImplementation("xmlpull:xmlpull:1.1.3.1")
    testImplementation("net.sf.kxml:kxml2:2.3.0")
}
