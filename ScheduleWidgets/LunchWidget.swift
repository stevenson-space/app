import AppIntents
import ScheduleKit
import SwiftUI
import WidgetKit

// Keep system-facing choices separate from the shared model's conformances.
enum LunchCategory: String, AppEnum {
    case comfort, mindful, sides, soup, international, special

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Food Category")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .comfort: "Comfort Food", .mindful: "Mindful", .sides: "Sides",
        .soup: "Soup", .international: "International", .special: "Special"
    ]

    var station: LunchMenuStation { LunchMenuStation(rawValue: rawValue)! }
}

struct LunchCategoryIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Lunch Menu"
    static let description = IntentDescription("See what's for lunch at a glance.")

    // Large widgets also show this picker: when a family's parameter summary
    // lists no parameters, iOS shows all of them instead of hiding them.
    @Parameter(title: "Food Category (Small Only)", default: .comfort)
    var category: LunchCategory
}

struct LunchTimelineEntry: TimelineEntry {
    let date: Date
    let lunch: LunchWidgetEntry?
    var station: LunchMenuStation = .comfort
}

enum LunchWidgetData {
    static func entries(station: LunchMenuStation = .comfort) -> [LunchTimelineEntry] {
        let now = Date()
        guard let data = try? SharedStore.readLunchWidgetData(),
              let catalog = try? BellScheduleCatalog.loadBundled() else {
            return [LunchTimelineEntry(date: now, lunch: nil, station: station)]
        }
        #if DEBUG
        let menuNow = data.schedule.widgetClock.scheduleDate(for: now)
        #else
        let menuNow = now
        #endif
        return LunchWidgetTimelinePlanner.entries(from: menuNow, cachedData: data.cachedMenu,
            inputs: data.schedule.resolverInputs(catalog: catalog)).map {
                #if DEBUG
                // Resolve the simulated day, but schedule WidgetKit transitions
                // on the real clock, just like the school schedule widget.
                let displayDate = data.schedule.widgetClock.realDate(for: $0.date)
                #else
                let displayDate = $0.date
                #endif
                return LunchTimelineEntry(date: displayDate, lunch: $0, station: station)
            }
    }

    /// The widget gallery and placeholders are drawn before any real menu can
    /// be read, so they show a fixed sample day.
    static func example(station: LunchMenuStation = .comfort,
                        omitting omitted: Set<LunchMenuStation> = []) -> LunchTimelineEntry {
        let day = DayKey(year: 2026, month: 9, day: 3)
        let date = day.date()!
        let menu = LunchMenuDay(day: day, sections: sampleSections.filter { !omitted.contains($0.station) })
        return LunchTimelineEntry(date: date, lunch: LunchWidgetEntry(date: date, day: day,
            menu: menu, isServingDay: true), station: station)
    }

    private static let sampleSections = [
        LunchMenuSection(station: .comfort, items: ["Tuna Noodle Casserole"]),
        LunchMenuSection(station: .mindful, items: ["Adobo Roasted Turkey Breast"]),
        LunchMenuSection(station: .sides, items: ["Roasted Corn", "Cauliflower"]),
        LunchMenuSection(station: .soup, items: ["Street Corn Soup", "Chicken Gumbo"]),
        LunchMenuSection(station: .international, items: ["Macaroni and Cheese Bowl"]),
        LunchMenuSection(station: .special, items: ["Nachos Thursday"]),
    ]
}

struct LunchCategoryProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> LunchTimelineEntry { LunchWidgetData.example() }

    func snapshot(for configuration: LunchCategoryIntent, in context: Context) async -> LunchTimelineEntry {
        context.isPreview ? LunchWidgetData.example(station: configuration.category.station)
            : LunchWidgetData.entries(station: configuration.category.station)[0]
    }

    func timeline(for configuration: LunchCategoryIntent, in context: Context) async -> Timeline<LunchTimelineEntry> {
        Timeline(entries: LunchWidgetData.entries(station: configuration.category.station),
                 policy: .after(Date().addingTimeInterval(3600)))
    }
}

struct LunchMenuWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: LunchWidgetTimelinePlanner.kind,
                               intent: LunchCategoryIntent.self, provider: LunchCategoryProvider()) { entry in
            LunchWidgetView(entry: entry)
                .containerBackground(for: .widget) { LunchWidgetBackground(entry: entry) }
                .widgetURL(LunchWidgetTimelinePlanner.lunchURL)
        }
        .configurationDisplayName("Lunch Menu")
        .description("See what's for lunch at a glance.")
        .supportedFamilies([.systemSmall, .systemLarge])
    }
}

@main
struct StevensonWidgetBundle: WidgetBundle {
    var body: some Widget {
        ScheduleWidget()
        LunchMenuWidget()
    }
}
