import SwiftUI

// Готовые вопросы – чтобы не печатать
private let quickQuestions = ["С чего начать?", "Объясни проще", "Дай подсказку", "Приведи пример"]

// Чат «Застрял» (F5): ментор подсказывает наводящими вопросами, но не решает задание за ученика
struct ChatView: View {
    @Environment(ChatViewModel.self) private var chat
    let mission: MissionDto
    let onClose: () -> Void

    @State private var input = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            messages
            if let error = chat.error {
                Text(error).font(.bodyMedium).foregroundStyle(Palette.coral)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
            }
            if !chat.sending {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(quickQuestions, id: \.self) { q in
                            Button { chat.send(q) } label: {
                                Text(q).font(.labelLarge).foregroundStyle(Palette.accent)
                                    .padding(.horizontal, 14).padding(.vertical, 8)
                                    .background(Palette.accentSoft, in: Capsule())
                            }
                            .buttonStyle(.pressable)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
            }
            inputBar
        }
        .background(Palette.background.ignoresSafeArea())
        .onAppear { chat.open(missionId: mission.id) }
        // неудачная отправка возвращает вопрос в поле ввода
        .onChange(of: chat.draft) { _, draft in if !draft.isEmpty { input = draft } }
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles").font(.system(size: 18, weight: .semibold)).foregroundStyle(Palette.onAccent)
                .frame(width: 40, height: 40).background(Gradients.primary, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("ИИ-ментор").font(.titleMedium).foregroundStyle(Palette.ink)
                Text(chat.sending ? "печатает…" : mission.title)
                    .font(.bodySmall).foregroundStyle(chat.sending ? Palette.accent : Palette.inkSoft).lineLimit(1)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.inkSoft)
                    .frame(width: 32, height: 32).background(Palette.line.opacity(0.6), in: Circle())
            }
            .accessibilityLabel("Закрыть")
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 8)
    }

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    SoftCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Вопрос урока").font(.labelMedium).foregroundStyle(Palette.accent)
                            Text(mission.task).font(.titleMedium).foregroundStyle(Palette.ink)
                            Text("Я не скажу ответ сразу, но помогу до него дойти.").font(.bodySmall).foregroundStyle(Palette.inkSoft)
                        }
                        .padding(16)
                    }
                    ForEach(Array(chat.messages.enumerated()), id: \.offset) { i, msg in
                        Bubble(text: msg.text, mine: msg.role == .user).id(i)
                    }
                    if chat.sending {
                        Bubble(text: "…", mine: false).id("typing")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: chat.messages.count) { scrollToEnd(proxy) }
            .onChange(of: chat.sending) { scrollToEnd(proxy) }
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        withAnimation {
            if chat.sending { proxy.scrollTo("typing", anchor: .bottom) }
            else if !chat.messages.isEmpty { proxy.scrollTo(chat.messages.count - 1, anchor: .bottom) }
        }
    }

    private var inputBar: some View {
        let canSend = !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !chat.sending
        return HStack(alignment: .bottom, spacing: 10) {
            TextField("", text: $input, prompt: Text("Напиши, что непонятно").foregroundStyle(Palette.inkSoft), axis: .vertical)
                .lineLimit(1...4)
                .font(.bodyLarge)
                .foregroundStyle(Palette.ink)
                .focused($inputFocused)
                .tint(Palette.accent)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(inputFocused ? Palette.accent : Palette.line, lineWidth: inputFocused ? 2 : 1)
                }
            Button {
                chat.send(input)
                input = ""
            } label: {
                Image(systemName: "paperplane.fill").font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(canSend ? Palette.onAccent : Palette.inkSoft)
                    .frame(width: 52, height: 52)
                    .background(canSend ? AnyShapeStyle(Gradients.primary) : AnyShapeStyle(Palette.line), in: Circle())
            }
            .buttonStyle(.pressable)
            .disabled(!canSend)
            .accessibilityLabel("Отправить")
        }
        .padding(16)
    }
}

private struct Bubble: View {
    let text: String
    let mine: Bool

    var body: some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 20, bottomLeadingRadius: mine ? 20 : 6,
            bottomTrailingRadius: mine ? 6 : 20, topTrailingRadius: 20, style: .continuous)
        HStack {
            if mine { Spacer(minLength: 48) }
            Text(text)
                .font(.bodyLarge)
                .foregroundStyle(mine ? Palette.onAccent : Palette.ink)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(mine ? AnyShapeStyle(Gradients.primary) : AnyShapeStyle(Palette.surface), in: shape)
                .shadow(color: mine ? .clear : Palette.cardShadow, radius: 4, y: 2)
                .textSelection(.enabled)
            if !mine { Spacer(minLength: 48) }
        }
    }
}
