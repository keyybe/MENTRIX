import SwiftUI

// Мини-тест: по одному короткому вопросу на тему направления.
// По ответам ИИ-наставник понимает, что человек уже знает, и подстраивает план.

// Один вопрос: варианты ответа и «Не знаю». selected – выбранный вариант (QuizAnswer.dontKnow – «Не знаю»).
struct QuizQuestionView: View {
    let question: QuizQuestionDto
    let index: Int
    let total: Int
    let selected: Int?
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Вопрос \(index + 1) из \(total)").font(.labelMedium).foregroundStyle(Palette.indigo)
                Spacer()
                Text(question.topic).font(.labelMedium).foregroundStyle(Palette.inkSoft).lineLimit(1)
            }
            Text(question.question).font(.headlineSmall).foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 4)
            ForEach(Array(question.options.enumerated()), id: \.offset) { i, option in
                AnswerRow(text: option, selected: selected == i) { onSelect(i) }
            }
            AnswerRow(text: "Не знаю", muted: true, selected: selected == QuizAnswer.dontKnow) { onSelect(QuizAnswer.dontKnow) }
        }
    }
}

private struct AnswerRow: View {
    let text: String
    var muted = false
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SoftCard(selected: selected) {
                HStack(spacing: 12) {
                    Text(text).font(.titleSmall).foregroundStyle(muted && !selected ? Palette.inkSoft : Palette.ink)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(selected ? Palette.indigo : Palette.line)
                }
                .padding(16)
            }
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// Прохождение мини-теста по шагам в онбординге
@MainActor @Observable
final class QuizFlow {
    private(set) var questions: [QuizQuestionDto] = []
    private(set) var area: ItArea?
    private(set) var loading = false
    private(set) var failed = false
    var index = 0
    var answers: [String: Int] = [:]

    var current: QuizQuestionDto? { questions.indices.contains(index) ? questions[index] : nil }
    var isLast: Bool { index >= questions.count - 1 }
    var currentAnswered: Bool { current.map { answers[$0.id] != nil } ?? false }
    // Тест можно пропустить, если вопросы не загрузились
    var unavailable: Bool { !loading && (failed || questions.isEmpty) }

    // Ответы для сервера; nil – теста не было
    var result: [QuizAnswer]? {
        questions.isEmpty ? nil : questions.map { QuizAnswer(id: $0.id, option: answers[$0.id] ?? QuizAnswer.dontKnow) }
    }

    // Загружает вопросы направления; при смене направления ответы сбрасываются
    func load(area: ItArea, using vm: MentorViewModel) async {
        if self.area == area && !questions.isEmpty { return }
        loading = true
        failed = false
        let loaded = await vm.loadQuiz(area: area)
        self.area = area
        questions = loaded ?? []
        failed = loaded == nil
        index = 0
        answers = [:]
        loading = false
    }
}
