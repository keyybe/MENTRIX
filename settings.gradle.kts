pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
plugins {
    id("org.gradle.toolchains.foojay-resolver-convention") version "1.0.0"
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}
rootProject.name = "ai-mentor-mvp"
include(":shared", ":server")
// В Docker сервер собирается без Android SDK, поэтому модуль приложения там не подключаем
if (System.getenv("SERVER_ONLY") == null) include(":app")
