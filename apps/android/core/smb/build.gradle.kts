plugins {
    alias(libs.plugins.android.library)
}

android {
    namespace = "app.storyarc.core.smb"
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

    packaging {
        resources {
            // jcifs-ng and its logging facade each ship one, and two of the same file
            // is a packaging error rather than a choice to make.
            excludes += "META-INF/DEPENDENCIES"
        }
    }
}

dependencies {
    api(project(":core:format"))
    implementation(libs.jcifs.ng)
    implementation(libs.kotlinx.coroutines.core)

    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
}
