import SwiftUI

/// The one visual for a schedule block everywhere in the app: emoji, name,
/// time-and-room line, optional trailing chip. Home renders the live day with
/// it; the editor renders the standard-day template with it.
struct ScheduleCardRow<Trailing: View>: View {
    let emoji: String
    let title: String
    let subtitle: String
    var dimmed = false
    /// Tint of the "happening now" state; nil for every other card.
    var highlightTint: Color? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 14) {
            Text(emoji)
                .font(.title2)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(dimmed ? .secondary : .primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(highlightTint.map { AnyShapeStyle($0.opacity(0.16)) }
                      ?? AnyShapeStyle(Color(.secondarySystemGroupedBackground)))
        )
        .opacity(dimmed ? 0.5 : 1)
    }
}
