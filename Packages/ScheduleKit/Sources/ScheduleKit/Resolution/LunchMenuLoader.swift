import Foundation

/// Shared cache selection and serving-day rules for the app and widgets.
public enum LunchMenuLoader {
    public static func load(cachedData: Data?, on _: DayKey) -> LunchMenu? {
        let bundled = try? LunchMenuParser.loadBundled()
        // A bundle update must not carry old dishes onto new rotation dates.
        guard let bundled,
              let cached = cachedData.flatMap({ try? LunchMenuParser.parse($0) }),
              cached.validFrom == bundled.validFrom,
              cached.validTo == bundled.validTo,
              cached.semesterSwitch == bundled.semesterSwitch,
              cached.offset == bundled.offset else { return bundled }
        return cached
    }

    public static func menu(_ menu: LunchMenu?, for day: DayKey, inputs: ResolverInputs) -> LunchMenuDay? {
        let timeline = resolveDay(day, inputs: inputs)
        guard timeline.isSchoolDay, timeline.family != .summer else { return nil }
        return menu?.menu(for: day)
    }
}
