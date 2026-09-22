import SwiftUI

/// The one visual for a schedule block everywhere in the app: emoji, name,
/// time-and-room line, optional period label and trailing chip. Home renders
/// the live day with it; the editor renders the standard-day template with it.
struct ScheduleCardRow<Trailing: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .subheadline) private var periodColumnWidth = 44.0

    let emoji: String
    let title: String
    let subtitle: String
    /// Home's physical period or split-period range, independent of the class name.
    var periodLabel: String? = nil
    /// Home shows a special-event badge even when a block has no period number.
    var showsPeriodBadge = false
    var minimumHeight: CGFloat = 0
    var dimmed = false
    /// Tint of the "happening now" state; nil for every other card.
    var highlightTint: Color? = nil
    @ViewBuilder var trailing: Trailing

    private var hasPeriodColumn: Bool { periodLabel != nil || showsPeriodBadge }

    private var badgeTint: Color {
        highlightTint ?? .primary
    }

    private var periodBadge: some View {
        Circle()
            .fill(badgeTint.opacity(0.12))
            .frame(width: periodColumnWidth, height: periodColumnWidth)
            .overlay {
                Group {
                    if let periodLabel {
                        Text(periodLabel)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    } else {
                        Image(systemName: "sparkles")
                    }
                }
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(badgeTint)
                .padding(4)
            }
            .accessibilityHidden(periodLabel == nil)
    }

    var body: some View {
        // At accessibility sizes, put the identity above the details so the
        // fixed columns don't crowd out the class name and time.
        let layout = dynamicTypeSize.isAccessibilitySize && hasPeriodColumn
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(spacing: 12))

        layout {
            HStack(spacing: 8) {
                if hasPeriodColumn {
                    periodBadge
                }

                Text(emoji)
                    .font(.title2)
                    .frame(width: 36)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(hasPeriodColumn ? nil : 1)
                Text(subtitle)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(hasPeriodColumn ? nil : 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(minHeight: minimumHeight)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(highlightTint.map { AnyShapeStyle($0.opacity(0.16)) }
                      ?? AnyShapeStyle(Color(.secondarySystemGroupedBackground)))
        )
        .opacity(dimmed ? 0.7 : 1)
    }
}

#if DEBUG
private struct ScheduleCardExamples: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                ScheduleCardRow(emoji: "💻", title: "AP CS P", subtitle: "8:30 – 9:21 · 3012",
                                periodLabel: "1", dimmed: true) { }
                ScheduleCardRow(emoji: "⚛️", title: "AP Physics C", subtitle: "10:18 – 11:30 · 1616",
                                periodLabel: "3–4A", highlightTint: .blue) {
                    Text("NOW")
                        .font(.caption.bold())
                        .foregroundStyle(.blue)
                }
                ScheduleCardRow(emoji: "🍔", title: "Lunch", subtitle: "11:37 – 11:57",
                                periodLabel: "4B") { }
                ScheduleCardRow(emoji: "🥳", title: "Free Period", subtitle: "2:38 – 3:25",
                                periodLabel: "8") { }
                ScheduleCardRow(emoji: "🎉", title: "Activity", subtitle: "10:06 – 10:46",
                                showsPeriodBadge: true) { }
                ScheduleCardRow(emoji: "📣", title: "Assembly", subtitle: "10:06 – 10:46",
                                showsPeriodBadge: true) { }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
    }
}

#Preview("Home cards · Dark") {
    ScheduleCardExamples().preferredColorScheme(.dark)
}

#Preview("Home cards · Light") {
    ScheduleCardExamples().preferredColorScheme(.light)
}

#Preview("Home cards · Large text") {
    ScheduleCardExamples().dynamicTypeSize(.accessibility3)
}
#endif
