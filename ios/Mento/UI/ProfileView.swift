import PhotosUI
import SwiftUI

private let minuteOptions = [15, 20, 25, 30, 35, 40]
private let dayOptions = Array(3...7)
private let reminderDefault = 19 * 60

private func formatTime(_ minutes: Int) -> String {
    String(format: "%02d:%02d", minutes / 60, minutes % 60)
}

private func dayWord(_ n: Int) -> String { (2...4).contains(n) ? "дня" : "дней" }

// Какая настройка сейчас редактируется
private enum ProfileEdit: Identifiable {
    case goal, minutes, days, reminderTime
    var id: Self { self }
}

// Профиль (F8): привычное меню настроек
struct ProfileView: View {
    @Environment(MentorViewModel.self) private var vm
    let onEditProfile: () -> Void

    @State private var editing: ProfileEdit?
    @State private var confirmDelete = false
    @State private var denied = false

    var body: some View {
        let plan = vm.plan
        let busy = vm.submitting || vm.offline
        ScrollView {
            VStack(spacing: 20) {
                header

                if let p = vm.progress {
                    HStack(spacing: 10) {
                        StatTile(icon: "flame.fill", tint: Palette.amber, value: "\(p.streak)", label: "дней подряд")
                        StatTile(icon: "checkmark.seal.fill", tint: Palette.mint, value: "\(p.doneMissions)", label: "уроков")
                        StatTile(icon: "chart.line.uptrend.xyaxis", tint: Palette.indigo,
                                 value: "\(p.totalMissions == 0 ? 0 : p.doneMissions * 100 / p.totalMissions)%", label: "плана")
                    }
                }

                if let plan {
                    Section(title: "Обучение") {
                        SettingRow(icon: plan.area.icon, tint: Palette.sky, title: "Направление", value: plan.area.title,
                                   enabled: !vm.offline) { vm.startChangeArea() }
                        RowDivider()
                        SettingRow(icon: "flag.fill", tint: Palette.coral, title: "Цель", value: plan.goal, enabled: !busy) { editing = .goal }
                        RowDivider()
                        SettingRow(icon: "timer", tint: Palette.mint, title: "Время в день", value: "\(plan.minutesPerDay) мин",
                                   enabled: !busy) { editing = .minutes }
                        RowDivider()
                        SettingRow(icon: "calendar", tint: Palette.indigo, title: "Дней в неделю", value: "\(plan.daysPerWeek)",
                                   enabled: !busy) { editing = .days }
                        if let gaps = vm.progress?.gaps, !gaps.isEmpty {
                            RowDivider()
                            SettingRow(icon: "arrow.counterclockwise", tint: Palette.amber, title: "Темы на повторение",
                                       value: gaps.joined(separator: ", "), action: nil)
                        }
                    }
                }

                Section(title: "Уведомления") {
                    SettingRow(icon: "bell.fill", tint: Palette.amber, title: "Напоминание о занятии",
                               value: vm.reminderMinutes != nil ? "Каждый день" : "Выключено",
                               trailing: AnyView(
                                   Toggle("", isOn: Binding(get: { vm.reminderMinutes != nil }, set: toggleReminder))
                                       .labelsHidden()
                                       .tint(Palette.indigo)
                               )) { toggleReminder(vm.reminderMinutes == nil) }
                    if let minutes = vm.reminderMinutes {
                        RowDivider()
                        SettingRow(icon: "clock.fill", tint: Palette.sky, title: "Время", value: formatTime(minutes)) { editing = .reminderTime }
                    }
                    if denied {
                        Text("Без разрешения на уведомления напоминания не придут. Разреши их в Настройках iPhone.")
                            .font(.bodySmall).foregroundStyle(Palette.coral)
                            .padding(.horizontal, 16).padding(.vertical, 8)
                    }
                }

                Section(title: "Аккаунт") {
                    SettingRow(icon: "rectangle.portrait.and.arrow.right", tint: Palette.inkSoft, title: "Выйти", value: nil) { vm.signOut() }
                    RowDivider()
                    SettingRow(icon: "trash", tint: Palette.coral, title: "Удалить аккаунт", value: nil, titleColor: Palette.coral,
                               enabled: !vm.offline) { confirmDelete = true }
                }

                Text("Mento · версия \(AppConfig.version)")
                    .font(.bodySmall).foregroundStyle(Palette.inkSoft)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(Palette.background)
        .sheet(item: $editing) { edit in
            editSheet(edit)
        }
        .alert("Удалить аккаунт?", isPresented: $confirmDelete) {
            Button("Удалить", role: .destructive) { vm.deleteAccount() }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("План, прогресс и серия будут удалены без возможности восстановления.")
        }
    }

    // шапка: аватар, имя и кнопка редактирования
    private var header: some View {
        VStack(spacing: 10) {
            Button(action: onEditProfile) {
                UserAvatar(name: vm.userName, file: vm.avatarFile, size: 104)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "camera.fill").font(.system(size: 14)).foregroundStyle(Palette.indigo)
                            .frame(width: 34, height: 34)
                            .background(Palette.surface, in: Circle())
                            .overlay { Circle().strokeBorder(Palette.background, lineWidth: 2) }
                    }
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Изменить фото")
            Text(vm.userName ?? "Ученик").font(.headlineSmall).foregroundStyle(Palette.ink)
            if let plan = vm.plan {
                Text("\(plan.area.title) · \(plan.level == .beginner ? "новичок" : "знаю основы")")
                    .font(.bodyMedium).foregroundStyle(Palette.inkSoft)
            }
            TonalButton(text: "Редактировать профиль", icon: "pencil", action: onEditProfile)
        }
        .frame(maxWidth: .infinity)
    }

    private func toggleReminder(_ on: Bool) {
        guard on else { return vm.setReminder(nil) }
        Task {
            // на iOS разрешение на уведомления спрашивается всегда
            let granted = await LocalReminderScheduler.requestPermission()
            denied = !granted
            if granted { vm.setReminder(vm.reminderMinutes ?? reminderDefault) }
        }
    }

    private func save(goal: String? = nil, minutes: Int? = nil, days: Int? = nil) {
        guard let plan = vm.plan else { return }
        vm.saveSettings(goal: goal ?? plan.goal, minutesPerDay: minutes ?? plan.minutesPerDay, daysPerWeek: days ?? plan.daysPerWeek)
    }

    @ViewBuilder
    private func editSheet(_ edit: ProfileEdit) -> some View {
        let plan = vm.plan
        switch edit {
        case .goal:
            GoalSheet(current: plan?.goal ?? "") { save(goal: $0); editing = nil }
                .presentationDetents([.height(300)])
        case .minutes:
            OptionsSheet(title: "Время в день", options: minuteOptions, selected: plan?.minutesPerDay ?? 20,
                         label: { "\($0) минут" }) { save(minutes: $0); editing = nil }
                .presentationDetents([.medium])
        case .days:
            OptionsSheet(title: "Дней в неделю", options: dayOptions, selected: plan?.daysPerWeek ?? 5,
                         label: { "\($0) \(dayWord($0)) в неделю" }) { save(days: $0); editing = nil }
                .presentationDetents([.medium])
        case .reminderTime:
            ReminderTimeSheet(current: vm.reminderMinutes ?? reminderDefault) { vm.setReminder($0); editing = nil }
                .presentationDetents([.height(360)])
        }
    }
}

private struct StatTile: View {
    let icon: String
    let tint: Color
    let value: String
    let label: String

