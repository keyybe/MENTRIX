import SwiftUI

private let dayLetters = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]

// Главный экран: что делать сейчас, как дела и что дальше. Сам урок открывается отдельным экраном.
struct HomeView: View {
    @Environment(MentorViewModel.self) private var vm
    let onStartLesson: () -> Void
    let onOpenChat: () -> Void
    let onOpenPlan: () -> Void

    var body: some View {
        let p = vm.progress
        let reviews = p?.reviewsDue ?? 0
        ScrollView {
            VStack(spacing: 16) {
                // приветствие и серия
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(greeting(vm.userName)).font(.headlineSmall).foregroundStyle(Palette.ink)
                        Text(vm.plan?.area.title ?? "").font(.bodyMedium).foregroundStyle(Palette.inkSoft)
                    }
                    Spacer()
                    InfoPill(icon: "flame.fill", text: "\(p?.streak ?? 0)", tint: Palette.amber, background: Palette.amberSoft)
                }

                if vm.offline {
                    SoftCard(color: Palette.coralSoft) {
                        HStack(spacing: 8) {
                            Image(systemName: "wifi.slash").font(.system(size: 15)).foregroundStyle(Palette.coral)
                            Text("Нет связи – показаны сохранённые данные").font(.bodySmall).foregroundStyle(Palette.coral)
                            Spacer(minLength: 0)
                            Button("Обновить") { vm.load() }.font(.labelLarge).foregroundStyle(Palette.coral)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }

                WeekStrip(activity: p?.weekActivity ?? [], doneToday: p?.doneToday == true)

                LessonHero(onStart: onStartLesson)

                // быстрые действия
                HStack(spacing: 12) {
                    QuickTile(
                        icon: "arrow.counterclockwise", tint: Palette.amber,
                        title: reviews > 0 ? "\(reviews) \(plural(reviews, "тема", "темы", "тем"))" : "Повторений нет",
                        subtitle: reviews > 0 ? "пора повторить" : "всё закреплено",
                        enabled: reviews > 0 && !vm.offline,
                        action: onStartLesson
                    )
                    QuickTile(
                        icon: "sparkles", tint: Palette.indigo,
                        title: "Ментор", subtitle: "спросить об уроке",
                        enabled: vm.today?.mission != nil && !vm.offline,
                        action: onOpenChat
                    )
                }

                if let week = currentWeek {
                    WeekProgressCard(week: week, onOpenPlan: onOpenPlan)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(Palette.background)
        .refreshable { await vm.load().value }
    }

    // Неделя текущего урока, а если план пройден – последняя
    private var currentWeek: WeekDto? {
        guard let weeks = vm.plan?.weeks else { return nil }
        let id = vm.today?.mission?.id
        return weeks.first { $0.missions.contains { $0.id == id } }
            ?? weeks.first { $0.missions.contains { $0.status == .todo } }
            ?? weeks.last
    }

    private func greeting(_ name: String?) -> String {
        let hello = switch Calendar.current.component(.hour, from: Date()) {
        case 5...11: "Доброе утро"
        case 12...17: "Добрый день"
        case 18...22: "Добрый вечер"
        default: "Доброй ночи"
        }
        guard let name, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return "\(hello)!" }
        return "\(hello), \(name)!"
    }
}

// Пн…Вс: закрашены дни с пройденным уроком, сегодняшний обведён
private struct WeekStrip: View {
    let activity: [Bool]
    let doneToday: Bool

    var body: some View {
        // weekday: 1 – воскресенье … 7 – суббота → индекс с понедельника
        let todayIndex = (Calendar.current.component(.weekday, from: Date()) + 5) % 7
        SoftCard {
            HStack {
                ForEach(0..<7, id: \.self) { i in
                    let done = (i < activity.count && activity[i]) || (i == todayIndex && doneToday)
                    let isToday = i == todayIndex
                    VStack(spacing: 6) {
                        Text(dayLetters[i]).font(.labelMedium).foregroundStyle(isToday ? Palette.indigo : Palette.inkSoft)
                        ZStack {
                            if done {
                                Circle().fill(Gradients.primary)
                                Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                            } else if isToday {
                                Circle().strokeBorder(Palette.indigo, lineWidth: 2)
                            } else {
                                Circle().fill(i < todayIndex ? Palette.line : Palette.background)
                            }
                        }
                        .frame(width: 34, height: 34)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 14)
        }
    }
}

// Главная карточка: урок дня и одна кнопка
private struct LessonHero: View {
    @Environment(MentorViewModel.self) private var vm
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let mission = vm.today?.mission {
                if vm.progress?.doneToday == true {
                    Label("Урок дня пройден", systemImage: "checkmark.circle.fill")
                        .font(.titleMedium).foregroundStyle(.white)
                    Text("Дальше: \(mission.title)").font(.headlineSmall).foregroundStyle(.white)
                    Text("Можно остановиться или пройти ещё один урок").font(.bodyMedium).foregroundStyle(.white.opacity(0.85))
                    HeroButton(text: "Ещё урок", action: onStart).padding(.top, 4)
                } else {
                    Text("\(mission.review ? "ПОВТОРЕНИЕ" : "УРОК ДНЯ") · \(mission.minutes) МИН")
                        .font(.labelMedium).foregroundStyle(.white.opacity(0.8))
                    Text(mission.title).font(.headlineMedium).foregroundStyle(.white)
                    Text(mission.topic).font(.bodyMedium).foregroundStyle(.white.opacity(0.85))
                    HeroButton(text: "Начать урок", action: onStart).padding(.top, 4)
                }
            } else {
                Image(systemName: "trophy.fill").font(.system(size: 32)).foregroundStyle(.white)
                Text("На сегодня всё").font(.headlineSmall).foregroundStyle(.white)
                Text(vm.today?.message ?? "Возвращайся завтра за новым уроком.")
                    .font(.bodyMedium).foregroundStyle(.white.opacity(0.85))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(Gradients.hero, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

// Белая кнопка на градиенте
private struct HeroButton: View {
    let text: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(text).font(.titleMedium)
                Image(systemName: "arrow.right").font(.system(size: 16, weight: .bold))
            }
            .foregroundStyle(Palette.indigo)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.pressable)
    }
}

private struct QuickTile: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        let color = enabled ? tint : Palette.inkSoft
        Button(action: action) {
            SoftCard {
                VStack(alignment: .leading, spacing: 10) {
                    IconTile(icon: icon, tint: color, background: color.opacity(0.12), size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.titleMedium).foregroundStyle(enabled ? Palette.ink : Palette.inkSoft)
                        Text(subtitle).font(.bodySmall).foregroundStyle(Palette.inkSoft)
                    }
                }
                .padding(16)
            }
        }
        .buttonStyle(.pressable)
        .disabled(!enabled)
    }
}

// Прогресс текущей недели плана – достижимая цель вместо процентов всего плана
private struct WeekProgressCard: View {
    let week: WeekDto
    let onOpenPlan: () -> Void

    var body: some View {
        let done = week.missions.filter { $0.status == .done }.count
        let total = week.missions.count
        Button(action: onOpenPlan) {
            SoftCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Неделя \(week.index)").font(.labelMedium).foregroundStyle(Palette.inkSoft)
                            Text(week.shortTitle).font(.titleMedium).foregroundStyle(Palette.ink)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(Palette.inkSoft)
                    }
                    SlimProgress(progress: total == 0 ? 0 : Double(done) / Double(total))
                    Text("\(done) из \(total) \(plural(total, "урока", "уроков", "уроков")) на этой неделе")
                        .font(.bodySmall).foregroundStyle(Palette.inkSoft)
                }
                .padding(18)
            }
        }
        .buttonStyle(.pressable)
        .accessibilityHint("Открыть план")
    }
}
