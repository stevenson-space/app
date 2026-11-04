import SwiftUI
import ScheduleKit

/// The one visual for a schedule block everywhere in the app: the period as a
/// varsity number, the class emoji and name, the time-and-room line, and a
/// trailing cue. Home renders the live day with it; the editor renders the
/// standard-day template. Inks come from the ground it sits on.
struct ScheduleRow<Trailing: View>: View {
    enum Emphasis {
        case normal
        /// Finished blocks on a live day.
        case past
        /// Sewn on as a patch: the block happening now, or the one a passing
        /// period leads to.
        case patch
    }

    @Environment(\.jacketGround) private var ground
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .headline) private var periodColumnWidth = 60.0

    /// The physical period ("1", "3–4A"), independent of the class name.
    var periodLabel: String?
    var emoji: String?
    let title: String
    let subtitle: String
    var emphasis: Emphasis = .normal
    var minimumHeight: CGFloat = 0
    @ViewBuilder var trailing: Trailing

    var body: some View {
        // At accessibility sizes the period sits above the name so the fixed
        // column doesn't crowd out the class name and time.
        let stacks = dynamicTypeSize.isAccessibilitySize
        let layout = stacks
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 0))

        layout {
            Text(periodLabel ?? "")
                .font(.varsity(.headline))
                .tracking(-0.2)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(titleInk)
                .frame(width: stacks ? nil : periodColumnWidth, alignment: .leading)
                .accessibilityHidden(periodLabel == nil)

            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        if let emoji {
                            Text(emoji)
                                .font(.subheadline)
                                .accessibilityHidden(true)
                        }
                        Text(title)
                            .font(.headline.weight(emphasis == .past ? .medium : .semibold))
                            .foregroundStyle(titleInk)
                    }
                    Text(subtitle)
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(secondaryInk)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                trailing
            }
        }
        .padding(.vertical, emphasis == .patch ? 12 : 11)
        .frame(minHeight: minimumHeight)
        .padding(.horizontal, emphasis == .patch ? 12 : 0)
        .background {
            if emphasis == .patch {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(patchFill)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .inset(by: 4)
                    .stroke(patchInk.opacity(0.38),
                            style: StrokeStyle(lineWidth: 1.5, dash: [4, 3.5]))
            }
        }
        .padding(.horizontal, emphasis == .patch ? -12 : 0)
        .environment(\.rowInk, titleInk)
    }

    // MARK: Inks

    private var titleInk: Color {
        switch emphasis {
        case .normal: ground.ink
        case .past: ground.ink2
        case .patch: patchInk
        }
    }

    private var secondaryInk: Color {
        switch emphasis {
        case .normal, .past: ground.ink2
        case .patch: patchInk2
        }
    }

    /// The field's patch is chenille with green lettering; the gold side's
    /// patch is green with chenille lettering.
    private var patchFill: Color {
        switch ground {
        case .field: Jacket.chenille
        case .gold: Jacket.field
        case .lining: Jacket.accent
        }
    }

    private var patchInk: Color {
        switch ground {
        case .field: Color(red: 0.114, green: 0.353, blue: 0.212)
        case .gold: Jacket.chenille
        case .lining: Jacket.onAccent
        }
    }

    private var patchInk2: Color {
        switch ground {
        case .field: Color(red: 0.243, green: 0.380, blue: 0.286)
        case .gold: Jacket.chenille2
        case .lining: Jacket.onAccent.opacity(0.85)
        }
    }
}

extension EnvironmentValues {
    /// The row's title ink, so trailing cues can match a patch.
    @Entry var rowInk: Color = .primary
}

/// The small caps cue at the end of a row: Now, Next, or "in 45m".
struct RowCue: View {
    @Environment(\.jacketGround) private var ground
    @Environment(\.rowInk) private var rowInk

    let text: String
    /// Caps label on a patch; a plain live-coloured time otherwise.
    var onPatch = false

    var body: some View {
        if onPatch {
            Text(text)
                .jacketLabel()
                .foregroundStyle(rowInk)
        } else {
            Text(text)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(ground.live)
        }
    }
}

#if DEBUG
private struct ScheduleRowExamples: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ScheduleRow(periodLabel: "1", emoji: "📚", title: "AP English Language",
                            subtitle: "8:30 – 9:21 · 2108", emphasis: .past) { }
                ScheduleRow(periodLabel: "3–4A", emoji: "⚛️", title: "AP Physics C",
                            subtitle: "10:18 – 11:30 · 1616", emphasis: .patch) {
                    RowCue(text: "Now", onPatch: true)
                }
                ScheduleRow(periodLabel: "4B", title: "Lunch", subtitle: "11:37 – 11:57") {
                    RowCue(text: "In 45m")
                }
                ScheduleRow(title: "Assembly", subtitle: "10:06 – 10:46") { }
            }
            .padding(20)
        }
        .background(Jacket.field)
        .environment(\.jacketGround, .field)
    }
}

#Preview("Rows · Field") {
    ScheduleRowExamples()
}

#Preview("Rows · Large text") {
    ScheduleRowExamples().dynamicTypeSize(.accessibility3)
}
#endif
