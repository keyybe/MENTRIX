import SwiftUI

private enum LessonPhase { case empty, question, reward }

// Урок дня (F3, F4): отдельный полноэкранный режим, чтобы ничего не отвлекало.
struct LessonView: View {
    @Environment(MentorViewModel.self) private var vm
    let onClose: () -> Void

    @State private var answer = ""
    @State private var answeredMission: String?
    @State private var chatOpen = false

    private var phase: LessonPhase {
        if vm.today?.mission == nil { return .empty }
        if vm.evaluation?.passed == true { return .reward }
        return .question
    }

    // шаги урока: вопрос → ответ → результат
    private var step: Double {
        if vm.evaluation != nil { return 3 }
        if !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return 2 }
        return 1
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.inkSoft)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Закрыть урок")
                SlimProgress(progress: step / 3, height: 6).padding(.trailing, 16)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            ZStack {
                switch phase {
                case .empty:
                    EmptyLesson(message: vm.today?.message, onFinish: finish)
                case .reward:
                    if let ev = vm.evaluation {
                        RewardView(ev: ev, onNext: { vm.next() }, onFinish: finish)
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }
                case .question:
                    if let mission = vm.today?.mission {
                        QuestionView(mission: mission, answer: $answer, onAskMentor: { chatOpen = true })
                            .transition(.opacity)
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.3), value: phase)
        }
        .background(Palette.background.ignoresSafeArea())
        .onChange(of: vm.today?.mission?.id, initial: true) { _, id in
            // новый урок – пустое поле ответа
            if answeredMission != id {
                answeredMission = id
                answer = ""
            }
        }
        .sheet(isPresented: $chatOpen) {
            if let mission = vm.today?.mission {
                ChatView(mission: mission, onClose: { chatOpen = false })
            }
        }
    }

    // обновить данные и вернуться на главную
    private func finish() {
        vm.next()
        onClose()
    }
}

private struct QuestionView: View {
    @Environment(MentorViewModel.self) private var vm
    @Environment(\.openURL) private var openURL
    let mission: MissionDto
    @Binding var answer: String
    let onAskMentor: () -> Void

    var body: some View {
        let ev = vm.evaluation
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 8) {
                        if mission.review {
                            InfoPill(icon: "arrow.counterclockwise", text: "Повторение", tint: Palette.amber, background: Palette.amberSoft)
                        } else {
                            InfoPill(icon: "sparkles", text: "Новый урок", tint: Palette.accent, background: Palette.accentSoft)
                        }
                        if mission.code {
                            InfoPill(icon: "chevron.left.forwardslash.chevron.right", text: "Код", tint: Palette.mint, background: Palette.mintSoft)
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(mission.topic) · \(mission.title)").font(.labelLarge).foregroundStyle(Palette.inkSoft)
                        Text(mission.task).font(.app(24, .bold)).foregroundStyle(Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 8) {
                        TonalButton(text: "Материал", icon: "book.fill", color: Palette.sky, background: Palette.skySoft, fillWidth: true) {
                            if let url = URL(string: mission.material.url) { openURL(url) }
                        }
                        TonalButton(text: "Подсказка", icon: "lightbulb.fill", color: Palette.amber, background: Palette.amberSoft,
                                    enabled: !vm.offline, fillWidth: true, action: onAskMentor)
                    }
                    AppTextField(
                        placeholder: mission.code ? "Напиши код здесь…" : "Твой ответ…",
                        text: $answer,
                        minLines: mission.code ? 6 : 4,
                        code: mission.code,
                        enabled: ev == nil
                    )
                    // Разбор ответа мягко раскрывается прямо под полем
                    if let ev {
                        MistakeCard(ev: ev).transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    if let error = vm.error {
                        Text(error).font(.bodyMedium).foregroundStyle(Palette.coral)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .animation(.easeInOut(duration: 0.3), value: ev)
            }
            .scrollDismissesKeyboard(.interactively)

            // кнопка всегда внизу, над клавиатурой
            Group {
                if ev == nil {
                    PrimaryButton(text: "Проверить",
                                  enabled: !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !vm.offline,
                                  loading: vm.submitting) {
                        vm.submitAnswer(answer)
                    }
                } else {
                    PrimaryButton(text: "Понятно, дальше") { vm.next() }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }
}

private struct MistakeCard: View {
    let ev: EvaluationDto

    var body: some View {
        SoftCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    IconTile(icon: "lightbulb.fill", tint: Palette.amber, background: Palette.amberSoft)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Почти получилось").font(.titleMedium).foregroundStyle(Palette.ink)
                        Text("\(ev.score)% · разбери подсказку и двигайся дальше").font(.bodySmall).foregroundStyle(Palette.inkSoft)
                    }
                }
                Text(ev.feedback).font(.bodyLarge).foregroundStyle(Palette.ink)
                ForEach(ev.gaps, id: \.self) { gap in
                    HStack(alignment: .top, spacing: 10) {
                        Circle().fill(Palette.amber).frame(width: 6, height: 6).padding(.top, 7)
                        Text(gap).font(.bodyMedium).foregroundStyle(Palette.inkSoft)
                    }
                }
            }
            .padding(18)
        }
    }
}

// Экран-награда после верного ответа
private struct RewardView: View {
    let ev: EvaluationDto
    let onNext: () -> Void
    let onFinish: () -> Void
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 10) {
            ScrollView {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 56, weight: .bold))
                        .foregroundStyle(Palette.onAccent)
                        .frame(width: 112, height: 112)
                        .background(Gradients.success, in: Circle())
                        .scaleEffect(appeared ? 1 : 0.6)
                        .animation(.spring(response: 0.45, dampingFraction: 0.6), value: appeared)
                    Text("Отлично!").font(.headlineLarge).foregroundStyle(Palette.ink)
                    HStack(spacing: 8) {
                        InfoPill(icon: "flame.fill", text: "Серия \(ev.streak) дн.", tint: Palette.amber, background: Palette.amberSoft)
                        InfoPill(icon: "trophy.fill", text: "\(ev.score)%", tint: Palette.mint, background: Palette.mintSoft)
                    }
                    SoftCard {
                        Text(ev.feedback).font(.bodyLarge).foregroundStyle(Palette.ink).padding(18)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            }
            PrimaryButton(text: "Ещё урок", gradient: Gradients.success, action: onNext)
            TonalButton(text: "На сегодня хватит", fillWidth: true, action: onFinish)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .sensoryFeedback(.success, trigger: appeared)
        .onAppear { appeared = true }
    }
}

private struct EmptyLesson: View {
    let message: String?
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            IconTile(icon: "trophy.fill", tint: Palette.amber, background: Palette.amberSoft, size: 88)
            Text("На сегодня всё").font(.headlineMedium).foregroundStyle(Palette.ink)
            Text(message ?? "Возвращайся завтра за новым уроком.")
                .font(.bodyLarge).foregroundStyle(Palette.inkSoft).multilineTextAlignment(.center)
            PrimaryButton(text: "На главную", action: onFinish).padding(.top, 8)
        }
        .padding(24)
    }
}
