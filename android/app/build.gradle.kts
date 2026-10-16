import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing is resolved from, in order of preference:
//
//   1. `android/key.properties` — a git-ignored local file for the developer.
//   2. Environment variables — this is what CI injects from GitHub Secrets,
//      so the keystore itself never has to exist in the repository.
//
// When none of them are present the release build simply stays unsigned
// instead of silently falling back to the debug key, because a debug-signed
// artifact that claims to be a release is how users end up with an app they
// cannot upgrade.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
}

fun signingSecret(name: String): String? =
    keystoreProperties.getProperty(name)?.takeIf { it.isNotBlank() }
        ?: System.getenv(name)?.takeIf { it.isNotBlank() }

android {
    namespace = "dev.omniclean.omni_clean_engine"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "dev.omniclean.omni_clean_engine"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            val storeFilePath = signingSecret("OMNICLEAN_KEYSTORE_PATH")
            val storePasswordValue = signingSecret("OMNICLEAN_KEYSTORE_PASSWORD")
            val keyAliasValue = signingSecret("OMNICLEAN_KEY_ALIAS")
            val keyPasswordValue = signingSecret("OMNICLEAN_KEY_PASSWORD")

            signingConfig = if (
                storeFilePath != null &&
                storePasswordValue != null &&
                keyAliasValue != null &&
                keyPasswordValue != null
            ) {
                signingConfigs.create("release") {
                    storeFile = file(storeFilePath)
                    storePassword = storePasswordValue
                    keyAlias = keyAliasValue
                    keyPassword = keyPasswordValue
                    // Every scheme, not just the modern default. The Android
                    // Gradle Plugin only turns v1 on when minSdk < 24, but a
                    // meaningful share of sideloading paths — OEM file-manager
                    // installers in particular — still look for the JAR
                    // signature in META-INF before they will accept a package.
                    // Signing with all three costs a few kilobytes and removes
                    // the whole class of "the package appears invalid" reports.
                    enableV1Signing = true
                    enableV2Signing = true
                    enableV3Signing = true
                }
            } else {
                logger.info(
                    "OmniClean: no release keystore configured — " +
                        "building an unsigned artifact. Set OMNICLEAN_KEYSTORE_PATH, " +
                        "OMNICLEAN_KEYSTORE_PASSWORD, OMNICLEAN_KEY_ALIAS and " +
                        "OMNICLEAN_KEY_PASSWORD (or android/key.properties) to sign.",
                )
                null
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
