import Foundation

/// Shared cache loading and serving-day rules for the app and widgets.
public enum LunchMenuLoader {
    /// Nil until a refresh has succeeded, and for a cache this version cannot
    /// read: versions before the API cached a rotation manifest instead.
    public static func load(cachedData: Data?) -> LunchMenu? {
        cachedData.flatMap { try? LunchMenuParser.parse($0) }
    }

    /// The published menu, on days the app's own calendar serves lunch. The
    /// calendar includes the student's overrides, which the API cannot know.
    public static func menu(_ menu: LunchMenu?, for day: DayKey, inputs: ResolverInputs) -> LunchMenuDay? {
        let timeline = resolveDay(day, inputs: inputs)
        guard timeline.isSchoolDay, timeline.family != .summer else { return nil }
        return menu?.menu(for: day)
    }
}
