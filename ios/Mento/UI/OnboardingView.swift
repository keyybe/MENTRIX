import SwiftUI

// Онбординг (F1): один вопрос на экран
private struct Choice {
    let icon: String
    let tint: Color
    let title: String
    var subtitle: String? = nil
}

private let goalChoices = [
    Choice(icon: "briefcase.fill", tint: Palette.indigo, title: "Найти первую работу"),
    Choice(icon: "arrow.left.arrow.right", tint: Palette.sky, title: "Сменить профессию"),
    Choice(icon: "graduationcap.fill", tint: Palette.mint, title: "Для учёбы"),
    Choice(icon: "heart.fill", tint: Palette.coral, title: "Для себя"),
]

private let minuteChoices: [(Int, Choice)] = [
    (15, Choice(icon: "cup.and.saucer.fill", tint: Palette.mint, title: "15 минут", subtitle: "Спокойный темп")),
    (20, Choice(icon: "timer", tint: Palette.sky, title: "20 минут", subtitle: "Оптимально")),
    (30, Choice(icon: "dumbbell.fill", tint: Palette.indigo, title: "30 минут", subtitle: "Серьёзно")),
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
    private let steps = 4

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
                        Button("Повторить") { vm.load() }.font(.labelLarge).foregroundStyle(Palette.indigo)
                    }
                    if canCancel && step == steps - 1 {
                        Text("Новый план заменит текущий: прогресс начнётся заново.")
                            .font(.bodySmall).foregroundStyle(Palette.inkSoft)
                    }
                }
                .padding(.bottom, 8)
            }
            .scrollDismissesKeyboard(.interactively)

            PrimaryButton(
                text: step < steps - 1 ? "Продолжить" : "Составить план",
                enabled: step != 2 || !effectiveGoal.isEmpty,
                loading: vm.submitting
            ) {
                if step < steps - 1 {
                    withAnimation(.easeInOut(duration: 0.25)) { step += 1 }
                } else {
                    vm.createProfile(ProfileRequest(area: area, goal: effectiveGoal, level: level, minutesPerDay: minutes, daysPerWeek: days))
                }
            }
            .padding(.vertical, 12)
        }
        .padding(.horizontal, 20)
        .background(Palette.background.ignoresSafeArea())
        .onAppear(perform: prefill)
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
        if step > 0 {
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
                OptionCard(icon: "paperplane.fill", tint: Palette.indigo, title: "Знаю основы", subtitle: "Пропустим базовые темы",
                           selected: level == .continuing) { level = .continuing }
            case 2:
                Question(title: "Какая у тебя цель?", subtitle: "Это поможет держать мотивацию")
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
                                .foregroundStyle(selected ? .white : Palette.ink)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(selected ? Palette.indigo : Palette.surface,
                                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .strokeBorder(selected ? Palette.indigo : Palette.line)
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
                    IconTile(icon: icon, tint: selected ? .white : tint, background: selected ? Palette.indigo : tint.opacity(0.12))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.titleMedium).foregroundStyle(Palette.ink)
                        if let subtitle { Text(subtitle).font(.bodyMedium).foregroundStyle(Palette.inkSoft) }
                    }
                    Spacer(minLength: 0)
                    ZStack {
                        Circle().strokeBorder(selected ? Palette.indigo : Palette.line, lineWidth: 2)
                        if selected {
                            Circle().fill(Palette.indigo)
                            Circle().fill(.white).frame(width: 8, height: 8)
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
