import SwiftUI
import ScheduleKit

/// The student's standard day as the cards Home shows, with the name and room
/// typed straight into each one. Return walks down the list, so eight classes
/// are one run of typing. Anything a name and a room can't say (a free period,
/// a period-and-a-half class, an emoji) opens the same sheet My Schedule uses.
struct OnboardingClassesView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    let next: () -> Void

    enum Field: Hashable {
        case name(Int)
        case room(Int)
    }

    // Typed text is held here and saved when focus moves or the step is left,
    // not on every keystroke: each save reloads the widgets.
    @State private var names: [Int: String] = [:]
    @State private var rooms: [Int: String] = [:]
    @State private var loaded = false
    @State private var editing: EditorTarget?
    @FocusState private var focus: Field?

    var body: some View {
        let config = model.config
        let pref = config.timeFormat
        let blocks = standardTemplate(config: config, catalog: model.catalog)
        let classes = blocks.compactMap { $0.role == .classPeriod ? $0.customizationID.periodNumber : nil }

        OnboardingPage(isTyping: focus != nil) {
            OnboardingHeading(title: "Add your classes")

            VStack(spacing: 8) {
                ForEach(blocks) { block in
                    if block.role == .classPeriod, let period = block.customizationID.periodNumber {
                        ClassCard(
                            badge: block.spanLabel ?? String(period),
                            period: period,
                            emoji: emoji(for: period, config: config),
                            times: TimeDisplay.range(block.start, block.end, pref),
                            name: Binding(get: { names[period, default: ""] },
                                          set: { names[period] = $0 }),
                            room: Binding(get: { rooms[period, default: ""] },
                                          set: { rooms[period] = $0 }),
                            focus: $focus,
                            isLast: period == classes.last,
                            submit: { advance(from: $0, classes: classes) },
                            more: { edit(block) })
                    } else {
                        ScheduleCardRow(
                            emoji: ScheduleStyle.emoji(for: block, config: config),
                            title: block.displayName,
                            subtitle: TimeDisplay.range(block.start, block.end, pref),
                            periodLabel: block.periodID.periodNumber.map { block.spanLabel ?? String($0) },
                            showsPeriodBadge: true
                        ) {
                            MoreButton(subject: block.displayName) { edit(block) }
                        }
                    }
                }
            }

            Text("Leave any blank and fill them in later in Settings. For a free period, a period-and-a-half class or your own emoji, tap \(Image(systemName: "ellipsis")).")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                // The symbol has no spoken name; the buttons it stands for do.
                .accessibilityLabel("Leave any blank and fill them in later in Settings. For a free period, a period-and-a-half class or your own emoji, use More options.")
        } actions: {
            OnboardingPrimaryButton("Continue", action: leave)
        }
        .navigationTitle("Step 2 of 3")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { OnboardingProgress(step: 2) }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Skip", action: leave)
            }
        }
        .sheet(item: $editing) { target in
            BlockEditSheet(target: target)
                .id(target.id)
                .presentationDetents([.medium, .large])
        }
        .onAppear(perform: load)
        // The sheet saves a name of its own when it closes; pick that up.
        .onChange(of: config.customizations) { _, _ in load() }
        .onChange(of: focus) { _, _ in save() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { save() }
        }
        .onDisappear(perform: save)
    }

    // MARK: - Drafts

    private func load() {
        for period in UserConfig.periodRange {
            let saved = model.config.customization(for: .period(period))
            names[period] = saved?.name ?? ""
            rooms[period] = saved?.room ?? ""
        }
        loaded = true
    }

    private func save() {
        guard loaded else { return }
        model.updateConfig { config in
            for period in UserConfig.periodRange {
                let key = PeriodID.period(period).storageKey
                var details = config.customizations[key] ?? PeriodCustomization()
                details.name = names[period]?.nilIfBlank
                details.room = rooms[period]?.nilIfBlank
                if details.isEmpty {
                    config.customizations.removeValue(forKey: key)
                } else {
                    config.customizations[key] = details
                }
            }
        }
    }

    /// A chosen emoji, or the one the name suggests as it is typed.
    private func emoji(for period: Int, config: UserConfig) -> String {
        if let chosen = config.customization(for: .period(period))?.emoji?.nilIfBlank {
            return chosen
        }
        return ScheduleStyle.subjectEmoji(names[period]?.nilIfBlank)
    }

    // MARK: - Moving through the list

    /// Name, then room, then the next class down; the last room ends typing.
    private func advance(from field: Field, classes: [Int]) {
        switch field {
        case .name(let period):
            focus = .room(period)
        case .room(let period):
            let following = classes.firstIndex(of: period).map { $0 + 1 }
            focus = following.flatMap { classes.indices.contains($0) ? .name(classes[$0]) : nil }
        }
    }

    private func edit(_ block: ResolvedBlock) {
        focus = nil
        save()
        editing = EditorTarget(block: block)
    }

    /// Typing ends with the step. A field left focused takes the keyboard
    /// back when the student returns from the next one, over the actions:
    /// the page isn't moved clear of a keyboard that arrives that way.
    private func leave() {
        focus = nil
        save()
        next()
    }
}

