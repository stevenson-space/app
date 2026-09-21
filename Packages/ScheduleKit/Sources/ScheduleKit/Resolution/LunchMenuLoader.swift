import Foundation

/// Shared cache selection and serving-day rules for the app and widgets.
public enum LunchMenuLoader {
    public static func load(cachedData: Data?, on day: DayKey) -> LunchMenu? {
        let cached = cachedData.flatMap { try? LunchMenuParser.parse($0) }
        let bundled = try? LunchMenuParser.loadBundled()
        if let cached, cached.validFrom <= day, day <= cached.validTo { return cached }
        if let bundled, bundled.validFrom <= day, day <= bundled.validTo { return bundled }
        return [cached, bundled].compactMap { $0 }.max { $0.validTo < $1.validTo }
    }

    public static func menu(_ menu: LunchMenu?, for day: DayKey, inputs: ResolverInputs) -> LunchMenuDay? {
        let timeline = resolveDay(day, inputs: inputs)
        guard timeline.isSchoolDay, timeline.family != .summer else { return nil }
        return menu?.menu(for: day)
    }
}
