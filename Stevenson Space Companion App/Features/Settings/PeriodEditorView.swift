import SwiftUI
import ScheduleKit

/// The schedule editor: the student's standard day as cards — exactly what
/// Home shows — where tapping a card edits it. A 1½-period class is one card;
/// the leftover half period is its own card you turn into lunch or free.
struct PeriodEditorListView: View {
    @Environment(AppModel.self) private var model
    @State private var editing: EditorTarget?

    var body: some View {
        let config = model.config
        let pref = config.timeFormat
        let blocks = standardTemplate(config: config, catalog: model.catalog)

        ScrollView {
            VStack(spacing: 8) {
                ForEach(blocks) { block in
                    Button {
                        editing = EditorTarget(block: block)
                    } label: {
                        ScheduleCardRow(
                            emoji: ScheduleStyle.emoji(for: block, config: config),
                            title: block.displayName,
                            subtitle: subtitle(for: block, pref: pref)
                        ) {
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Customize Schedule")
        .sheet(item: $editing) { target in
            BlockEditSheet(target: target)
                .presentationDetents([.medium, .large])
        }
    }

    /// "Period 2 · 9:26 – 10:38 · 118" (span label replaces the period name
    /// for halves and merged 1½-period classes).
    private func subtitle(for block: ResolvedBlock, pref: TimeFormatPref) -> String {
        var parts = [block.spanLabel ?? "Period \(block.periodID.storageKey)"]
        parts.append(TimeDisplay.range(block.start, block.end, pref))
        if let room = block.room { parts.append(room) }
        return parts.joined(separator: " · ")
    }
}

/// What a tapped card edits: a class (by anchor), a whole period (uniform
/// lunch/free), or one half of a period.
enum EditorTarget: Identifiable {
    case classAnchor(Int)
    case fullPeriod(Int)
    case half(period: Int, half: Half)

    init(block: ResolvedBlock) {
        let number = block.periodID.periodNumber ?? 1
        if let half = block.half {
            self = .half(period: number, half: half)
        } else if block.role == .classPeriod {
            self = .classAnchor(number)
        } else {
            self = .fullPeriod(number)
        }
    }

    var id: String {
        switch self {
        case .classAnchor(let n): return "class-\(n)"
        case .fullPeriod(let n): return "full-\(n)"
        case .half(let p, let h): return "half-\(p)\(h.rawValue)"
        }
    }

    var period: Int {
        switch self {
        case .classAnchor(let n), .fullPeriod(let n): return n
        case .half(let p, _): return p
        }
    }
}

// MARK: - Edit sheet

struct BlockEditSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let target: EditorTarget

    @State private var name = ""
    @State private var room = ""
    @State private var emoji = ""
    @State private var showingEmojiPicker = false
    @State private var loaded = false

    private var number: Int { target.period }

    var body: some View {
        NavigationStack {
            Form {
                switch target {
                case .half(let period, let half):
                    halfContent(period: period, half: half)
                default:
                    kindSection
                    switch currentKind {
                    case .classwork:
                        classFields
                        lengthSection
                    case .lunch:
                        if UserConfig.advisoryPeriods.contains(number) {
                            advisorySection
                        }
                    case .free:
                        EmptyView()
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingEmojiPicker) {
                ClassEmojiPicker(selection: $emoji,
                                 automaticEmoji: ScheduleStyle.subjectEmoji(name))
                    .presentationDetents([.medium, .large])
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            let customization = model.config.customization(for: .period(number))
            name = customization?.name ?? ""
            room = customization?.room ?? ""
            emoji = customization?.emoji ?? ""
        }
        .onDisappear { saveText() }
    }

    private var title: String {
        if case .half(let p, let h) = target { return "\(p)\(h.rawValue)" }
        return "\(PeriodID.ordinal(number)) Period"
    }

    // MARK: Whole-period cards: what is this period?

    private enum CardKind: Hashable { case classwork, lunch, free }

    /// Which half advisory occupies when this period is an advisory+lunch
    /// pair; nil otherwise.
    private var advisoryPairHalf: Half? {
        let plan = model.config.plan(for: number)
        if plan.a == .advisory && plan.b == .lunch { return .a }
        if plan.b == .advisory && plan.a == .lunch { return .b }
        return nil
    }

    private var currentKind: CardKind {
        let plan = model.config.plan(for: number)
        // An advisory+lunch pair is still "my lunch period".
        if plan == PeriodPlan(a: .lunch, b: .lunch) || advisoryPairHalf != nil { return .lunch }
        if plan == PeriodPlan(a: .free, b: .free) { return .free }
        return .classwork
    }

    private var kindSection: some View {
        Section {
            Picker("This period is", selection: Binding(
                get: { currentKind },
                set: { newValue in
                    guard newValue != currentKind else { return }
                    saveText()
                    model.updateConfig { config in
                        switch newValue {
                        case .classwork:
                            config.setPlan(.standardClass(number), for: number)
                        case .lunch:
                            config.retractClassClaims(anchor: number)
                            config.lunch = SplitAssignment(basePeriod: number, choice: .full)
                        case .free:
                            config.retractClassClaims(anchor: number)
                            config.setPlan(PeriodPlan(a: .free, b: .free), for: number)
                        }
                    }
                })) {
                Text("Class").tag(CardKind.classwork)
                Text("Lunch").tag(CardKind.lunch)
                Text("Free").tag(CardKind.free)
            }
            .pickerStyle(.segmented)
        }
    }

    private var classFields: some View {
        Section {
            HStack(spacing: 12) {
                Button {
                    showingEmojiPicker = true
                } label: {
                    Text(emoji.nilIfBlank ?? ScheduleStyle.subjectEmoji(name))
                        .font(.title3)
                        .frame(width: 44, height: 44)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Choose class emoji")
                .accessibilityValue(emoji.isEmpty ? "Automatic" : emoji)
                TextField("Class name (e.g. AP Biology)", text: $name)
            }
            TextField("Room", text: $room)
        }
    }

    // MARK: Advisory (freshmen)

    /// On the lunch card (periods 4–6): advisory always pairs with lunch —
    /// it takes one half, lunch the other. Turning it off frees that half.
    private var advisorySection: some View {
        Section {
            Toggle("I have Advisory (freshmen)", isOn: Binding(
                get: { advisoryPairHalf != nil },
                set: { on in
                    model.updateConfig { config in
                        if on {
                            config.setPairedAdvisory(basePeriod: number, advisoryHalf: .a)
                        } else {
                            // This card is "my lunch period": dropping advisory
                            // hands its half back to lunch (a full period again).
                            let plan = config.plan(for: number)
                            if plan.a == .advisory { config.setSlot(period: number, half: .a, to: .lunch) }
                            if plan.b == .advisory { config.setSlot(period: number, half: .b, to: .lunch) }
                        }
                    }
                }))
            if advisoryPairHalf != nil {
                Picker("Advisory half", selection: Binding(
                    get: { advisoryPairHalf ?? .a },
                    set: { newHalf in
                        model.updateConfig { config in
                            config.setPairedAdvisory(basePeriod: number, advisoryHalf: newHalf)
                        }
                    })) {
                    Text("A (first half)").tag(Half.a)
                    Text("B (second half)").tag(Half.b)
                }
            }
        }
    }

    // MARK: Class length

    private var currentLength: ClassLength {
        model.config.classLength(anchor: number)
    }

    /// Extension is blocked by advisory, or by a lunch living exactly in the
    /// claimed half. A full-period lunch doesn't block — it shrinks to its
    /// other half to make way.
    private func blocker(inPeriod period: Int, half: Half) -> HalfSlotAssignment? {
        guard UserConfig.periodRange.contains(period) else { return nil }
        let plan = model.config.plan(for: period)
        let slot = plan.slot(half)
        if slot == .advisory { return .advisory }
        if slot == .lunch && plan != PeriodPlan(a: .lunch, b: .lunch) { return .lunch }
        return nil
    }

    @ViewBuilder
    private var lengthSection: some View {
        let forwardBlocker = number < UserConfig.periodRange.upperBound
            ? (currentLength == .extendsForward ? nil : blocker(inPeriod: number + 1, half: .a))
            : nil
        let backwardBlocker = number > UserConfig.periodRange.lowerBound
            ? (currentLength == .startsEarly ? nil : blocker(inPeriod: number - 1, half: .b))
            : nil
        let canForward = number < UserConfig.periodRange.upperBound && forwardBlocker == nil
        let canBackward = number > UserConfig.periodRange.lowerBound && backwardBlocker == nil

        Section {
            Picker("Length", selection: Binding(
                get: { currentLength },
                set: { applyLength($0) })) {
                Text("1 period").tag(ClassLength.standard)
                if canForward {
                    Text("1½ — runs into \(number + 1)A").tag(ClassLength.extendsForward)
                }
                if canBackward {
                    Text("1½ — starts in \(number - 1)B").tag(ClassLength.startsEarly)
                }
            }
            .pickerStyle(.menu)
        } footer: {
            if let forwardBlocker {
                Text("Can't run into \(number + 1)A — it holds your \(forwardBlocker == .lunch ? "lunch" : "advisory").")
            } else if let backwardBlocker {
                Text("Can't start in \(number - 1)B — it holds your \(backwardBlocker == .lunch ? "lunch" : "advisory").")
            } else if currentLength != .standard {
                Text("The leftover half period shows as its own card — tap it to make it lunch or free.")
            }
        }
    }

    private func applyLength(_ newLength: ClassLength) {
        guard newLength != currentLength else { return }
        saveText()
        model.updateConfig { config in
            config.setClassLength(anchor: number, newLength)
        }
    }

    // MARK: Half cards: what fills this half period?

    /// A half period is only ever lunch or free. Class extensions into a half
    /// are set from the class card's Length menu, never from here.
    @ViewBuilder
    private func halfContent(period: Int, half: Half) -> some View {
        let current = model.config.plan(for: period).slot(half)
        let otherHalf: Half = half == .a ? .b : .a
        let otherSlot = model.config.plan(for: period).slot(otherHalf)

        Section {
            Picker("During \(period)\(half.rawValue)", selection: Binding(
                get: { model.config.plan(for: period).slot(half) },
                set: { newValue in
                    guard newValue != current else { return }
                    model.updateConfig { config in
                        if newValue == .lunch {
                            // Lunch takes the whole period when the other half
                            // is already lunch, or holds only the period's
                            // phantom own-class leftover — nothing real to keep.
                            let wholePeriod = otherSlot == .lunch
                                || otherSlot == .classSlot(anchor: period)
                            let choice: HalfChoice = wholePeriod
                                ? .full
                                : (half == .a ? .a : .b)
                            config.lunch = SplitAssignment(basePeriod: period, choice: choice)
                        } else {
                            config.setSlot(period: period, half: half, to: newValue)
                            // Advisory never exists without lunch: freeing the
                            // paired lunch half frees the advisory half too.
                            if current == .lunch, otherSlot == .advisory {
                                config.setSlot(period: period, half: otherHalf, to: .free)
                            }
                        }
                    }
                })) {
                Text("Lunch").tag(HalfSlotAssignment.lunch)
                Text("Free").tag(HalfSlotAssignment.free)
                if current != .lunch && current != .free {
                    Text(fallbackLabel(for: current)).tag(current)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } footer: {
            if current == .advisory {
                Text("Advisory pairs with lunch in the other half and doesn't meet on Fridays.")
            }
        }

        // Lunch and advisory can swap sides: picking a half for the tapped
        // block moves the paired occupant (or a free half) to the opposite
        // side. Hidden when the other half belongs to a class.
        let canPickHalf = (current == .lunch && (otherSlot == .advisory || otherSlot == .free))
            || (current == .advisory && otherSlot == .lunch)
        if canPickHalf {
            Section {
                Picker(current == .advisory ? "Advisory half" : "Lunch half", selection: Binding(
                    get: { half },
                    set: { (newHalf: Half) in
                        guard newHalf != half else { return }
                        model.updateConfig { config in
                            if current == .advisory {
                                config.setPairedAdvisory(basePeriod: period,
                                                         advisoryHalf: newHalf)
                            } else if otherSlot == .advisory {
                                config.setPairedAdvisory(basePeriod: period,
                                                         advisoryHalf: newHalf == .a ? .b : .a)
                            } else {
                                config.lunch = SplitAssignment(basePeriod: period,
                                                               choice: newHalf == .a ? .a : .b)
                            }
                        }
                        // The block moved: this sheet describes a position,
                        // not the block — close it so the swap is visible.
                        dismiss()
                    })) {
                    Text("A (first half)").tag(Half.a)
                    Text("B (second half)").tag(Half.b)
                }
                .pickerStyle(.menu)
            } footer: {
                if current == .advisory {
                    Text("Lunch takes the other half.")
                } else if otherSlot == .advisory {
                    Text("Advisory takes the other half.")
                }
            }
        }

        // Freshman advisory rides on the lunch half: it claims the other half
        // of the same period. Shown for every lunch half in 4–6 so it's
        // discoverable, but disabled while that half belongs to a class.
        if current == .lunch, UserConfig.advisoryPeriods.contains(period) {
            let canToggle = otherSlot == .free || otherSlot == .advisory
            Section {
                Toggle("I have Advisory (freshmen)", isOn: Binding(
                    get: { otherSlot == .advisory },
                    set: { on in
                        model.updateConfig { config in
                            if on {
                                config.setPairedAdvisory(basePeriod: period,
                                                         advisoryHalf: otherHalf)
                            } else {
                                config.setSlot(period: period, half: otherHalf, to: .free)
                            }
                        }
                    }))
                .disabled(!canToggle)
            } footer: {
                if otherSlot == .advisory {
                    Text("Advisory holds \(period)\(otherHalf.rawValue) and doesn't meet on Fridays — lunch fills the whole period then.")
                } else if canToggle {
                    Text("Freshmen: advisory takes \(period)\(otherHalf.rawValue), the other half of this period.")
                } else {
                    let owner = otherSlot.classAnchor.map { className($0) } ?? "another block"
                    Text("Advisory would take \(period)\(otherHalf.rawValue), which belongs to \(owner). Free that half first.")
                }
            }
        }
    }

    private func className(_ anchor: Int) -> String {
        model.config.customization(for: .period(anchor))?.name?.nilIfBlank
            ?? "\(PeriodID.ordinal(anchor)) Period class"
    }

    /// A stored value the picker wouldn't normally offer (migrated half-lunch
    /// data, or a neighbor whose class was reshaped since).
    private func fallbackLabel(for slot: HalfSlotAssignment) -> String {
        switch slot {
        case .classSlot(let anchor) where anchor == number:
            return "\(className(number)) (this half)"
        case .classSlot(let anchor):
            return className(anchor)
        case .lunch: return "Lunch"
        case .advisory: return "Advisory"
        case .free: return "Free"
        }
    }

    private func saveText() {
        guard loaded else { return }
        model.updateConfig { config in
            let key = PeriodID.period(number).storageKey
            let customization = PeriodCustomization(name: name.nilIfBlank,
                                                    room: room.nilIfBlank,
                                                    emoji: emoji.nilIfBlank)
            if customization.isEmpty {
                config.customizations.removeValue(forKey: key)
            } else {
                config.customizations[key] = customization
            }
        }
    }
}

private struct ClassEmojiPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: String
    let automaticEmoji: String

    private let columns = [GridItem(.adaptive(minimum: 44), spacing: 10)]

    private static let categories: [(title: String, emoji: [String])] = [
        ("Business & Careers", [
            "💼", "💰", "📈", "⚖️", "🚗", "🛠️", "🏗️", "💇", "🚒"
        ]),
        ("Math & Science", [
            "📐", "📊", "⚛️", "🧪", "🧬", "🔬", "🔭", "🌱", "🌋", "🫀", "🧠"
        ]),
        ("Computers & Engineering", [
            "💻", "⚙️", "⚡", "📱", "🎮", "🔐", "🖨️", "🥽"
        ]),
        ("English, Languages & History", [
            "📚", "📝", "📰", "🌍", "🗣️", "📜", "🏛️"
        ]),
        ("Art, Music & Theatre", [
            "🎨", "🖌️", "🏺", "💎", "📷", "🎬", "🎭", "🩰", "🎵", "🎹", "🎸", "🎻", "🎺", "🎤"
        ]),
        ("Food, Fashion & Family", [
            "🍳", "🥗", "🧵", "🧸", "🏠", "🧑‍🏫", "🍔"
        ]),
        ("PE, Health & Outdoors", [
            "🏃", "🏋️", "🏊", "🧘", "🧗", "🩺", "☀️"
        ]),
        ("School & Support", [
            "✏️", "🎓", "🎯", "📣", "🥳", "🤝"
        ])
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    automaticOption

                    ForEach(Self.categories, id: \.title) { category in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(category.title)
                                .font(.headline)

                            LazyVGrid(columns: columns, spacing: 10) {
                                ForEach(category.emoji, id: \.self) { emoji in
                                    Button {
                                        selection = emoji
                                        dismiss()
                                    } label: {
                                        Text(emoji)
                                            .font(.title2)
                                            .frame(maxWidth: .infinity, minHeight: 44)
                                            .background {
                                                if selection == emoji {
                                                    RoundedRectangle(cornerRadius: 10)
                                                        .fill(Color.accentColor.opacity(0.16))
                                                }
                                            }
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Choose \(emoji)")
                                    .accessibilityAddTraits(selection == emoji ? .isSelected : [])
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("Choose an Emoji")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var automaticOption: some View {
        Button {
            selection = ""
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Text(automaticEmoji)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Automatic")
                        .font(.headline)
                    Text("Matches your class name")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if selection.isEmpty {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(14)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection.isEmpty ? .isSelected : [])
    }
}

extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }
}
