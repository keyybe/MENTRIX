plugins {
    kotlin("jvm")
    kotlin("plugin.serialization")
    application
}

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}

kotlin {
    compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) }
}

application {
    mainClass.set("kg.aimentor.server.ApplicationKt")
}

val ktor = "2.3.12"

dependencies {
    implementation(project(":shared"))
    implementation("io.ktor:ktor-server-core:$ktor")
    implementation("io.ktor:ktor-server-netty:$ktor")
    implementation("io.ktor:ktor-server-content-negotiation:$ktor")
    implementation("io.ktor:ktor-server-status-pages:$ktor")
    implementation("io.ktor:ktor-server-auth:$ktor")
    implementation("io.ktor:ktor-server-auth-jwt:$ktor")
    // хранение данных
    implementation("org.postgresql:postgresql:42.7.14")
    implementation("com.zaxxer:HikariCP:5.1.0")
    implementation("io.ktor:ktor-serialization-kotlinx-json:$ktor")
    // клиент нужен для запросов к внешней модели ИИ (HttpLlm)
    implementation("io.ktor:ktor-client-core:$ktor")
    implementation("io.ktor:ktor-client-cio:$ktor")
    implementation("io.ktor:ktor-client-content-negotiation:$ktor")
    implementation("ch.qos.logback:logback-classic:1.5.8")

    testImplementation(kotlin("test"))
    testImplementation("io.ktor:ktor-server-test-host:$ktor")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.8.1")
}

tasks.test { useJUnitPlatform() }

// ./gradlew :server:run – локальная разработка: вход без Google разрешён.
// В Docker и на хостинге сервер запускается из installDist, и эта настройка там не действует.
tasks.named<JavaExec>("run") {
    environment("AUTH_DEV", System.getenv("AUTH_DEV") ?: "true")
}

// Проверка ссылок из sources.json (ходит в интернет): ./gradlew :server:checkLinks
tasks.register<JavaExec>("checkLinks") {
    group = "verification"
    description = "Проверяет, что все ссылки в sources.json открываются"
    classpath = sourceSets["main"].runtimeClasspath
    mainClass.set("kg.aimentor.server.LinkCheckKt")
}
