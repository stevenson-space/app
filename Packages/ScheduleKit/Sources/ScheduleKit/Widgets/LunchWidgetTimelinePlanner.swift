import Foundation

public struct LunchWidgetEntry: Sendable {
    public let date: Date
    public let day: DayKey
    public let menu: LunchMenuDay?
    public let isServingDay: Bool

    public init(date: Date, day: DayKey, menu: LunchMenuDay?, isServingDay: Bool) {
        self.date = date
        self.day = day
        self.menu = menu
        self.isServingDay = isServingDay
    }
}

public enum LunchWidgetTimelinePlanner {
    // Preserve the existing configurable small widget identity.
    public static let kind = "LunchCategoryWidget"
    public static let lunchURL = URL(string: "stevenson-space://lunch")!

    /// Daily entries keep the date correct while the app is suspended. The
    /// terminal empty entry prevents the last menu persisting beyond its day.
    public static func entries(from now: Date, cachedData: Data?, inputs: ResolverInputs) -> [LunchWidgetEntry] {
        let today = DayKey(date: now)
        return (0...7).map { offset in
            let day = today.advanced(by: offset)
            let timeline = resolveDay(day, inputs: inputs)
            let serving = timeline.isSchoolDay && timeline.family != .summer && !day.isWeekend
            let menu = offset < 7 ? LunchMenuLoader.menu(
                LunchMenuLoader.load(cachedData: cachedData, on: day), for: day, inputs: inputs) : nil
            return LunchWidgetEntry(date: offset == 0 ? now : day.date()!, day: day,
                                    menu: menu, isServingDay: serving)
        }
    }
}
