import Foundation

// Задание внутри источника. keywords – ключевые понятия, по ним оценивает офлайн-проверка.
// Через "|" можно указать синонимы: "хеш|hash|хэш".
// code = true – практическое задание, в ответе нужно написать код.
public struct TaskDef: Codable, Equatable, Sendable {
    public var title: String
    public var prompt: String
    public var keywords: [String]
    public var code: Bool

    public init(title: String, prompt: String, keywords: [String], code: Bool = false) {
        self.title = title; self.prompt = prompt; self.keywords = keywords; self.code = code
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decode(String.self, forKey: .title)
        prompt = try c.decode(String.self, forKey: .prompt)
        keywords = try c.decode([String].self, forKey: .keywords)
        code = try c.decodeIfPresent(Bool.self, forKey: .code) ?? false
    }

    // Ключевые понятия без синонимов: "хеш|hash" → "хеш"
    var keywordNames: [String] {
        keywords.map { String($0.split(separator: "|", omittingEmptySubsequences: false).first ?? "").trimmed }
    }
}

// Вопрос мини-теста по теме источника. answer – номер правильного варианта в options.
public struct QuizDef: Codable, Equatable, Sendable {
    public var question: String
    public var options: [String]
    public var answer: Int
}

// Проверенный источник из базы. basic = true – для новичков, продолжающие такие пропускают.
public struct Source: Codable, Sendable {
    public var id: String
    public var title: String
    public var url: String
    public var area: ItArea
    public var basic: Bool
    public var minutes: Int
    public var quiz: QuizDef?
    public var tasks: [TaskDef]
}

public enum SourceBase {
    public static func load() throws -> [Source] {
        guard let url = Bundle.module.url(forResource: "sources", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode([Source].self, from: Data(contentsOf: url))
    }
}

extension StringProtocol {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    // Слова через любые пробельные символы (как split("\\s+") у обрезанной строки)
    var wordCount: Int { Swift.max(1,split(whereSeparator: \.isWhitespace).count) }
}
