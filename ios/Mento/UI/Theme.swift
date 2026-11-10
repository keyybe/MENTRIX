import SwiftUI

// ---------- Цвета ----------

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

enum Palette {
    static let indigo = Color(hex: 0x5B5BF6)      // основной
    static let violet = Color(hex: 0x9B5CF6)      // второй цвет градиента
    static let indigoSoft = Color(hex: 0xEEEEFE)  // тонированный фон основного
    static let indigoDeep = Color(hex: 0x3F3DC8)
    static let mint = Color(hex: 0x12B5A0)        // успех
    static let mintSoft = Color(hex: 0xE3F7F3)
    static let amber = Color(hex: 0xF59E0B)       // серия занятий
    static let amberSoft = Color(hex: 0xFEF3DC)
    static let coral = Color(hex: 0xF2545B)       // ошибки
    static let coralSoft = Color(hex: 0xFDECEC)
    static let sky = Color(hex: 0x3B9EF5)
    static let skySoft = Color(hex: 0xE6F2FE)
    static let ink = Color(hex: 0x14152B)         // основной текст
    static let inkSoft = Color(hex: 0x6B6F86)     // второстепенный текст
    static let line = Color(hex: 0xE7E8F0)        // рамки
    static let background = Color(hex: 0xF6F6FB)
    static let surface = Color.white
    static let cardShadow = Color(red: 0x34 / 255, green: 0x3A / 255, blue: 0x8C / 255).opacity(0.13)
}

enum Gradients {
    static let primary = LinearGradient(colors: [Palette.indigo, Palette.violet], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let hero = LinearGradient(colors: [Color(hex: 0x4F46E5), Color(hex: 0x8B5CF6), Color(hex: 0xC06CF0)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing)
    static let success = LinearGradient(colors: [Palette.mint, Color(hex: 0x0EA5A0)], startPoint: .topLeading, endPoint: .bottomTrailing)
}

// ---------- Шрифт ----------
// Системный шрифт в скруглённом варианте – близок к Manrope из Android-версии и хорошо держит кириллицу.

extension Font {
    static func app(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static let headlineLarge = app(32, .heavy)
    static let headlineMedium = app(26, .heavy)
    static let headlineSmall = app(22, .bold)
    static let titleLarge = app(20, .bold)
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
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(enabled ? AnyShapeStyle(gradient) : AnyShapeStyle(Palette.line))
                    .shadow(color: enabled ? Palette.indigo.opacity(0.3) : .clear, radius: 10, y: 4)
                let color = enabled ? Color.white : Palette.inkSoft
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
    var color: Color = Palette.indigo
    var background: Color = Palette.indigoSoft
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
            .background(enabled ? background : Palette.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
            .background(selected ? Palette.indigoSoft : color, in: shape)
            .overlay { if selected { shape.strokeBorder(Palette.indigo, lineWidth: 2) } }
            .shadow(color: selected ? .clear : Palette.cardShadow, radius: 8, y: 3)
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
                .strokeBorder(focused ? Palette.indigo : Palette.line, lineWidth: focused ? 2 : 1)
        }
        .tint(Palette.indigo)
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
                    .font(.system(size: size * 0.42, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
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
        case .backend: Palette.indigo
        case .mobile: Palette.mint
        }
    }
}
