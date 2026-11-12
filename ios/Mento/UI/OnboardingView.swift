import SwiftUI

// Онбординг (F1): один вопрос на экран
private struct Choice {
    let icon: String
    let tint: Color
    let title: String
    var subtitle: String? = nil
}

private let goalChoices = [
    Choice(icon: "briefcase.fill", tint: Palette.accent, title: "Найти первую работу"),
    Choice(icon: "arrow.left.arrow.right", tint: Palette.sky, title: "Сменить профессию"),
    Choice(icon: "graduationcap.fill", tint: Palette.mint, title: "Для учёбы"),
    Choice(icon: "heart.fill", tint: Palette.coral, title: "Для себя"),
]

private let minuteChoices: [(Int, Choice)] = [
    (15, Choice(icon: "cup.and.saucer.fill", tint: Palette.mint, title: "15 минут", subtitle: "Спокойный темп")),
    (20, Choice(icon: "timer", tint: Palette.sky, title: "20 минут", subtitle: "Оптимально")),
    (30, Choice(icon: "dumbbell.fill", tint: Palette.accent, title: "30 минут", subtitle: "Серьёзно")),
    (40, Choice(icon: "bolt.fill", tint: Palette.amber, title: "40 минут", subtitle: "Интенсивно")),
]

struct OnboardingView: View {
    @Environment(MentorViewModel.self) private var vm

    @State private var step = 0
    @State private var area: ItArea = .frontend
    @State private var level: Level = .beginner
    @State private var goal = ""
    @State private var customGoal = ""
    @State private var minutes = 20
    @State private var days = 5
    @State private var prefilled = false
    @State private var quiz = QuizFlow()
    private let steps = 5
    private let quizStep = 2
    private let goalStep = 3

