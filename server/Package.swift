// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MentorServer",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "mentor-server", targets: ["Server"]),
        .executable(name: "check-links", targets: ["CheckLinks"]),
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.115.0"),
        .package(url: "https://github.com/vapor/jwt-kit.git", from: "5.0.0"),
        .package(url: "https://github.com/vapor/postgres-nio.git", from: "1.25.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "4.0.0"),
        .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.24.0"),
    ],
    targets: [
        .target(
            name: "MentorServer",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "JWTKit", package: "jwt-kit"),
                .product(name: "PostgresNIO", package: "postgres-nio"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "CryptoExtras", package: "swift-crypto"),
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
            ],
            resources: [.copy("Resources/sources.json")]
        ),
        .executableTarget(name: "Server", dependencies: ["MentorServer"]),
        .executableTarget(
            name: "CheckLinks",
            dependencies: ["MentorServer", .product(name: "AsyncHTTPClient", package: "async-http-client")]
        ),
        // swift test; тесты PostgreSQL запускаются, только если задан TEST_DATABASE_URL
        .testTarget(
            name: "MentorServerTests",
            dependencies: [
                "MentorServer",
                .product(name: "VaporTesting", package: "vapor"),
                .product(name: "PostgresNIO", package: "postgres-nio"),
            ]
        ),
    ]
)
