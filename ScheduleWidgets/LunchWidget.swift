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
    static let title: LocalizedStringResource = "Lunch Category"
    static let description = IntentDescription("Choose the food category to show on your Home Screen.")

    @Parameter(title: "Food Category", default: .comfort)
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

    static func example(station: LunchMenuStation = .comfort) -> LunchTimelineEntry {
        let day = DayKey(year: 2026, month: 9, day: 3)
        let date = day.date()!
        return LunchTimelineEntry(date: date, lunch: LunchWidgetEntry(date: date, day: day,
            menu: (try? LunchMenuParser.loadBundled())?.menu(for: day), isServingDay: true), station: station)
    }
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

struct LunchMenuProvider: TimelineProvider {
    func placeholder(in context: Context) -> LunchTimelineEntry { LunchWidgetData.example() }

    func getSnapshot(in context: Context, completion: @escaping (LunchTimelineEntry) -> Void) {
        completion(context.isPreview ? LunchWidgetData.example() : LunchWidgetData.entries()[0])
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LunchTimelineEntry>) -> Void) {
        completion(Timeline(entries: LunchWidgetData.entries(), policy: .after(Date().addingTimeInterval(3600))))
    }
}

struct LunchCategoryWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: LunchWidgetTimelinePlanner.categoryKind,
                               intent: LunchCategoryIntent.self, provider: LunchCategoryProvider()) { entry in
            LunchWidgetView(entry: entry)
                .containerBackground(for: .widget) { LunchWidgetBackground(entry: entry) }
                .widgetURL(LunchWidgetTimelinePlanner.lunchURL)
        }
        .configurationDisplayName("Lunch Category")
        .description("Today’s lunch from your favorite category. Edit the widget to choose one.")
        .supportedFamilies([.systemSmall])
    }
}

struct LunchMenuWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: LunchWidgetTimelinePlanner.menuKind, provider: LunchMenuProvider()) { entry in
            LunchWidgetView(entry: entry)
                .containerBackground(for: .widget) { LunchWidgetBackground(entry: entry) }
                .widgetURL(LunchWidgetTimelinePlanner.lunchURL)
        }
        .configurationDisplayName("Today’s Lunch")
        .description("All six food categories, with room to see what’s on the menu.")
        .supportedFamilies([.systemLarge])
    }
}

@main
struct StevensonWidgetBundle: WidgetBundle {
    var body: some Widget {
        ScheduleWidget()
        LunchCategoryWidget()
        LunchMenuWidget()
    }
}
