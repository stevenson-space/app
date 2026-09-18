import ScheduleKit
import SwiftUI
import WidgetKit

struct ScheduleWidgetEntry: TimelineEntry {
    let date: Date
    let schedule: WidgetScheduleEntry?
    let config: UserConfig
}

struct ScheduleProvider: TimelineProvider {
    func placeholder(in context: Context) -> ScheduleWidgetEntry { Self.example }

    func getSnapshot(in context: Context, completion: @escaping (ScheduleWidgetEntry) -> Void) {
        completion(context.isPreview ? Self.example : entries(at: Date()).entries[0])
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ScheduleWidgetEntry>) -> Void) {
        let plan = entries(at: Date())
        completion(Timeline(entries: plan.entries, policy: .after(plan.reload)))
    }

    private func entries(at now: Date) -> (entries: [ScheduleWidgetEntry], reload: Date) {
        do {
            let data = try SharedStore.readScheduleData()
            let catalog = try BellScheduleCatalog.loadBundled()
            let plan = WidgetTimelinePlanner.plan(from: now, inputs: data.resolverInputs(catalog: catalog))
            return (plan.entries.map {
                ScheduleWidgetEntry(date: $0.date, schedule: $0, config: data.config)
            }, plan.reloadAfter)
        } catch {
            return ([ScheduleWidgetEntry(date: now, schedule: nil, config: UserConfig())],
                    DayKey(date: now).advanced(by: 1).date()!)
        }
    }

    static var example: ScheduleWidgetEntry {
        example(at: HourMinute(hour: 9, minute: 0))
    }

    static func example(at time: HourMinute, longName: Bool = false, room: String? = "2432") -> ScheduleWidgetEntry {
        var config = UserConfig()
        config.customizations["1"] = PeriodCustomization(
            name: longName ? "Advanced Topics in Environmental Science and Research" : "AP Biology",
            room: room, emoji: "🧬")
        let now = DayKey(year: 2026, month: 9, day: 14).date(at: time)!
        let catalog = try! BellScheduleCatalog.loadBundled()
        let plan = WidgetTimelinePlanner.plan(from: now, inputs: ResolverInputs(config: config, catalog: catalog))
        return ScheduleWidgetEntry(date: now, schedule: plan.entries[0], config: config)
    }
}

@main
struct ScheduleWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetTimelinePlanner.kind, provider: ScheduleProvider()) { entry in
            ScheduleWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
                .widgetURL(WidgetTimelinePlanner.homeURL)
        }
        .configurationDisplayName("School Schedule")
        .description("Your current period, passing time, and the countdown to the next bell.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}
