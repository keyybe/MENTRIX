import AsyncHTTPClient
import Foundation
import JWTKit
import Vapor

// googleClientIds – OAuth Client ID из Google Cloud Console (через запятую, если их несколько).
// devLogin – вход без Google по id устройства, только для разработки.
public struct AuthConfig: Sendable {
    public var jwtSecret: String
    public var googleClientIds: [String]
    public var devLogin: Bool
    public var adminToken: String?

    public init(jwtSecret: String, googleClientIds: [String] = [], devLogin: Bool = false, adminToken: String? = nil) {
        self.jwtSecret = jwtSecret
        self.googleClientIds = googleClientIds
        self.devLogin = devLogin
        self.adminToken = adminToken
    }
}

// Собственные токены сервера: приложение получает их после входа и шлёт в Authorization: Bearer.
// Издатель, аудитория и HS256 не меняй: иначе уже выданные токены перестанут действовать.
public struct TokenIssuer: Sendable {
    static let issuer = "ai-mentor"
    static let audience = "ai-mentor-app"
    static let ttlDays = 30

    private struct Payload: JWTPayload {
        var iss: IssuerClaim
        var aud: AudienceClaim
        var sub: SubjectClaim
        var exp: ExpirationClaim

        func verify(using algorithm: some JWTAlgorithm) async throws {
            try exp.verifyNotExpired()
            guard iss.value == TokenIssuer.issuer else { throw JWTError.claimVerificationFailure(failedClaim: iss, reason: "issuer") }
            try aud.verifyIntendedAudience(includes: TokenIssuer.audience)
        }
    }

    private let keys: JWTKeyCollection

    public init(secret: String) async {
        keys = JWTKeyCollection()
        await keys.add(hmac: HMACKey(from: secret), digestAlgorithm: .sha256)
    }

    public func issue(_ userId: String) async throws -> String {
        let expires = Date().addingTimeInterval(TimeInterval(Self.ttlDays * 24 * 60 * 60))
        return try await keys.sign(Payload(
            iss: IssuerClaim(value: Self.issuer),
            aud: AudienceClaim(value: [Self.audience]),
            sub: SubjectClaim(value: userId),
            exp: ExpirationClaim(value: expires)
        ))
    }

    // id пользователя из токена или nil, если токен поддельный или истёк
    public func userId(from token: String) async -> String? {
        guard let payload = try? await keys.verify(token, as: Payload.self), !payload.sub.value.isEmpty else { return nil }
        return payload.sub.value
    }
}

public protocol GoogleVerifier: Sendable {
    // возвращает стабильный id пользователя Google (sub) или бросает APIError.unauthorized
    func verify(_ idToken: String) async throws -> String
}

// Проверяет подпись ID-токена ключами Google, издателя, срок и что токен выдан нашему приложению
public actor GoogleJwksVerifier: GoogleVerifier {
    private static let certsURL = "https://www.googleapis.com/oauth2/v3/certs"
    private static let cacheTTL: TimeInterval = 10 * 60 * 60 // ключи Google меняются редко
    private static let minRefresh: TimeInterval = 60          // не чаще раза в минуту при неизвестном ключе

    private let clientIds: Set<String>
    private let client: HTTPClient
    private var keys: JWTKeyCollection?
    private var fetchedAt = Date.distantPast

    public init(clientIds: [String], client: HTTPClient = .shared) {
        self.clientIds = Set(clientIds)
        self.client = client
    }

    public func verify(_ idToken: String) async throws -> String {
        do {
            return try await verifyOnce(idToken, refresh: Date().timeIntervalSince(fetchedAt) > Self.cacheTTL)
        } catch let error as APIError {
            throw error
        } catch {
            // ключ мог смениться – один раз перечитываем ключи
            if Date().timeIntervalSince(fetchedAt) > Self.minRefresh, let sub = try? await verifyOnce(idToken, refresh: true) {
                return sub
            }
            throw APIError.unauthorized("Не удалось проверить вход через Google")
        }
    }

    private func verifyOnce(_ idToken: String, refresh: Bool) async throws -> String {
        let keys = try await currentKeys(refresh: refresh)
        let token = try await keys.verify(
            idToken,
            as: GoogleIdentityToken.self,
            expectedAudiences: clientIds,
            trustedAuthorizedPresenters: clientIds
        )
        return token.subject.value
    }

    private func currentKeys(refresh: Bool) async throws -> JWTKeyCollection {
        if let keys, !refresh { return keys }
        var request = HTTPClientRequest(url: Self.certsURL)
        request.method = .GET
        let response = try await client.execute(request, timeout: .seconds(10))
        let body = try await response.body.collect(upTo: 1024 * 1024)
        guard response.status == .ok else { throw UpstreamError(message: "Google certs: \(response.status.code)") }
        let jwks = try JSONDecoder().decode(JWKS.self, from: Data(buffer: body))
        let collection = try await JWTKeyCollection().add(jwks: jwks)
        keys = collection
        fetchedAt = Date()
        return collection
    }
}
