import SwiftUI

struct LoginView: View {
    @Environment(MentorViewModel.self) private var vm

    @State private var isRegister = false
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var google: GoogleSignIn?

    private let googleConfigured = !AppConfig.googleClientId.isEmpty

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                form
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(alignment: .top) {
            // градиент сверху, белый снизу – чтобы при прокрутке не было «дыр»
            VStack(spacing: 0) { Gradients.hero; Palette.surface }.ignoresSafeArea()
        }
        .onChange(of: isRegister) { vm.clearError() }
    }

    // верхняя часть: логотип и название на градиенте
    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(Palette.heroText)
                .frame(width: 88, height: 88)
                .background(Palette.heroText.opacity(0.12), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .padding(.bottom, 4)
            Text("Mento").font(.headlineLarge).foregroundStyle(Palette.heroText)
            Text("Программирование по 15 минут в день")
                .font(.bodyLarge)
                .foregroundStyle(Palette.heroText.opacity(0.85))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 40)
    }

    // нижняя карточка с переключением Вход/Регистрация и формой
    private var form: some View {
        VStack(spacing: 14) {
            ModeSwitch(isRegister: $isRegister.animation(.easeInOut(duration: 0.2)))
                .padding(.bottom, 4)

            if isRegister {
                AppTextField(placeholder: "Твоё имя", text: $name, icon: "person.fill")
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
            }
            AppTextField(placeholder: "Email", text: $email, icon: "envelope.fill")
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            AppTextField(placeholder: isRegister ? "Пароль (от 8 символов)" : "Пароль",
                         text: $password, icon: "lock.fill", secure: true)
                .textContentType(isRegister ? .newPassword : .password)
                .onSubmit(submit)

            PrimaryButton(text: isRegister ? "Создать аккаунт" : "Войти", loading: vm.submitting, action: submit)

            if let error = vm.error {
                Text(error)
                    .font(.bodyMedium)
                    .foregroundStyle(Palette.coral)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }

            if googleConfigured || AppConfig.isDebug {
                HStack(spacing: 12) {
                    Rectangle().fill(Palette.line).frame(height: 1)
                    Text("или").font(.bodySmall).foregroundStyle(Palette.inkSoft)
                    Rectangle().fill(Palette.line).frame(height: 1)
                }
                .padding(.vertical, 4)
            }

            if googleConfigured {
                TonalButton(text: "Войти через Google", enabled: !vm.submitting, fillWidth: true, action: signInWithGoogle)
            }
            if AppConfig.isDebug || !googleConfigured {
                TonalButton(text: "Без аккаунта (для разработки)", enabled: !vm.submitting, fillWidth: true) { vm.loginDev() }
            }
        }
        .padding(24)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
        .background(Palette.surface, in: UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32, style: .continuous))
        .onChange(of: name) { vm.clearError() }
        .onChange(of: email) { vm.clearError() }
        .onChange(of: password) { vm.clearError() }
    }

    private func submit() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        if isRegister {
            if trimmedName.isEmpty { return vm.loginFailed("Укажи имя") }
            if trimmedEmail.isEmpty { return vm.loginFailed("Укажи email") }
            if password.count < 8 { return vm.loginFailed("Пароль должен быть не короче 8 символов") }
            vm.register(name: trimmedName, email: trimmedEmail, password: password)
        } else {
            if trimmedEmail.isEmpty { return vm.loginFailed("Укажи email") }
            if password.isEmpty { return vm.loginFailed("Укажи пароль") }
            vm.login(email: trimmedEmail, password: password)
        }
    }

    private func signInWithGoogle() {
        let signIn = GoogleSignIn(clientId: AppConfig.googleClientId)
        google = signIn // держим ссылку, пока открыто окно входа
        Task {
            switch await signIn.signIn() {
            case let .success(idToken, name): vm.loginWithGoogle(idToken: idToken, name: name)
            case let .failed(message): vm.loginFailed(message)
            case .cancelled: break
            }
            google = nil
        }
    }
}

// Переключатель «Вход / Регистрация» в цветах приложения: выбранный вариант – капсула акцентного цвета
private struct ModeSwitch: View {
    @Binding var isRegister: Bool

    var body: some View {
        HStack(spacing: 4) {
            option("Вход", selected: !isRegister) { isRegister = false }
            option("Регистрация", selected: isRegister) { isRegister = true }
        }
        .padding(4)
        .background(Palette.background, in: Capsule())
        .overlay { Capsule().strokeBorder(Palette.line) }
    }

    private func option(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.labelLarge)
                .foregroundStyle(selected ? Palette.onAccent : Palette.inkSoft)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(selected ? Palette.accent : .clear, in: Capsule())
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
