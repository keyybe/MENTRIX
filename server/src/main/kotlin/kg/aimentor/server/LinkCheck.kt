package kg.aimentor.server

import java.net.URI
import java.net.http.HttpClient
import java.net.http.HttpRequest
import java.net.http.HttpResponse
import java.time.Duration
import kotlin.system.exitProcess

// ./gradlew :server:checkLinks – открывает каждую ссылку из sources.json и падает, если какая-то не отвечает.
// Запускай перед релизом и время от времени: документация переезжает.
fun main() {
    val client = HttpClient.newBuilder()
        .followRedirects(HttpClient.Redirect.NORMAL)
        .connectTimeout(Duration.ofSeconds(10))
        .build()
    val broken = SourceBase.load().map { it.url }.distinct().mapNotNull { url ->
        val status = try {
            val req = HttpRequest.newBuilder(URI(url))
                .timeout(Duration.ofSeconds(20))
                .header("User-Agent", "ai-mentor-link-check")
                .GET()
                .build()
            client.send(req, HttpResponse.BodyHandlers.discarding()).statusCode()
        } catch (e: Exception) {
            -1
        }
        println("${if (status in 200..399) "OK  " else "FAIL"} $status $url")
        url.takeIf { status !in 200..399 }
    }
    if (broken.isNotEmpty()) {
        println("Не открываются: ${broken.size}")
        exitProcess(1)
    }
    println("Все ссылки в порядке")
}
