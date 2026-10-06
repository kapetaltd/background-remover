import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Play upload key. CI passes it via environment variables (see
// .github/workflows/android.yml); locally, android/key.properties works too.
// Without either, release builds fall back to the debug key, which Google Play
// rejects, so `flutter run --release` still works for development.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}

fun signingValue(property: String, env: String): String? =
    System.getenv(env)?.takeIf { it.isNotBlank() } ?: keystoreProperties.getProperty(property)

val uploadStoreFile = signingValue("storeFile", "CUTOUT_UPLOAD_STORE_FILE")
val hasUploadKey = uploadStoreFile != null && file(uploadStoreFile).exists()

android {
    namespace = "com.kapetaltd.cutout"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.kapetaltd.cutout"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // ONNX Runtime for Android requires API 24+.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasUploadKey) {
            create("upload") {
                storeFile = file(uploadStoreFile!!)
                storePassword = signingValue("storePassword", "CUTOUT_UPLOAD_STORE_PASSWORD")
                keyAlias = signingValue("keyAlias", "CUTOUT_UPLOAD_KEY_ALIAS")
                keyPassword = signingValue("keyPassword", "CUTOUT_UPLOAD_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig =
                if (hasUploadKey) signingConfigs.getByName("upload")
                else signingConfigs.getByName("debug")
            // Keeps ONNX Runtime's JNI classes when R8 shrinking is enabled.
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
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
