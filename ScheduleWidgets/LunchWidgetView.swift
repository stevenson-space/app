import ScheduleKit
import SwiftUI
import WidgetKit

struct LunchWidgetView: View {
    let entry: LunchTimelineEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    private var large: Bool { family == .systemLarge }
    private var accent: Color {
        guard renderingMode == .fullColor, contrast != .increased else { return .primary }
        return colorScheme == .dark
            ? Color(red: 0.55, green: 0.82, blue: 0.60)
            : Color(red: 0.20, green: 0.49, blue: 0.29)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: large ? 14 : 10) {
            header
            if let menu = entry.lunch?.menu, !menu.sections.isEmpty {
                if large {
                    fullMenu(menu)
                } else if let section = menu.sections.first(where: { $0.station == entry.station }), !section.items.isEmpty {
                    category(section)
                } else {
                    empty(title: "Not on today’s menu", detail: "Check the app for more options.")
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
        HStack(alignment: .firstTextBaseline) {
            Label(large ? "Today’s lunch" : "LUNCH", systemImage: "fork.knife")
                .font(large ? .headline : .caption2.weight(.bold))
                .tracking(large ? 0 : 1.2)
                .foregroundStyle(accent)
                .widgetAccentable()
            Spacer(minLength: 4)
            Text(dateLabel)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
    }

    private var dateLabel: String {
        let day = entry.lunch?.day ?? DayKey(date: entry.date)
        var format = Date.FormatStyle.dateTime.month(.abbreviated).day()
        format.timeZone = SchoolTime.timeZone
        return (day.date() ?? entry.date).formatted(format)
    }

    private func category(_ section: LunchMenuSection) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(section.station.title, systemImage: section.station.icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            ViewThatFits(in: .vertical) {
                Text(section.items.joined(separator: " · "))
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(section.items.joined(separator: " · "))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("More in app ↗")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(section.station.title): \(section.items.joined(separator: ", "))")
    }

    private func fullMenu(_ menu: LunchMenuDay) -> some View {
        ViewThatFits(in: .vertical) {
            menuGrid(menu, spacing: 20)
            menuGrid(menu, spacing: 13)
            menuGrid(menu, spacing: 7)
            HStack(alignment: .top, spacing: 18) {
                menuColumn(menu, stations: [.comfort, .mindful, .international])
                menuColumn(menu, stations: [.sides, .soup, .special])
            }
            .fixedSize(horizontal: false, vertical: true)
            // A future longer menu or accessibility text must not silently clip.
            VStack(alignment: .leading, spacing: 8) {
                Text("Today’s categories").font(.headline)
                ForEach(menu.sections) { section in
                    Label(section.station.title, systemImage: section.station.icon)
                        .font(.subheadline)
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

    private func menuColumn(_ menu: LunchMenuDay, stations: [LunchMenuStation]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(stations, id: \.self) { station in
                if let section = menu.sections.first(where: { $0.station == station }) {
                    menuCell(section)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func menuGrid(_ menu: LunchMenuDay, spacing: CGFloat) -> some View {
        Grid(alignment: .topLeading, horizontalSpacing: 18, verticalSpacing: spacing) {
            // Three paired rows preserve reading order and balance longer sides.
            ForEach(menu.sections.filter { [.comfort, .sides, .international].contains($0.station) }) { section in
                GridRow(alignment: .top) {
                    menuCell(section)
                    if let paired = menu.sections.first(where: { $0.station == partner(for: section.station) }) {
                        menuCell(paired)
                    }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func partner(for station: LunchMenuStation) -> LunchMenuStation {
        switch station {
        case .comfort: .mindful
        case .sides: .soup
        default: .special
        }
    }

    private func menuCell(_ section: LunchMenuSection) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(section.station.title, systemImage: section.station.icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent)
                .widgetAccentable()
            Text(section.items.isEmpty ? "Not listed today" : section.items.joined(separator: " · "))
                .font(.subheadline.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
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
    var body: some View {
        LinearGradient(colors: [Color.primary.opacity(0.02), Color.green.opacity(0.14)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .background(.background)
    }
}

#Preview("Lunch · category", as: .systemSmall) {
    LunchCategoryWidget()
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