/// One class, as a card that can be typed into: the same badge, emoji and
/// two-line shape as `ScheduleCardRow`, with fields where its text would be.
private struct ClassCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .subheadline) private var badgeSize = 44.0
    @ScaledMetric(relativeTo: .title2) private var emojiWidth = 36.0

    let badge: String
    let period: Int
    let emoji: String
    let times: String
    @Binding var name: String
    @Binding var room: String
    var focus: FocusState<OnboardingClassesView.Field?>.Binding
    let isLast: Bool
    let submit: (OnboardingClassesView.Field) -> Void
    let more: () -> Void

    private var ordinal: String { PeriodID.ordinal(period) }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // Identity above the fields, so the fixed columns don't crowd
                // out what is being typed.
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        identity
                        Spacer(minLength: 0)
                        moreButton
                    }
                    fields
                }
            } else {
                HStack(spacing: 12) {
                    identity
                    fields
                    moreButton
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .onboardingCard()
    }

    private var identity: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.primary.opacity(0.12))
                .frame(width: badgeSize, height: badgeSize)
                .overlay {
                    Text(badge)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(4)
                }
                .accessibilityHidden(true)

            Text(emoji)
                .font(.title2)
                .frame(width: emojiWidth)
                .contentTransition(.opacity)
                .animation(.snappy, value: emoji)
                .accessibilityHidden(true)
        }
    }

    private var fields: some View {
        // Time and room share a line until the text is too large for both.
        // Aligned by their tops: the field's frame is a little taller than the
        // time's, so centring them would lift the room off the time's baseline.
        let details = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 3))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 6))

        return VStack(alignment: .leading, spacing: 3) {
            // Vertical fields keep the keyboard up when Return moves on to
            // the next one, and let a long name wrap. Neither takes a line
            // limit: with one, the text hops up a couple of points the first
            // time its field is focused.
            TextField(namePrompt, text: $name, axis: .vertical)
                .font(.headline)
                .textInputAutocapitalization(.words)
                .submitLabel(.next)
                .focused(focus, equals: .name(period))
                .onReturn(in: $name) { submit(.name(period)) }
                .accessibilityLabel("\(ordinal) period class name")

            details {
                Text(times)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .fixedSize()
                if !dynamicTypeSize.isAccessibilitySize {
                    Text("·")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                TextField("Room", text: $room, axis: .vertical)
                    .submitLabel(isLast ? .done : .next)
                    .focused(focus, equals: .room(period))
                    .onReturn(in: $room) { submit(.room(period)) }
                    .accessibilityLabel("\(ordinal) period room")
            }
            .font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A prompt stays on one line. At accessibility sizes the full one is cut
    /// off, and the badge above the field already says which period it is.
    /// One word, to fit the narrowest phone at the largest size.
    private var namePrompt: String {
        dynamicTypeSize.isAccessibilitySize ? "Class" : "\(ordinal) period class"
    }

    private var moreButton: some View {
        MoreButton(subject: name.nilIfBlank ?? "\(ordinal) period", action: more)
    }
}

/// Opens the full editor for a period.
private struct MoreButton: View {
    let subject: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // A full-size target whose dots still sit near the card's edge.
        .padding(.trailing, -10)
        .accessibilityLabel("More options for \(subject)")
    }
}
