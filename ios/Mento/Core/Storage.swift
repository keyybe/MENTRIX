import Foundation
import Security

// Вход и личные настройки на устройстве
protocol SessionStore: AnyObject {
    var token: String? { get set }
    var deviceId: String { get }
    var reminderMinutes: Int? { get set } // время напоминания в минутах от полуночи, nil – выключено
    var lastPassedDay: String? { get set } // день (yyyy-MM-dd), когда миссия засчитана – в этот день не напоминаем
    var name: String? { get set }          // имя для приветствия и профиля
    var avatarFile: String? { get set }    // имя файла фото профиля в папке приложения
}

// Последние данные с сервера, чтобы приложение открывалось и без интернета
protocol CacheStore: AnyObject {
    var plan: PlanDto? { get set }
    var today: TodayDto? { get set }
    var progress: ProgressDto? { get set }
    func clear()
}

// Токен – в Связке ключей, остальное – в UserDefaults
final class DefaultsSession: SessionStore {
    private let defaults: UserDefaults
    private let keychain = Keychain(service: "kg.aimentor.app")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let id = defaults.string(forKey: "uid") {
            deviceId = id
        } else {
            deviceId = UUID().uuidString
            defaults.set(deviceId, forKey: "uid")
        }
        // Связка ключей переживает удаление приложения – после переустановки начинаем с чистого листа
        if !defaults.bool(forKey: "installed") {
            keychain.delete("token")
            defaults.set(true, forKey: "installed")
        }
    }

    let deviceId: String

    var token: String? {
        get { keychain.get("token") }
        set { if let newValue { keychain.set(newValue, for: "token") } else { keychain.delete("token") } }
    }

    var reminderMinutes: Int? {
        get { defaults.object(forKey: "reminderMinutes") as? Int }
        set { defaults.set(newValue, forKey: "reminderMinutes") }
    }

    var lastPassedDay: String? {
        get { defaults.string(forKey: "lastPassedDay") }
        set { defaults.set(newValue, forKey: "lastPassedDay") }
    }

    var name: String? {
        get { defaults.string(forKey: "name") }
        set { defaults.set(newValue, forKey: "name") }
    }

    var avatarFile: String? {
        get { defaults.string(forKey: "avatarFile") }
        set { defaults.set(newValue, forKey: "avatarFile") }
    }
}

final class DefaultsCache: CacheStore {
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = UserDefaults(suiteName: "mentor-cache") ?? .standard) {
        self.defaults = defaults
    }

    private func read<T: Decodable>(_ key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }

    private func write(_ key: String, _ value: (some Encodable)?) {
        if let value, let data = try? encoder.encode(value) {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    var plan: PlanDto? {
        get { read("plan") }
        set { write("plan", newValue) }
    }

    var today: TodayDto? {
        get { read("today") }
        set { write("today", newValue) }
    }

    var progress: ProgressDto? {
        get { read("progress") }
        set { write("progress", newValue) }
    }

    func clear() {
        ["plan", "today", "progress"].forEach(defaults.removeObject(forKey:))
    }
}

// Минимальная обёртка над Связкой ключей для строк
struct Keychain {
    let service: String

    private func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: key]
    }

    func get(_ key: String) -> String? {
        var q = query(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func set(_ value: String, for key: String) {
        let data = Data(value.utf8)
        let status = SecItemUpdate(query(key) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var q = query(key)
            q[kSecValueData as String] = data
            q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(q as CFDictionary, nil)
        }
    }

    func delete(_ key: String) {
        SecItemDelete(query(key) as CFDictionary)
    }
}
