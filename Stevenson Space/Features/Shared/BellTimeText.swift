import SwiftUI
import ScheduleKit

/// A bell time set as a varsity number, with the meridiem small beside it
/// ("10:30 AM" as a big 10:30 and a small AM) so the number fits the hero.
struct BellTimeText: View {
    let date: Date
    let pref: TimeFormatPref
    var size: CGFloat = 96
    var face: Color
    var edge: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(TimeDisplay.time(date, pref, includesMeridiem: false))
                .font(.varsity(size: size))
                .tracking(-size * 0.035)
                .monospacedDigit()
                .foregroundStyle(face)
                .twill(edge, x: size / 32, y: size / 24)
            if let meridiem {
                Text(meridiem)
                    .font(.varsity(.title2))
                    .foregroundStyle(face)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(TimeDisplay.time(date, pref))
    }

    private var meridiem: String? {
        guard !TimeDisplay.uses24Hour(pref) else { return nil }
        return SchoolTime.calendar.component(.hour, from: date) < 12 ? "AM" : "PM"
    }
}
