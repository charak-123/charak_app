import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Upload-key credentials. Kept out of git (see android/.gitignore): a release
// build needs key.properties beside this module, created from
// key.properties.example. Without it a release *APK* (`flutter run --release`
// on a test phone) falls back to the debug key, but a release *App Bundle* —
// the only thing that goes to Play — refuses to build: see the guard at the
// bottom of this file.
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) load(FileInputStream(f))
}

android {
    namespace = "com.charak.doctor_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications (which re-raises foreground pushes) uses
        // java.time, so the build fails without desugaring on our minSdk.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Permanent once published to Play; Firebase/Google Sign-In are registered against it.
        applicationId = "com.charak.doctor_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // flutter_secure_storage's EncryptedSharedPreferences (AES) backend
        // requires API 23; raise the floor from Flutter's default accordingly.
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = (keystoreProperties["storeFile"] as String?)?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

    buildTypes {
        release {
            // Debug keys only when there is no upload key on this machine, so a
            // local `flutter run --release` still works. A real release build
            // must have key.properties present.
            signingConfig = if (keystoreProperties.isEmpty) {
                signingConfigs.getByName("debug")
            } else {
                signingConfigs.getByName("release")
            }
            isMinifyEnabled = true
            isShrinkResources = true
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.2")
}

flutter {
    source = "../.."
}

// Never produce a Play upload signed with the debug key. Every machine's debug
// key is different and public-by-convention, so a bundle signed with one is
// either rejected by Play or — sideloaded to a tester — installs as an app no
// real update can ever replace. APK builds are left alone for device testing.
gradle.taskGraph.whenReady {
    // This module's own bundle task only: plugin modules have release tasks
    // named bundle…Release too, and those run for APK builds.
    val bundlingRelease = allTasks.any { it.project == project && it.name == "bundleRelease" }
    if (bundlingRelease && keystoreProperties.isEmpty) {
        throw GradleException(
            "android/key.properties is missing, so this release App Bundle would be " +
            "signed with the debug key. Create it from key.properties.example first."
        )
    }
}
