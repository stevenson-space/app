import Foundation

/// Shared cache selection and serving-day rules for the app and widgets.
public enum LunchMenuLoader {
    public static func load(cachedData: Data?) -> LunchMenu? {
        load(cachedData: cachedData, bundledData: try? LunchMenuParser.bundledData())
    }

    static func load(cachedData: Data?, bundledData: Data?) -> LunchMenu? {
        let bundled = bundledData.flatMap { try? LunchMenuParser.parse($0) }
        let cached = cachedData.flatMap { try? LunchMenuParser.parse($0) }
        guard let bundled else { return cached }
        // A bundle update must not carry old dishes onto new rotation dates.
        guard let cached,
              cached.rotationSettings == bundled.rotationSettings else { return bundled }
        return cached
    }

    public static func menu(_ menu: LunchMenu?, for day: DayKey, inputs: ResolverInputs) -> LunchMenuDay? {
        let timeline = resolveDay(day, inputs: inputs)
        guard timeline.isSchoolDay, timeline.family != .summer else { return nil }
        return menu?.menu(for: day)
    }
}
