import Foundation
import Synchronization
import Testing
@testable import MentorServer

@Suite struct PasswordsTests {
    @Test func hashIsSaltedAndVerifiable() {
        let a = Passwords.hash("секретный пароль")
        let b = Passwords.hash("секретный пароль")
        #expect(a != b, "одинаковые пароли дают разные хеши благодаря соли")
        #expect(a.hasPrefix("pbkdf2_sha256$\(Passwords.iterations)$"))
        #expect(!a.contains("секретный"))
        #expect(Passwords.verify("секретный пароль", a))
        #expect(!Passwords.verify("секретный парол", a))
    }

    @Test func malformedHashNeverVerifies() {
        for stored in ["", "plain", "md5$1$a$b", "pbkdf2_sha256$0$AAAA$AAAA", "pbkdf2_sha256$x$AAAA$AAAA", "pbkdf2_sha256$1000$***$AAAA"] {
            #expect(!Passwords.verify("anything", stored), "\(stored)")
        }
    }
}

@Suite struct AccountServiceTests {
    let store = InMemoryUserStore()
    let millis = Millis()

    final class Millis: Sendable {
        private let value = Mutex<Int64>(1_000_000)
        var now: Int64 { value.withLock { $0 } }
        func advance(_ ms: Int64) { value.withLock { $0 += ms } }
    }

    func makeAccounts() -> AccountService {
        AccountService(store: store, now: { [millis] in millis.now })
    }

    @Test func registerThenLoginWithAnyEmailCase() async throws {
        let accounts = makeAccounts()
        let created = try await accounts.register(RegisterRequest(name: " Аня ", email: " Anya@Example.COM ", password: "password123"))
        #expect(created.email == "anya@example.com")
        #expect(created.name == "Аня")
        #expect(created.userId.hasPrefix("e:"))

        let logged = try await accounts.login(LoginRequest(email: "ANYA@example.com", password: "password123"))
        #expect(logged.userId == created.userId)
    }

    @Test func duplicateEmailAndBadInputAreRejected() async throws {
        let accounts = makeAccounts()
        _ = try await accounts.register(RegisterRequest(name: "Аня", email: "a@b.kg", password: "password123"))
        #expect(await apiError { try await accounts.register(RegisterRequest(name: "Другая", email: "A@B.kg", password: "password456")) }?.status == .conflict)

        let bad: [RegisterRequest] = [
            RegisterRequest(name: "", email: "x@y.kg", password: "password123"),
            RegisterRequest(name: String(repeating: "я", count: AccountService.maxName + 1), email: "x@y.kg", password: "password123"),
            RegisterRequest(name: "Имя", email: "not-an-email", password: "password123"),
            RegisterRequest(name: "Имя", email: "x@y", password: "password123"),
            RegisterRequest(name: "Имя", email: "x@y.kg", password: "short"),
            RegisterRequest(name: "Имя", email: "x@y.kg", password: "          "),
            RegisterRequest(name: "Имя", email: "x@y.kg", password: String(repeating: "p", count: AccountService.maxPassword + 1)),
        ]
        for request in bad {
            #expect(await apiError { try await accounts.register(request) }?.status == .badRequest, "\(request.name) / \(request.email)")
        }
    }

    @Test func wrongPasswordAndUnknownEmailGiveSameError() async throws {
        let accounts = makeAccounts()
        _ = try await accounts.register(RegisterRequest(name: "Аня", email: "a@b.kg", password: "password123"))
        let wrong = await apiError { try await accounts.login(LoginRequest(email: "a@b.kg", password: "password000")) }
        let unknown = await apiError { try await accounts.login(LoginRequest(email: "ghost@b.kg", password: "password123")) }
        #expect(wrong != nil && wrong == unknown)
        #expect(wrong?.status == .unauthorized)
    }

    @Test func tooManyFailuresLockLoginForAWhile() async throws {
        let accounts = makeAccounts()
        _ = try await accounts.register(RegisterRequest(name: "Аня", email: "a@b.kg", password: "password123"))
        for _ in 0..<AccountService.maxFailures {
            _ = await apiError { try await accounts.login(LoginRequest(email: "a@b.kg", password: "wrong-password")) }
        }
        // даже верный пароль не пускает, пока действует блокировка
        #expect(await apiError { try await accounts.login(LoginRequest(email: "a@b.kg", password: "password123")) }?.status == .tooManyRequests)

        millis.advance(AccountService.lockMs)
        let account = try await accounts.login(LoginRequest(email: "a@b.kg", password: "password123"))
        #expect(account.email == "a@b.kg")
    }

    @Test func successfulLoginResetsFailures() async throws {
        let accounts = makeAccounts()
        _ = try await accounts.register(RegisterRequest(name: "Аня", email: "a@b.kg", password: "password123"))
        for _ in 0..<(AccountService.maxFailures - 1) {
            _ = await apiError { try await accounts.login(LoginRequest(email: "a@b.kg", password: "wrong-password")) }
        }
        _ = try await accounts.login(LoginRequest(email: "a@b.kg", password: "password123"))
        _ = await apiError { try await accounts.login(LoginRequest(email: "a@b.kg", password: "wrong-password")) }
        // счётчик начался заново, поэтому вход не заблокирован
        _ = try await accounts.login(LoginRequest(email: "a@b.kg", password: "password123"))
    }

    @Test func deletingUserRemovesAccountSoEmailIsFreeAgain() async throws {
        let accounts = makeAccounts()
        let account = try await accounts.register(RegisterRequest(name: "Аня", email: "a@b.kg", password: "password123"))
        let service = MentorService(sources: sources, llm: RuleBasedLlm(), store: store)
        try await service.delete(account.userId)

        #expect(await apiError { try await accounts.login(LoginRequest(email: "a@b.kg", password: "password123")) }?.status == .unauthorized)
        let again = try await accounts.register(RegisterRequest(name: "Аня", email: "a@b.kg", password: "password456"))
        #expect(again.userId != account.userId)
    }
}

@Suite struct TokenIssuerTests {
    @Test func issuedTokenResolvesToUser() async throws {
        let issuer = await TokenIssuer(secret: "token-test-secret-0123456789abcdef0123")
        let token = try await issuer.issue("e:123")
        #expect(await issuer.userId(from: token) == "e:123")
    }

    @Test func forgedOrForeignTokensAreRejected() async throws {
        let issuer = await TokenIssuer(secret: "token-test-secret-0123456789abcdef0123")
        let other = await TokenIssuer(secret: "another-secret-0987654321-fedcba98765432")
        let token = try await issuer.issue("e:123")

        #expect(await other.userId(from: token) == nil, "токен с чужим секретом")
        #expect(await issuer.userId(from: "not.a.jwt") == nil)
        #expect(await issuer.userId(from: "") == nil)

        // подменили полезную нагрузку – подпись перестаёт сходиться
        var parts = token.split(separator: ".").map(String.init)
        let fakePayload = #"{"iss":"ai-mentor","aud":["ai-mentor-app"],"sub":"e:admin","exp":4102444800}"#
        parts[1] = Data(fakePayload.utf8).base64EncodedString()
            .replacingOccurrences(of: "=", with: "").replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        #expect(await issuer.userId(from: parts.joined(separator: ".")) == nil)
    }
}
