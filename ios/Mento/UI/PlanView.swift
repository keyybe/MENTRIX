import SwiftUI

// План: недели и уроки
struct PlanView: View {
    @Environment(MentorViewModel.self) private var vm
    let onStart: () -> Void

    var body: some View {
        if let plan = vm.plan {
            let currentId = vm.today?.mission?.id
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Мой план").font(.headlineSmall).foregroundStyle(Palette.ink)
                        Text("\(plan.area.title) · \(plan.weeks.count) нед. · цель: \(plan.goal)")
                            .font(.bodyMedium).foregroundStyle(Palette.inkSoft)
                    }
                    if let summary = plan.summary, !summary.isEmpty {
                        SummaryCard(text: summary)
                    }
                    ForEach(plan.weeks) { week in
                        WeekCard(week: week, currentId: currentId, onStart: onStart)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .background(Palette.background)
        }
    }
}

// Почему план устроен именно так – объяснение ИИ-наставника
private struct SummaryCard: View {
    let text: String

    var body: some View {
        SoftCard(color: Palette.accentSoft) {
            HStack(alignment: .top, spacing: 12) {
                IconTile(icon: "sparkles", tint: Palette.onAccent, background: Palette.accent, size: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Почему такой план").font(.titleSmall).foregroundStyle(Palette.ink)
                    Text(text).font(.bodyMedium).foregroundStyle(Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
        }
    }
}

private struct WeekCard: View {
    let week: WeekDto
    let currentId: String?
    let onStart: () -> Void

    var body: some View {
        let done = week.missions.filter { $0.status == .done }.count
        let highlighted = week.missions.contains { $0.id == currentId } || done == week.missions.count
        SoftCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    Text("\(week.index)")
                        .font(.titleMedium)
                        .foregroundStyle(highlighted ? Palette.onAccent : Palette.inkSoft)
                        .frame(width: 36, height: 36)
                        .background(highlighted ? AnyShapeStyle(Gradients.primary) : AnyShapeStyle(Palette.background),
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Неделя \(week.index)").font(.labelMedium).foregroundStyle(Palette.inkSoft)
                        Text(week.shortTitle).font(.titleMedium).foregroundStyle(Palette.ink)
                        if let why = week.why {
                            Text(why).font(.bodySmall).foregroundStyle(Palette.inkSoft)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer()
                    Text("\(done)/\(week.missions.count)").font(.labelLarge).foregroundStyle(Palette.inkSoft)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                SlimProgress(progress: week.missions.isEmpty ? 0 : Double(done) / Double(week.missions.count), height: 4)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 6)
                ForEach(week.missions) { m in
                    MissionRow(mission: m, current: m.id == currentId, onClick: onStart)
                }
            }
            .padding(.vertical, 8)
        }
    }
}

private struct MissionRow: View {
    let mission: MissionDto
    let current: Bool
    let onClick: () -> Void

    var body: some View {
        let done = mission.status == .done
        let (icon, tint, bg): (String, Color, Color) =
            if done { ("checkmark.circle.fill", Palette.mint, Palette.mintSoft) }
            else if current { ("play.fill", Palette.onAccent, Palette.accent) }
            else if mission.review { ("arrow.counterclockwise", Palette.amber, Palette.amberSoft) }
            else { ("lock.fill", Palette.inkSoft, Palette.background) }

        let row = HStack(spacing: 12) {
            IconTile(icon: icon, tint: tint, background: bg, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(mission.title).font(.titleSmall).foregroundStyle(done || current ? Palette.ink : Palette.inkSoft)
                Text(subtitle).font(.bodySmall).foregroundStyle(current ? Palette.accent : Palette.inkSoft)
            }
            Spacer(minLength: 0)
            if current { Image(systemName: "chevron.right").foregroundStyle(Palette.accent) }
        }
        .padding(10)
        .background(current ? Palette.accentSoft : .clear, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 8)

        if current {
            Button(action: onClick) { row }.buttonStyle(.pressable)
        } else {
            row
        }
    }

    private var subtitle: String {
        if current { return "Сейчас · \(mission.minutes) мин" }
        if mission.status == .todo, let from = mission.availableFrom { return "Повторение с \(from)" }
        if mission.review { return "Повторение" }
        if mission.status == .done { return "Пройдено" }
        return "\(mission.minutes) мин"
    }
}
