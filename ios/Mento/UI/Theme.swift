import SwiftUI

// ---------- Цвета ----------

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }

    // Цвет для светлой и тёмной темы: SwiftUI сам берёт нужный вариант
    init(light: UInt32, dark: UInt32, opacity: Double = 1) {
        func ui(_ hex: UInt32) -> UIColor {
            UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255, alpha: opacity)
        }
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? ui(dark) : ui(light) })
    }
}

// Винная палитра: от почти чёрного #1D1015 до пудрового #F1DDE0.
// В тёмной теме фон тёмный, а текст и главные кнопки пудровые; в светлой – наоборот.
// Остальные цвета (успех, серия, ошибки) подобраны в тон, но различимы.
enum Palette {
    static let accent = Color(light: 0x702B40, dark: 0xD28B96)      // основной акцент: иконки, рамки, выбор
    static let accentSoft = Color(light: 0xF1DDE0, dark: 0x421B29)  // тонированный фон акцента
    static let accentDeep = Color(hex: 0xA64C61)
    static let wine = Color(hex: 0x702B40)
    static let onAccent = Color(light: 0xF1DDE0, dark: 0x1D1015)    // текст и иконки на акценте и главных кнопках
    static let mint = Color(light: 0x2E8B65, dark: 0x8FD1AE)        // успех
    static let mintSoft = Color(light: 0xE0F1E8, dark: 0x22302A)
    static let amber = Color(light: 0xB5701D, dark: 0xF2BE7E)       // серия занятий
    static let amberSoft = Color(light: 0xF8EAD6, dark: 0x3A2620)
    static let coral = Color(light: 0xC8364A, dark: 0xFF8A8A)       // ошибки
    static let coralSoft = Color(light: 0xF9DDE1, dark: 0x40192A)
    static let sky = Color(light: 0x6E4DB8, dark: 0xC3A8EE)         // дополнительный (сиреневый)
    static let skySoft = Color(light: 0xECE4F8, dark: 0x2E1D38)
    static let ink = Color(light: 0x1D1015, dark: 0xF1DDE0)         // основной текст
    static let inkSoft = Color(light: 0x7A5560, dark: 0xBF97A0)     // второстепенный текст
    static let line = Color(light: 0xE6CFD4, dark: 0x4A2433)        // рамки
    static let background = Color(light: 0xF7EEF0, dark: 0x1D1015)
    static let surface = Color(light: 0xFFFFFF, dark: 0x2A151E)     // карточки
    static let cardShadow = Color(light: 0x702B40, dark: 0x000000, opacity: 0.12)
    // винная карточка урока и шапка входа одинаковы в обеих темах
    static let heroText = Color(hex: 0xF1DDE0)
    static let heroInk = Color(hex: 0x1D1015)
}

enum Gradients {
    // главные кнопки и выбранные элементы: пудровая капсула в тёмной теме, винная – в светлой
    static let primary = LinearGradient(colors: [Color(light: 0xA64C61, dark: 0xF1DDE0), Color(light: 0x702B40, dark: 0xD28B96)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing)
    // глубокий винный – главная карточка и шапка входа
    static let hero = LinearGradient(colors: [Color(hex: 0xA64C61), Color(hex: 0x702B40), Color(hex: 0x421B29)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing)
    static let success = LinearGradient(colors: [Palette.mint, Color(light: 0x23704F, dark: 0x6DB892)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing)
}

// Тема оформления, выбирается в профиле и хранится на устройстве
enum AppTheme: String, CaseIterable {
    case dark, light, system

    static let storageKey = "appTheme"

    var title: String {
        switch self {
        case .dark: "Тёмная"
        case .light: "Светлая"
        case .system: "Как в системе"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .dark: .dark
        case .light: .light
        case .system: nil
        }
    }
}

// ---------- Шрифт ----------
// Заголовки – системный шрифт с засечками (New York), остальной текст – обычный системный.
// Оба хорошо держат кириллицу.

extension Font {
    static func app(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight)
    }

    static func display(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static let headlineLarge = display(34, .bold)
    static let headlineMedium = display(28, .semibold)
    static let headlineSmall = display(23, .semibold)
    static let titleLarge = display(20, .semibold)
    static let titleMedium = app(16, .bold)
    static let titleSmall = app(14, .semibold)
    static let bodyLarge = app(16, .medium)
    static let bodyMedium = app(14, .medium)
    static let bodySmall = app(12, .medium)
    static let labelLarge = app(15, .semibold)
    static let labelMedium = app(12, .semibold)
}

// ---------- Нажатие ----------

// Нажатие слегка «утапливает» элемент
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableStyle {
    static var pressable: PressableStyle { PressableStyle() }
}

// ---------- Кнопки ----------

// Главная кнопка: градиентная «капсула»
struct PrimaryButton: View {
    let text: String
    var icon: String? = nil
    var enabled = true
    var loading = false
    var gradient: LinearGradient = Gradients.primary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Capsule()
                    .fill(enabled ? AnyShapeStyle(gradient) : AnyShapeStyle(Palette.line))
                    .shadow(color: enabled ? Palette.accent.opacity(0.25) : .clear, radius: 14, y: 4)
                let color = enabled ? Palette.onAccent : Palette.inkSoft
                if loading {
                    ProgressView().tint(color)
                } else {
                    HStack(spacing: 8) {
                        if let icon { Image(systemName: icon).font(.system(size: 18, weight: .semibold)) }
                        Text(text).font(.titleMedium)
                    }
                    .foregroundStyle(color)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
        }
        .buttonStyle(.pressable)
        .disabled(!enabled || loading)
    }
}

// Тонированная кнопка для второстепенных действий
struct TonalButton: View {
    let text: String
    var icon: String? = nil
    var color: Color = Palette.accent
    var background: Color = Palette.accentSoft
    var enabled = true
    var fillWidth = false
    let action: () -> Void

    var body: some View {
        let tint = enabled ? color : Palette.inkSoft
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon).font(.system(size: 16, weight: .semibold)) }
                Text(text).font(.labelLarge).lineLimit(1)
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 16)
            .frame(maxWidth: fillWidth ? .infinity : nil)
            .frame(height: 48)
            .background(enabled ? background : Palette.surface, in: Capsule())
        }
        .buttonStyle(.pressable)
        .disabled(!enabled)
    }
}

