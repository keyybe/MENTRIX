import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

enum GoogleSignInResult {
    case success(idToken: String, name: String?)
    case cancelled
    case failed(String)
}

// Вход через Google без сторонних SDK: OAuth 2.0 + PKCE в системном окне ASWebAuthenticationSession.
// Нужен OAuth client ID типа iOS (см. ios/README.md). Его же надо добавить на сервер в GOOGLE_CLIENT_ID
// через запятую – у ID-токена будет audience iOS-клиента.
@MainActor
final class GoogleSignIn: NSObject, ASWebAuthenticationPresentationContextProviding {
    let clientId: String
    private var session: ASWebAuthenticationSession?

    init(clientId: String) {
        self.clientId = clientId
    }

    // com.googleusercontent.apps.123-abc – обратная запись client ID, её же нужно указать в URL Types
    var redirectScheme: String {
        clientId.split(separator: ".").reversed().joined(separator: ".")
    }

    func signIn() async -> GoogleSignInResult {
        let verifier = Self.randomString()
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        let redirect = "\(redirectScheme):/oauth2redirect"

        var auth = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        auth.queryItems = [
            .init(name: "client_id", value: clientId),
            .init(name: "redirect_uri", value: redirect),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: "openid profile email"),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "prompt", value: "select_account"),
        ]

        let callback: URL
        do {
            callback = try await withCheckedThrowingContinuation { continuation in
                let completion: ASWebAuthenticationSession.CompletionHandler = { url, error in
                    if let url { continuation.resume(returning: url) } else { continuation.resume(throwing: error ?? URLError(.unknown)) }
                }
                let session = if #available(iOS 17.4, *) {
                    ASWebAuthenticationSession(url: auth.url!, callback: .customScheme(redirectScheme), completionHandler: completion)
                } else {
                    ASWebAuthenticationSession(url: auth.url!, callbackURLScheme: redirectScheme, completionHandler: completion)
                }
                session.presentationContextProvider = self
                self.session = session
                session.start()
            }
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            return .cancelled
        } catch {
            return .failed("Не удалось войти через Google")
        }
        defer { session = nil }

        guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value else {
            return .failed("Не удалось войти через Google")
        }

        // обмен кода на токены (для iOS-клиента секрет не нужен)
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [
            .init(name: "client_id", value: clientId),
            .init(name: "code", value: code),
            .init(name: "code_verifier", value: verifier),
            .init(name: "grant_type", value: "authorization_code"),
            .init(name: "redirect_uri", value: redirect),
        ]
        request.httpBody = form.percentEncodedQuery?.data(using: .utf8)

        struct TokenResponse: Decodable { let id_token: String? }
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let idToken = (try? JSONDecoder().decode(TokenResponse.self, from: data))?.id_token else {
            return .failed("Не удалось войти через Google")
        }
        return .success(idToken: idToken, name: Self.givenName(from: idToken))
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first ?? ASPresentationAnchor()
    }

    // Имя из ID-токена – только для приветствия, проверяет токен сервер
    private static func givenName(from jwt: String) -> String? {
        let parts = jwt.split(separator: ".")
        guard parts.count > 1 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (json["given_name"] as? String) ?? (json["name"] as? String)
    }

    private static func randomString() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URL
    }
}

private extension Data {
    var base64URL: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
