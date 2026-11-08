import Crypto
import CryptoExtras
import Foundation
import Synchronization
import Vapor

// Пароли храним только как PBKDF2-SHA256 с солью: даже при утечке базы их нельзя прочитать.
// Формат строки: pbkdf2_sha256$итерации$соль$хеш (соль и хеш в Base64) – такой же был у сервера на Kotlin.
public enum Passwords {
    static let iterations = 210_000
    static let keyBytes = 32

    public static func hash(_ password: String) -> String {
        var rng = SystemRandomNumberGenerator()
        let salt = (0..<16).map { _ in UInt8.random(in: .min ... .max, using: &rng) }
        let hash = derive(password, salt: salt, iterations: iterations) ?? []
        return "pbkdf2_sha256$\(iterations)$\(Data(salt).base64EncodedString())$\(Data(hash).base64EncodedString())"
    }

    public static func verify(_ password: String, _ stored: String) -> Bool {
        let parts = stored.split(separator: "$", omittingEmptySubsequences: false)
        guard parts.count == 4, parts[0] == "pbkdf2_sha256",
              let iterations = Int(parts[1]), iterations > 0,
              let salt = Data(base64Encoded: String(parts[2])),
              let expected = Data(base64Encoded: String(parts[3])),
              let actual = derive(password, salt: [UInt8](salt), iterations: iterations)
        else { return false }
        // сравнение за постоянное время, чтобы по скорости ответа нельзя было подобрать хеш
        return constantTimeEquals([UInt8](expected), actual)
    }

    private static func derive(_ password: String, salt: [UInt8], iterations: Int) -> [UInt8]? {
        let key = try? KDF.Insecure.PBKDF2.deriveKey(
            from: Array(password.utf8), salt: salt, using: .sha256,
            outputByteCount: keyBytes, unsafeUncheckedRounds: iterations
        )
        return key?.withUnsafeBytes { Array($0) }
    }
}

func constantTimeEquals(_ a: [UInt8], _ b: [UInt8]) -> Bool {
    guard a.count == b.count else { return false }
    var diff: UInt8 = 0
    for i in a.indices { diff |= a[i] ^ b[i] }
    return diff == 0
}

// Регистрация и вход по email. now – миллисекунды, подменяется в тестах ограничения попыток.
public final class AccountService: Sendable {
    public static let minPassword = 8
    public static let maxPassword = 128
    public static let maxName = 40
    public static let maxFailures = 5               // столько неудачных входов подряд…
    public static let lockMs: Int64 = 15 * 60 * 1000 // …блокируют вход на 15 минут

    private struct Failures {
        var count: Int
        var since: Int64
    }

    private let store: any UserStore
    private let now: @Sendable () -> Int64
    private let failures = Mutex<[String: Failures]>([:])

    // Хеш-пустышка: если email не найден, всё равно считаем хеш, чтобы по времени ответа
    // нельзя было узнать, зарегистрирован ли email
    private let dummyHash = Passwords.hash(newId())

    public init(store: any UserStore, now: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }) {
        self.store = store
        self.now = now
    }

    private func normalize(_ email: String) -> String { email.trimmed.lowercased() }

    // Хеширование пароля – тяжёлая операция, выносим её из потоков Swift Concurrency
    private func offload<T: Sendable>(_ work: @escaping @Sendable () -> T) async throws -> T {
        try await NIOThreadPool.singleton.runIfActive(work)
    }

    public func register(_ req: RegisterRequest) async throws -> Account {
        let email = normalize(req.email)
        let name = req.name.trimmed
        if name.isEmpty || name.count > Self.maxName { throw APIError.badRequest("Укажи имя (до \(Self.maxName) символов)") }
        if (try? /^[^@\s]+@[^@\s]+\.[^@\s]{2,}$/.wholeMatch(in: email)) == nil || email.count > 254 {
            throw APIError.badRequest("Проверь email – похоже, в нём ошибка")
        }
        if req.password.count < Self.minPassword { throw APIError.badRequest("Пароль должен быть не короче \(Self.minPassword) символов") }
        if req.password.count > Self.maxPassword { throw APIError.badRequest("Слишком длинный пароль") }
        if req.password.trimmed.isEmpty { throw APIError.badRequest("Пароль не может состоять из пробелов") }

        let password = req.password
        let hash = try await offload { Passwords.hash(password) }
        let account = Account(userId: "e:" + newId(), email: email, passwordHash: hash, name: name)
        guard try await store.createAccount(account) else {
            throw APIError.conflict("Этот email уже зарегистрирован. Войди в аккаунт.")
        }
        return account
    }

    public func login(_ req: LoginRequest) async throws -> Account {
        let email = normalize(req.email)
        let locked = failures.withLock { f in
            guard let entry = f[email] else { return false }
            return entry.count >= Self.maxFailures && now() - entry.since < Self.lockMs
        }
        if locked { throw APIError.tooManyRequests("Слишком много попыток входа. Попробуй через 15 минут.") }

        let account = try await store.findAccount(email: email)
        let password = req.password
        let stored = account?.passwordHash ?? dummyHash
        let passwordOk = try await offload { Passwords.verify(password, stored) }
        guard let account, passwordOk else {
            let t = now()
            failures.withLock { f in
                if let old = f[email], t - old.since < Self.lockMs {
                    f[email] = Failures(count: old.count + 1, since: old.since)
                } else {
                    f[email] = Failures(count: 1, since: t)
                }
            }
            throw APIError.unauthorized("Неверный email или пароль")
        }
        _ = failures.withLock { $0.removeValue(forKey: email) }
        return account
    }
}
