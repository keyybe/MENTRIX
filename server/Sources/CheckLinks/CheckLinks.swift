import AsyncHTTPClient
import Foundation
import MentorServer

// swift run check-links – открывает каждую ссылку из sources.json и завершается с ошибкой, если какая-то не отвечает.
// Запускай перед релизом и время от времени: документация переезжает.
@main
enum CheckLinks {
    static func main() async throws {
        let urls = try SourceBase.load().map(\.url).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        var config = HTTPClient.Configuration()
        config.redirectConfiguration = .follow(max: 10, allowCycles: false)
        config.timeout = .init(connect: .seconds(10), read: .seconds(20))
        let client = HTTPClient(eventLoopGroupProvider: .singleton, configuration: config)

        var broken: [String] = []
        for url in urls {
            var request = HTTPClientRequest(url: url)
            request.headers.add(name: "User-Agent", value: "ai-mentor-link-check")
            let status: Int
            do {
                status = Int(try await client.execute(request, timeout: .seconds(20)).status.code)
            } catch {
                status = -1
            }
            let ok = (200..<400).contains(status)
            print("\(ok ? "OK  " : "FAIL") \(status) \(url)")
            if !ok { broken.append(url) }
        }
        try await client.shutdown()

        if !broken.isEmpty {
            print("Не открываются: \(broken.count)")
            exit(1)
        }
        print("Все ссылки в порядке")
    }
}
