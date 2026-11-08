import Foundation

// Календарный день без времени и часового пояса (аналог LocalDate).
// В JSON и в базе – строка yyyy-MM-dd.
public struct Day: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    // дней от 1970-01-01
    public let ordinal: Int

    public init(ordinal: Int) { self.ordinal = ordinal }

    public init(_ year: Int, _ month: Int, _ day: Int) {
        // алгоритм days_from_civil (Howard Hinnant)
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        ordinal = era * 146_097 + doe - 719_468
    }

    public init?(iso: String) {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        self.init(parts[0], parts[1], parts[2])
    }

    // Сегодня по часовому поясу сервера
    public static func today(_ now: Date = Date(), calendar: Calendar = .current) -> Day {
        let c = calendar.dateComponents([.year, .month, .day], from: now)
        return Day(c.year ?? 1970, c.month ?? 1, c.day ?? 1)
    }

    public var components: (year: Int, month: Int, day: Int) {
        // алгоритм civil_from_days (Howard Hinnant)
        let z = ordinal + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        return (yoe + era * 400 + (m <= 2 ? 1 : 0), m, d)
    }

    public func adding(days: Int) -> Day { Day(ordinal: ordinal + days) }

    public func days(until other: Day) -> Int { other.ordinal - ordinal }

    // 0 – понедельник … 6 – воскресенье (1970-01-01 был четвергом)
    public var weekdayFromMonday: Int { ((ordinal % 7) + 7 + 3) % 7 }

    public var monday: Day { adding(days: -weekdayFromMonday) }

    public var description: String {
        let (y, m, d) = components
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    public static func < (lhs: Day, rhs: Day) -> Bool { lhs.ordinal < rhs.ordinal }

    public init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let day = Day(iso: text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Неверная дата: \(text)"))
        }
        self = day
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(description)
    }
}
