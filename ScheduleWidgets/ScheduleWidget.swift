import ScheduleKit
import OSLog
import SwiftUI
import WidgetKit

struct ScheduleWidgetEntry: TimelineEntry {
    let date: Date
    let schedule: WidgetScheduleEntry?
    let config: UserConfig
    #if DEBUG
    var clock = WidgetDebugClock()
    #endif

    var countdownInterval: ClosedRange<Date>? {
        guard let interval = schedule?.countdownInterval else { return nil }
        #if DEBUG
        return clock.realInterval(for: interval)
        #else
        return interval
        #endif
    }
}

struct ScheduleProvider: TimelineProvider {
    private static let logger = Logger(subsystem: "shankar.Stevenson-Space-Companion-App.ScheduleWidgets",
                                       category: "Timeline")

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
            #if DEBUG
            let scheduleNow = data.widgetClock.scheduleDate(for: now)
            #else
            let scheduleNow = now
            #endif
            let plan = WidgetTimelinePlanner.plan(from: scheduleNow, inputs: data.resolverInputs(catalog: catalog))
            #if DEBUG
            return (plan.entries.map {
                ScheduleWidgetEntry(date: data.widgetClock.realDate(for: $0.date),
                                    schedule: $0, config: data.config, clock: data.widgetClock)
            }, data.widgetClock.realDate(for: plan.reloadAfter))
            #else
            return (plan.entries.map {
                ScheduleWidgetEntry(date: $0.date, schedule: $0, config: data.config)
            }, plan.reloadAfter)
            #endif
        } catch {
            Self.logger.error("Unable to load shared schedule for widget: \(String(describing: error), privacy: .public)")
            return ([ScheduleWidgetEntry(date: now, schedule: nil, config: UserConfig())],
                    now.addingTimeInterval(15 * 60))
        }
    }

    static var weekendExample: ScheduleWidgetEntry {
        let now = DayKey(year: 2026, month: 9, day: 19).date(at: HourMinute(hour: 12, minute: 0))!
        let catalog = try! BellScheduleCatalog.loadBundled()
        let config = UserConfig()
        let plan = WidgetTimelinePlanner.plan(from: now, inputs: ResolverInputs(config: config, catalog: catalog))
        return ScheduleWidgetEntry(date: now, schedule: plan.entries[0], config: config)
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
                .containerBackground(for: .widget) { ScheduleWidgetBackground(entry: entry) }
                .widgetURL(WidgetTimelinePlanner.homeURL)
        }
        .configurationDisplayName("School Schedule")
        .description("Your current period, passing time, and the countdown to the next bell.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}