    var body: some View {
        SoftCard {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: 20)).foregroundStyle(tint)
                Text(value).font(.titleLarge).foregroundStyle(Palette.ink).padding(.top, 4)
                Text(label).font(.bodySmall).foregroundStyle(Palette.inkSoft)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
    }
}

// Группа настроек с заголовком, как в системных «Настройках»
private struct Section<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.labelLarge).foregroundStyle(Palette.inkSoft).padding(.leading, 4)
            SoftCard { VStack(spacing: 0, content: content).padding(.vertical, 4) }
        }
    }
}

private struct RowDivider: View {
    var body: some View {
        Rectangle().fill(Palette.line).frame(height: 1).padding(.leading, 68).padding(.trailing, 16)
    }
}

// Строка настройки: иконка, название, текущее значение и стрелка (или свой элемент справа)
private struct SettingRow: View {
    let icon: String
    let tint: Color
    let title: String
    let value: String?
    var titleColor: Color = Palette.ink
    var enabled = true
    var trailing: AnyView? = nil
    let action: (() -> Void)?

    var body: some View {
        let color = enabled ? tint : Palette.inkSoft
        let row = HStack(spacing: 14) {
            IconTile(icon: icon, tint: color, background: color.opacity(0.12), size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.titleSmall).foregroundStyle(enabled ? titleColor : Palette.inkSoft)
                if let value { Text(value).font(.bodySmall).foregroundStyle(Palette.inkSoft).lineLimit(1) }
            }
            Spacer(minLength: 0)
            if let trailing {
                trailing
            } else if action != nil {
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.inkSoft)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)

        if let action {
            Button(action: action) { row }.buttonStyle(.pressable).disabled(!enabled)
        } else {
            row
        }
    }
}

private struct GoalSheet: View {
    @Environment(\.dismiss) private var dismiss
    let current: String
    let onSave: (String) -> Void
    @State private var goal = ""

    var body: some View {
        let trimmed = goal.trimmingCharacters(in: .whitespaces)
        VStack(alignment: .leading, spacing: 16) {
            Text("Твоя цель").font(.titleLarge).foregroundStyle(Palette.ink)
            AppTextField(placeholder: "Например, найти первую работу", text: $goal)
            Text("ИИ-наставник пересоберёт непройденную часть плана под новую цель. Пройденные уроки останутся.")
                .font(.bodySmall).foregroundStyle(Palette.inkSoft)
            HStack {
                TonalButton(text: "Отмена", color: Palette.ink, background: Palette.background, fillWidth: true) { dismiss() }
                TonalButton(text: "Сохранить", enabled: !trimmed.isEmpty && trimmed != current, fillWidth: true) { onSave(trimmed) }
            }
        }
        .padding(24)
        .onAppear { goal = current }
    }
}