    private var canCancel: Bool { vm.changingArea }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if step > 0 || canCancel {
                    Button(action: back) {
                        Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold)).foregroundStyle(Palette.ink)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Назад")
                }
                Spacer()
                Text("Шаг \(step + 1) из \(steps)").font(.labelMedium).foregroundStyle(Palette.inkSoft)
            }
            .frame(height: 48)
            SlimProgress(progress: Double(step + 1) / Double(steps), height: 6)
                .padding(.bottom, 28)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    stepContent
                        .id(step)
                        .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: 24)), removal: .opacity))
                    if let error = vm.error {
                        Text(error).font(.bodyMedium).foregroundStyle(Palette.coral)
                        Button("Повторить") { vm.load() }.font(.labelLarge).foregroundStyle(Palette.accent)
                    }
                    if canCancel && step == steps - 1 {
                        Text("Новый план заменит текущий: прогресс начнётся заново.")
                            .font(.bodySmall).foregroundStyle(Palette.inkSoft)
                    }
                    if vm.submitting && step == steps - 1 {
                        Text("ИИ-наставник подбирает темы под твою цель и ответы теста…")
                            .font(.bodySmall).foregroundStyle(Palette.inkSoft)
                    }
                }
                .padding(.bottom, 8)
            }
            .scrollDismissesKeyboard(.interactively)

            PrimaryButton(text: buttonText, enabled: buttonEnabled, loading: vm.submitting || (step == quizStep && quiz.loading)) {
                if step == quizStep && !quiz.unavailable && !quiz.isLast {
                    withAnimation(.easeInOut(duration: 0.25)) { quiz.index += 1 }
                } else if step < steps - 1 {
                    withAnimation(.easeInOut(duration: 0.25)) { step += 1 }
                } else {
                    vm.createProfile(ProfileRequest(area: area, goal: effectiveGoal, level: level, minutesPerDay: minutes,
                                                    daysPerWeek: days, quiz: quiz.unavailable ? nil : quiz.result))
                }
            }
            .padding(.vertical, 12)
        }
        .padding(.horizontal, 20)
        .background(Palette.background.ignoresSafeArea())
        .onAppear(perform: prefill)
        // вопросы теста зависят от направления: грузим их, когда человек доходит до шага теста
        .task(id: step == quizStep ? area : nil) {
            if step == quizStep { await quiz.load(area: area, using: vm) }
        }
    }

    private var buttonText: String {
        if step == quizStep && quiz.unavailable { return "Продолжить без теста" }
        return step < steps - 1 ? "Продолжить" : "Составить план"
    }

    private var buttonEnabled: Bool {
        switch step {
        case quizStep: quiz.unavailable || quiz.currentAnswered
        case goalStep: !effectiveGoal.isEmpty
        default: true
        }
    }

    private var effectiveGoal: String {
        let custom = customGoal.trimmingCharacters(in: .whitespaces)
        return custom.isEmpty ? goal : custom
    }

    // при смене направления подставляем текущие настройки
    private func prefill() {
        guard !prefilled, let plan = vm.plan else { return }
        prefilled = true
        area = plan.area
        level = plan.level
        if goalChoices.contains(where: { $0.title == plan.goal }) { goal = plan.goal } else { customGoal = plan.goal }
        minutes = plan.minutesPerDay
        days = plan.daysPerWeek
    }

    private func back() {
        if step == quizStep && quiz.index > 0 {
            withAnimation(.easeInOut(duration: 0.25)) { quiz.index -= 1 }
        } else if step > 0 {
            withAnimation(.easeInOut(duration: 0.25)) { step -= 1 }
        } else if canCancel {
            vm.cancelChangeArea()
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch step {
            case 0:
                Question(title: "Что хочешь изучать?", subtitle: "Можно поменять в любой момент")
                ForEach(ItArea.allCases) { a in
                    OptionCard(icon: a.icon, tint: a.tint, title: a.title, subtitle: a.hint, selected: area == a) { area = a }
                }
            case 1:
                Question(title: "Твой уровень", subtitle: "Подберём темы под тебя")
                OptionCard(icon: "safari.fill", tint: Palette.mint, title: "Я новичок", subtitle: "Начнём с самых основ",
                           selected: level == .beginner) { level = .beginner }
                OptionCard(icon: "paperplane.fill", tint: Palette.accent, title: "Знаю основы", subtitle: "Пропустим базовые темы",
                           selected: level == .continuing) { level = .continuing }
            case quizStep:
                if quiz.index == 0 || quiz.unavailable {
                    Question(title: "Мини-тест", subtitle: "Несколько коротких вопросов, чтобы не учить то, что ты уже знаешь")
                }
                if quiz.loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 24)
                } else if let q = quiz.current {
                    QuizQuestionView(question: q, index: quiz.index, total: quiz.questions.count,
                                     selected: quiz.answers[q.id]) { quiz.answers[q.id] = $0 }
                        .id(q.id)
                        .transition(.opacity)
                } else {
                    Text("Не удалось загрузить вопросы. Можно продолжить без теста.")
                        .font(.bodyMedium).foregroundStyle(Palette.inkSoft)
                }
            case goalStep:
                Question(title: "Какая у тебя цель?", subtitle: "Под неё ИИ-наставник составит план")
                ForEach(goalChoices, id: \.title) { c in
                    OptionCard(icon: c.icon, tint: c.tint, title: c.title, subtitle: nil,
                               selected: customGoal.isEmpty && goal == c.title) {
                        goal = c.title
                        customGoal = ""
                    }
                }
                AppTextField(placeholder: "Или напиши свою", text: $customGoal)
            default:
                Question(title: "Сколько времени в день?", subtitle: "Лучше понемногу, но каждый день")
                ForEach(minuteChoices, id: \.0) { m, c in
                    OptionCard(icon: c.icon, tint: c.tint, title: c.title, subtitle: c.subtitle, selected: minutes == m) { minutes = m }
                }
                Text("Дней в неделю").font(.titleMedium).foregroundStyle(Palette.ink).padding(.top, 8)
                HStack(spacing: 8) {
                    ForEach(3...7, id: \.self) { d in
                        let selected = days == d
                        Button { days = d } label: {
                            Text("\(d)")
                                .font(.titleLarge)
                                .foregroundStyle(selected ? Palette.onAccent : Palette.ink)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(selected ? Palette.accent : Palette.surface,
                                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .strokeBorder(selected ? Palette.accent : Palette.line)
                                }
                        }
                        .buttonStyle(.pressable)
                    }
                }
            }
        }
    }
}

private struct Question: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headlineMedium).foregroundStyle(Palette.ink)
            Text(subtitle).font(.bodyLarge).foregroundStyle(Palette.inkSoft)
        }
        .padding(.bottom, 8)
    }
}

// Вариант ответа: иконка, текст и отметка выбора справа
private struct OptionCard: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SoftCard(selected: selected) {
                HStack(spacing: 14) {
                    IconTile(icon: icon, tint: selected ? Palette.onAccent : tint, background: selected ? Palette.accent : tint.opacity(0.12))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.titleMedium).foregroundStyle(Palette.ink)
                        if let subtitle { Text(subtitle).font(.bodyMedium).foregroundStyle(Palette.inkSoft) }
                    }
                    Spacer(minLength: 0)
                    ZStack {
                        Circle().strokeBorder(selected ? Palette.accent : Palette.line, lineWidth: 2)
                        if selected {
                            Circle().fill(Palette.accent)
                            Circle().fill(Palette.onAccent).frame(width: 8, height: 8)
                        }
                    }
                    .frame(width: 22, height: 22)
                }
                .padding(16)
            }
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
