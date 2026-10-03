import ScheduleKit
import SwiftUI
import WidgetKit

struct LunchWidgetView: View {
    let entry: LunchTimelineEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.colorSchemeContrast) private var contrast

    private var large: Bool { family == .systemLarge }
    private var accent: Color {
        guard entry.lunch?.isServingDay != false else { return .primary }
        guard renderingMode == .fullColor, contrast != .increased else { return .primary }
        return ScheduleStyle.tint(for: .classPeriod)
    }

    private func categoryAccent(_ station: LunchMenuStation) -> Color {
        guard renderingMode == .fullColor, contrast != .increased else { return .primary }
        return station.color
    }

    var body: some View {
        VStack(alignment: .leading, spacing: large ? 22 : 16) {
            header
            if let menu = entry.lunch?.menu, !menu.sections.isEmpty {
                if large {
                    fullMenu(menu)
                } else if let section = menu.sections.first(where: { $0.station == entry.station }), !section.items.isEmpty {
                    category(section)
                } else {
                    empty(title: "Menu not posted", detail: "Check the app for other options.")
                }
            } else if entry.lunch == nil {
                empty(title: "Let’s do lunch", detail: "Open the app to load your menu.")
            } else if entry.lunch?.isServingDay == false {
                empty(title: "No lunch today", detail: "The menu returns on school days.")
            } else {
                empty(title: "Menu unavailable", detail: "Open the app for the latest menu.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Fixed widget bounds cannot scroll. Keep full content available to VoiceOver.
        .dynamicTypeSize(...(large ? DynamicTypeSize.xxxLarge : .large))
        .accessibilityHint("Opens the lunch menu in Stevenson Space")
    }

    private var header: some View {
        Label(large ? "Today’s lunch" : "LUNCH", systemImage: "fork.knife")
            .font(large ? .headline : .caption2.weight(.bold))
            .tracking(large ? 0 : 1.2)
            .foregroundStyle(accent)
            .widgetAccentable()
            .lineLimit(1)
    }

    private func category(_ section: LunchMenuSection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(section.station.title, systemImage: section.station.icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(categoryAccent(section.station))
                .widgetAccentable()
                .lineLimit(1)
            ViewThatFits(in: .vertical) {
                if section.items.count == 1 {
                    menuOptions(section.items, spacing: 8)
                        .font(.headline)
                }
                menuOptions(section.items, spacing: 8)
                    .font(.subheadline.weight(.semibold))
                VStack(alignment: .leading, spacing: 4) {
                    Text(section.items.first ?? "Not listed today")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(section.items.count > 1 ? "+\(section.items.count - 1) more in app ↗" : "More in app ↗")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(section.station.title): \(section.items.joined(separator: ", "))")
    }

    private func fullMenu(_ menu: LunchMenuDay) -> some View {
        let rows = menuRows(menu)
        return ViewThatFits(in: .vertical) {
            // Only a complete menu needs to spread across the widget's height.
            if menu.sections.count == LunchMenuStation.allCases.count {
                spaciousMenu(menu)
            }
            menuGrid(menu, spacing: 20)
            menuGrid(menu, spacing: 13)
            menuGrid(menu, spacing: 7)
            HStack(alignment: .top, spacing: 18) {
                menuColumn(rows.compactMap { $0.sections.first })
                menuColumn(rows.compactMap { $0.sections.dropFirst().first })
            }
            .fixedSize(horizontal: false, vertical: true)
            // A future longer menu or accessibility text must not silently clip.
            VStack(alignment: .leading, spacing: 8) {
                Text("Today’s categories").font(.headline)
                ForEach(menu.sections) { section in
                    Label(section.station.title, systemImage: section.station.icon)
                        .font(.subheadline)
                        .foregroundStyle(categoryAccent(section.station))
                        .widgetAccentable()
                        .accessibilityLabel("\(section.station.title): \(section.items.joined(separator: ", "))")
                }
                Text("Open the app for the full menu ↗")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            Text("Open the app for today’s full menu ↗")
                .font(.headline)
                .accessibilityLabel(menu.sections.map {
                    "\($0.station.title): \($0.items.joined(separator: ", "))"
                }.joined(separator: ". "))
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func spaciousMenu(_ menu: LunchMenuDay) -> some View {
        let rows = menuRows(menu)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(rows, id: \.station) { row in
                VStack(alignment: .leading, spacing: 0) {
                    if row.station != rows.first?.station {
                        Spacer(minLength: 24)
                    }
                    HStack(alignment: .top, spacing: 22) {
                        ForEach(row.sections) { section in
                            menuCell(section, spacing: 9)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func menuColumn(_ sections: [LunchMenuSection]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(sections) { section in
                menuCell(section)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func menuGrid(_ menu: LunchMenuDay, spacing: CGFloat) -> some View {
        Grid(alignment: .topLeading, horizontalSpacing: 18, verticalSpacing: spacing) {
            // Pack available stations in reading order, leaving no holes between them.
            ForEach(menuRows(menu), id: \.station) { row in
                GridRow(alignment: .top) {
                    ForEach(row.sections) { section in
                        menuCell(section)
                    }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func menuRows(_ menu: LunchMenuDay) -> [(station: LunchMenuStation, sections: [LunchMenuSection])] {
        stride(from: 0, to: menu.sections.count, by: 2).map { index in
            let end = min(index + 2, menu.sections.count)
            return (station: menu.sections[index].station, sections: Array(menu.sections[index..<end]))
        }
    }

    private func menuCell(_ section: LunchMenuSection, spacing: CGFloat = 5) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            Label(section.station.title, systemImage: section.station.icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(categoryAccent(section.station))
                .widgetAccentable()
            menuOptions(section.items.isEmpty ? ["Not listed today"] : section.items, spacing: spacing)
                .font(.subheadline.weight(.medium))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func menuOptions(_ items: [String], spacing: CGFloat = 5) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func empty(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Spacer(minLength: 0)
            if large {
                Image(systemName: "takeoutbag.and.cup.and.straw")
                    .font(.largeTitle)
                    .foregroundStyle(accent).widgetAccentable()
                    .accessibilityHidden(true)
            }
            Text(title).font(.headline)
            Text(detail).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

struct LunchWidgetBackground: View {
    let entry: LunchTimelineEntry

    var body: some View {
        if entry.lunch?.isServingDay == false {
            RestingWidgetBackground()
        } else {
            Rectangle().fill(.background)
        }
    }
}

#Preview("Lunch · category", as: .systemSmall) {
    LunchMenuWidget()
} timeline: {
    LunchWidgetData.example()
    LunchWidgetData.example(station: .sides)
    LunchTimelineEntry(date: Date(), lunch: nil)
}

#Preview("Lunch · full menu", as: .systemLarge) {
    LunchMenuWidget()
} timeline: {
    LunchWidgetData.example()
    LunchTimelineEntry(date: Date(), lunch: nil)
}

#Preview("Lunch · missing stations", as: .systemLarge) {
    LunchMenuWidget()
} timeline: {
    LunchWidgetData.example(day: DayKey(year: 2026, month: 11, day: 16))
}
