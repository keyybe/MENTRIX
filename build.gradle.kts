plugins {
    // AGP 9 компилирует Kotlin сам (built-in Kotlin), плагин kotlin-android больше не нужен
    id("com.android.application") version "9.5.1" apply false
    kotlin("jvm") version "2.4.21" apply false
    kotlin("plugin.serialization") version "2.4.21" apply false
    kotlin("plugin.compose") version "2.4.21" apply false
}
