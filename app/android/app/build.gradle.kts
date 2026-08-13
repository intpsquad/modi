// Kotlin DSL 스크립트에서 `java`는 Gradle의 JavaPluginExtension을 가리켜 java.util 패키지 경로를
// 그대로 쓸 수 없다. 그래서 명시적으로 import한다.
import java.io.FileInputStream
import java.util.Base64
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // google-services.json 필요(Firebase 콘솔에서 다운로드해 이 디렉터리에 배치) — specs/0001-architecture.md 인증 스파이크.
    id("com.google.gms.google-services")
}

// --- API_BASE_URL 단일 진실 ---
// Flutter는 `--dart-define`/`--dart-define-from-file`로 받은 값들을 base64 CSV로 묶어
// `-Pdart-defines=...`로 Gradle에 넘긴다(flutter_tools/lib/src/build_info.dart:412).
// 그걸 여기서 디코드해 BuildConfig에 심으면, Dart(Env.apiBaseUrl)와 Kotlin(ShareActivity)이
// 커맨드라인 한 곳에서 같은 값을 받는다 — 주소를 두 군데 하드코딩할 필요가 없다.
// 값 파일은 `app/env/dev.json`(로컬 전용, README "로컬 전용 파일" 참고).
val dartDefines: Map<String, String> =
    (project.findProperty("dart-defines") as String?)
        ?.split(",")
        ?.filter { it.isNotBlank() }
        ?.mapNotNull { entry ->
            String(Base64.getDecoder().decode(entry), Charsets.UTF_8)
                .split("=", limit = 2)
                .takeIf { it.size == 2 }
                ?.let { it[0] to it[1] }
        }?.toMap()
        ?: emptyMap()

// release에 주소를 안 넘기면 에뮬레이터 기본값(10.0.2.2)이 그대로 배포되므로 빌드를 실패시킨다.
val isReleaseBuild = gradle.startParameter.taskNames.any { it.contains("Release", ignoreCase = true) }
if (isReleaseBuild && !dartDefines.containsKey("API_BASE_URL")) {
    throw GradleException(
        "release 빌드에는 API_BASE_URL이 필요하다(기본값 http://10.0.2.2:8080은 에뮬레이터 전용). " +
            "예: flutter build apk --release --dart-define-from-file=env/prod.json",
    )
}

// 기본값은 에뮬레이터 기준. app/lib/config/env.dart의 기본값과 반드시 같게 유지한다.
val apiBaseUrl: String = dartDefines["API_BASE_URL"] ?: "http://10.0.2.2:8080"
val kakaoNativeAppKey: String =
    dartDefines["KAKAO_NATIVE_APP_KEY"] ?: "YOUR_KAKAO_NATIVE_APP_KEY"

// --- release 서명 ---
// 실제 키스토어·비밀번호는 여기 없다 — `app/android/key.properties`(로컬 전용, .gitignore·
// README "로컬 전용 파일" 참고, 템플릿은 `key.properties.example`)의 경로만 읽는다. 그 파일이
// 없으면(release 키스토어를 아직 안 만든 개발자 PC, 또는 이 파일이 없는 CI) 기존과 동일하게 debug
// 키로 폴백해 `flutter run --release`가 계속 되게 한다.
// ⚠️ 출시 대상은 iOS 뿐이다(2026-08-13) — 안드로이드는 CI·릴리스 경로가 없어 이 블록은 지금
// 아무도 쓰지 않는다. 되살릴 때 `keytool -genkey`로 키스토어를 만든다.
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
val keystoreProperties = Properties()
if (hasReleaseKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.nomara.modi.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications가 core library desugaring을 요구한다(알림 스케줄 등 java.time 사용).
        isCoreLibraryDesugaringEnabled = true
    }

    // S-25-D ShareActivity(Kotlin)는 Dart의 --dart-define을 직접 못 읽어 BuildConfig로 노출한다.
    buildFeatures {
        buildConfig = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.intpsquad.modi"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        buildConfigField("String", "API_BASE_URL", "\"$apiBaseUrl\"")
        manifestPlaceholders["KAKAO_NATIVE_APP_KEY"] = kakaoNativeAppKey
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // release 키스토어(`key.properties`)가 있으면 그걸로, 없으면 debug 키로 서명한다
            // (그래야 release 키스토어 없는 개발자 PC에서도 `flutter run --release`가 된다).
            signingConfig =
                if (hasReleaseKeystore) {
                    signingConfigs.getByName("release")
                } else {
                    signingConfigs.getByName("debug")
                }
        }
    }
}

dependencies {
    // ShareActivity가 로그인 세션을 읽기 위해 필요 — firebase_auth Flutter 플러그인은 이 의존성을
    // implementation 스코프로만 물고 있어 :app 컴파일 클래스패스에는 노출되지 않는다.
    implementation(platform("com.google.firebase:firebase-bom:33.16.0"))
    implementation("com.google.firebase:firebase-auth")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("com.google.android.material:material:1.12.0")

    // 네이티브 공유 경로(ShareActivity)의 순수 로직을 기기 없이 검증하기 위한 것.
    // ⚠️ **CI 는 이걸 안 돌린다** — `.github/workflows/ci.yml` 의 app 잡은 `flutter analyze`·
    // `flutter test` 만 돌리고 Gradle 유닛테스트는 부르지 않는다. 로컬에서 돌린다:
    //     cd app/android && ./gradlew :app:testDebugUnitTest
    // CI 공백은 specs/OPEN.md 에 올려뒀다.
    testImplementation("junit:junit:4.13.2")

    // flutter_local_notifications 요구사항 — core library desugaring 런타임.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