// Нижняя панель со списком вариантов, выбранный отмечен галочкой
private struct OptionsSheet<T: Hashable>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let options: [T]
    let selected: T
    let label: (T) -> String
    let onPick: (T) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.titleLarge).foregroundStyle(Palette.ink).padding(.horizontal, 12).padding(.bottom, 8)
            ForEach(options, id: \.self) { option in
                let isSelected = option == selected
                Button {
                    if isSelected { dismiss() } else { onPick(option) }
                } label: {
                    HStack {
                        Text(label(option)).font(.bodyLarge).foregroundStyle(isSelected ? Palette.indigo : Palette.ink)
                        Spacer()
                        if isSelected { Image(systemName: "checkmark").foregroundStyle(Palette.indigo) }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(isSelected ? Palette.indigoSoft : .clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.pressable)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.top, 24)
    }
}

private struct ReminderTimeSheet: View {
    @Environment(\.dismiss) private var dismiss
    let current: Int
    let onSave: (Int) -> Void
    @State private var time = Date()

    var body: some View {
        VStack(spacing: 12) {
            Text("Время напоминания").font(.titleLarge).foregroundStyle(Palette.ink)
            DatePicker("", selection: $time, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .environment(\.locale, Locale(identifier: "ru_RU"))
            HStack {
                TonalButton(text: "Отмена", color: Palette.ink, background: Palette.background, fillWidth: true) { dismiss() }
                TonalButton(text: "Готово", fillWidth: true) {
                    let c = Calendar.current.dateComponents([.hour, .minute], from: time)
                    onSave((c.hour ?? 0) * 60 + (c.minute ?? 0))
                }
            }
        }
        .padding(24)
        .onAppear {
            time = Calendar.current.date(bySettingHour: current / 60, minute: current % 60, second: 0, of: Date()) ?? Date()
        }
    }
}

// ---------- Редактирование профиля: фото и имя ----------

struct EditProfileView: View {
    @Environment(MentorViewModel.self) private var vm
    let onClose: () -> Void

    @State private var name = ""
    @State private var processing = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var pickerOpen = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Button(action: onClose) {
                    Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold)).foregroundStyle(Palette.ink)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Назад")
                Text("Редактировать профиль").font(.titleLarge).foregroundStyle(Palette.ink)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            ScrollView {
                VStack(spacing: 16) {
                    Button { pickerOpen = true } label: {
                        UserAvatar(name: name.isEmpty ? nil : name, file: vm.avatarFile, size: 128)
                            .overlay {
                                if processing {
                                    Circle().fill(.black.opacity(0.35))
                                    ProgressView().tint(.white).controlSize(.large)
                                }
                            }
                    }
                    .buttonStyle(.pressable)
                    .disabled(processing)

                    HStack(spacing: 8) {
                        TonalButton(text: vm.avatarFile == nil ? "Добавить фото" : "Изменить фото", icon: "camera.fill",
                                    enabled: !processing) { pickerOpen = true }
                        if vm.avatarFile != nil {
                            TonalButton(text: "Удалить", icon: "trash", color: Palette.coral, background: Palette.coralSoft,
                                        enabled: !processing) { vm.setAvatar(nil) }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Имя").font(.labelLarge).foregroundStyle(Palette.inkSoft).padding(.leading, 4)
                        AppTextField(placeholder: "Как к тебе обращаться?", text: $name)
                            .textContentType(.givenName)
                            .onChange(of: name) { _, new in if new.count > 40 { name = String(new.prefix(40)) } }
                        Text("Имя и фото хранятся только на этом устройстве и используются в приветствии.")
                            .font(.bodySmall).foregroundStyle(Palette.inkSoft).padding(.leading, 4)
                    }
                    .padding(.top, 4)
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)

            PrimaryButton(text: "Сохранить",
                          enabled: name.trimmingCharacters(in: .whitespaces) != (vm.userName ?? "") && !processing) {
                vm.updateName(name)
                onClose()
            }
            .padding(20)
        }
        .background(Palette.background.ignoresSafeArea())
        .onAppear { name = vm.userName ?? "" }
        // системный выбор фото: разрешение на доступ к галерее не нужно
        .photosPicker(isPresented: $pickerOpen, selection: $pickerItem, matching: .images)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            processing = true
            Task {
                defer { processing = false; pickerItem = nil }
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else { throw CocoaError(.fileReadUnknown) }
                    vm.setAvatar(try await AvatarStore.save(data))
                } catch {
                    vm.avatarFailed()
                }
            }
        }
    }
}
