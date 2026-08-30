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
    // jcifs-ng was built against BouncyCastle 1.76 and parses the SPNEGO tokens the
    // server chooses with it. 1.76 is inside CVE-2025-8885, so it is raised here rather
    // than added as a dependency: no source in this module imports BouncyCastle, and
    // declaring it would say otherwise. jcifs-ng touches only long-stable ASN.1, HMAC
    // and KDF APIs, so the newer artifact is a drop-in.
    constraints {
        implementation(libs.bouncycastle.bcprov) {
            because("CVE-2025-8885: unbounded allocation parsing a server's SPNEGO ASN.1 object identifier")
        }
    }

    api(project(":core:format"))
    implementation(libs.jcifs.ng)
    implementation(libs.kotlinx.coroutines.core)

    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
}