// ---------- Карточки ----------

// Белая «парящая» карточка с мягкой тенью. selected – выбранный вариант (рамка основного цвета).
struct SoftCard<Content: View>: View {
    var selected = false
    var color: Color = Palette.surface
    @ViewBuilder let content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        VStack(alignment: .leading, spacing: 0, content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Palette.accentSoft : color, in: shape)
            .overlay { shape.strokeBorder(selected ? Palette.accent : Palette.line.opacity(0.7), lineWidth: selected ? 2 : 1) }
            .shadow(color: selected ? .clear : Palette.cardShadow, radius: 12, y: 6)
    }
}

// Иконка в скруглённом квадрате с тонированным фоном
struct IconTile: View {
    let icon: String
    let tint: Color
    let background: Color
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(background, in: RoundedRectangle(cornerRadius: size * 0.32, style: .continuous))
    }
}

// ---------- Прогресс ----------

struct SlimProgress: View {
    let progress: Double
    var height: CGFloat = 8
    var track: Color = Palette.line

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(Gradients.primary)
                    .frame(width: geo.size.width * min(max(progress, 0), 1))
            }
        }
        .frame(height: height)
        .animation(.easeInOut(duration: 0.4), value: progress)
    }
}

// Небольшая «пилюля» с иконкой и текстом
struct InfoPill: View {
    let icon: String
    let text: String
    let tint: Color
    let background: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 13, weight: .semibold))
            Text(text).font(.labelMedium)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(background, in: Capsule())
    }
}

// ---------- Поле ввода ----------

struct AppTextField: View {
    let placeholder: String
    @Binding var text: String
    var icon: String? = nil
    var minLines = 1
    var code = false
    var secure = false
    var enabled = true

    @FocusState private var focused: Bool
    @State private var revealed = false

    var body: some View {
        HStack(alignment: minLines > 1 ? .top : .center, spacing: 12) {
            if let icon {
                Image(systemName: icon).foregroundStyle(Palette.inkSoft).frame(width: 20)
            }
            Group {
                if secure && !revealed {
                    SecureField("", text: $text, prompt: prompt)
                } else if minLines > 1 {
                    TextField("", text: $text, prompt: prompt, axis: .vertical)
                        .lineLimit(minLines...)
                } else {
                    TextField("", text: $text, prompt: prompt)
                }
            }
            .focused($focused)
            .font(code ? .system(size: 15, design: .monospaced) : .bodyLarge)
            .foregroundStyle(Palette.ink)
            .textInputAutocapitalization(code || secure ? .never : .sentences)
            .autocorrectionDisabled(code || secure)
            .disabled(!enabled)
            if secure {
                Button { revealed.toggle() } label: {
                    Image(systemName: revealed ? "eye.slash" : "eye").foregroundStyle(Palette.inkSoft)
                }
                .accessibilityLabel(revealed ? "Скрыть пароль" : "Показать пароль")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(focused ? Palette.accent : Palette.line, lineWidth: focused ? 2 : 1)
        }
        .tint(Palette.accent)
    }

    private var prompt: Text { Text(placeholder).foregroundStyle(Palette.inkSoft) }
}

// ---------- Аватар ----------

// Фото, если оно есть, иначе первая буква имени на градиенте
struct UserAvatar: View {
    let name: String?
    let file: String?
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(Gradients.primary)
            if let image = AvatarStore.load(file) {
                Image(uiImage: image).resizable().scaledToFill()
                    .accessibilityLabel("Фото профиля")
            } else {
                Text(initial)
                    .font(.system(size: size * 0.42, weight: .semibold, design: .serif))
                    .foregroundStyle(Palette.onAccent)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initial: String {
        guard let first = name?.trimmingCharacters(in: .whitespaces).first else { return "🙂" }
        return String(first).uppercased()
    }
}

// Русское склонение: 1 тема, 2 темы, 5 тем
func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
    let mod10 = n % 10, mod100 = n % 100
    if mod10 == 1 && mod100 != 11 { return one }
    if (2...4).contains(mod10) && !(12...14).contains(mod100) { return few }
    return many
}

extension ItArea {
    var icon: String {
        switch self {
        case .frontend: "globe"
        case .backend: "server.rack"
        case .mobile: "iphone"
        }
    }

    var hint: String {
        switch self {
        case .frontend: "Сайты и интерфейсы"
        case .backend: "Серверы и базы данных"
        case .mobile: "Приложения для телефона"
        }
    }

    var tint: Color {
        switch self {
        case .frontend: Palette.sky
        case .backend: Palette.accent
        case .mobile: Palette.mint
        }
    }
}
