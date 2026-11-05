plugins {
    id("com.android.application")
    kotlin("plugin.compose")
    kotlin("plugin.serialization")
}

// Адрес боевого сервера и Web Client ID из Google Cloud задаются в gradle.properties
// (лучше в ~/.gradle/gradle.properties, чтобы не попали в репозиторий):
//   aimentor.serverUrl=https://api.example.com/
//   aimentor.googleClientId=1234567890-xxxx.apps.googleusercontent.com
val serverUrl = providers.gradleProperty("aimentor.serverUrl").getOrElse("https://api.example.com/")
val googleClientId = providers.gradleProperty("aimentor.googleClientId").getOrElse("")

android {
    namespace = "kg.aimentor.app"
    compileSdk = 37 // нужен свежим библиотекам Compose

    defaultConfig {
        applicationId = "kg.aimentor.app"
        minSdk = 26 // Android 8.0, как в ТЗ
        targetSdk = 36
        versionCode = 1
        versionName = "0.1"
        buildConfigField("String", "GOOGLE_CLIENT_ID", "\"$googleClientId\"")
    }

    buildTypes {
        debug {
            // 10.0.2.2 – это localhost компьютера, если приложение запущено в эмуляторе
            buildConfigField("String", "BASE_URL", "\"http://10.0.2.2:8080/\"")
        }
        release {
            buildConfigField("String", "BASE_URL", "\"$serverUrl\"")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }
}

val ktor = "2.3.12"

dependencies {
    implementation(project(":shared"))

    implementation(platform("androidx.compose:compose-bom:2026.09.00"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-text-google-fonts") // шрифт Nunito без файлов в APK
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.compose.ui:ui-tooling-preview")
    debugImplementation("androidx.compose.ui:ui-tooling")

    implementation("androidx.activity:activity-compose:1.13.0")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.11.0")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.11.0")

    // вход через Google
    implementation("androidx.credentials:credentials:1.6.0")
    implementation("androidx.credentials:credentials-play-services-auth:1.6.0")
    implementation("com.google.android.libraries.identity.googleid:googleid:1.2.1")

    // ежедневные напоминания
    implementation("androidx.work:work-runtime-ktx:2.12.0")

    implementation("io.ktor:ktor-client-android:$ktor")
    implementation("io.ktor:ktor-client-content-negotiation:$ktor")
    implementation("io.ktor:ktor-serialization-kotlinx-json:$ktor")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.11.0")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.11.0")
}
