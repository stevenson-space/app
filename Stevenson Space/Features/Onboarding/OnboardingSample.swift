import Foundation
import ScheduleKit

/// One believable student's Monday for the tour's demos. It runs through the
/// same resolver as Home, so every time it shows is a real Standard bell.
enum OnboardingSample {
    /// A September Monday, forced to Standard so calendar data can't move it.
    static let day = DayKey(year: 2026, month: 9, day: 14)

    static let config: UserConfig = {
        var config = UserConfig()
        let classes: [(Int, String, String?)] = [
            (1, "AP Language", "1210"),
            (2, "Precalculus", "2216"),
            (3, "AP Chemistry", "1616"),
            (5, "Spanish 3", "1102"),
            (6, "AP World History", "2130"),
            (7, "Physical Education", nil),
        ]
        for (period, name, room) in classes {
            config.customizations[PeriodID.period(period).storageKey] =
                PeriodCustomization(name: name, room: room)
        }
        // Chemistry runs 3–4A with lunch in 4B, and 8th period is free.
        config.lunch = SplitAssignment(basePeriod: 4, choice: .b)
        config.setClassLength(anchor: 3, .extendsForward)
        config.freePeriods = [8]
        return config
    }()

    static func timeline(catalog: BellScheduleCatalog) -> DayTimeline {
        let standard = DayOverride(day: day, type: .bell(family: .standard, rotation: nil))
        return resolveDay(day, inputs: ResolverInputs(overrides: [day: standard],
                                                      config: config, catalog: catalog))
    }

    struct LunchApproach {
        let chemistry: ResolvedSpan
        let lunch: ResolvedSpan
        let afterLunch: ResolvedSpan?
    }

    /// The moments around lunch the countdown demo plays: the end of
    /// Chemistry, the passing period, and the start of Lunch.
    static func lunchApproach(catalog: BellScheduleCatalog) -> LunchApproach? {
        let moments = timeline(catalog: catalog).moments
        guard let index = moments.firstIndex(where: { $0.role == .lunch }), index > 0 else { return nil }
        return LunchApproach(chemistry: moments[index - 1], lunch: moments[index],
                             afterLunch: moments.indices.contains(index + 1) ? moments[index + 1] : nil)
    }
}
