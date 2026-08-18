import SwiftUI
import ScheduleKit

/// Per-period personalization: custom name, room, free toggle. Keyed by period
/// identity, so names follow periods through finals reordering.
struct PeriodEditorListView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List(1...8, id: \.self) { number in
            NavigationLink {
                PeriodDetailView(number: number)
            } label: {
                row(for: number)
            }
        }
        .navigationTitle("Periods & Classes")
    }

    private func row(for number: Int) -> some View {
        let customization = model.config.customization(for: .period(number))
        let isFree = model.config.freePeriods.contains(number)
        return HStack {
            Text("\(PeriodID.ordinal(number))")
                .font(.subheadline.weight(.semibold))
                .frame(width: 44, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(customization?.name?.nilIfBlank ?? (isFree ? "Free Period" : "Not named"))
                    .foregroundStyle(customization?.name?.nilIfBlank == nil && !isFree ? .secondary : .primary)
                if let room = customization?.room?.nilIfBlank {
                    Text("Room \(room)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if isFree {
                Text("FREE")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.gray.opacity(0.2)))
            }
        }
    }
}

struct PeriodDetailView: View {
    @Environment(AppModel.self) private var model
    let number: Int

    @State private var name = ""
    @State private var room = ""
    @State private var isFree = false
    @State private var loaded = false

    var body: some View {
        Form {
            Section("Class") {
                TextField("Class name (e.g. AP Biology)", text: $name)
                    .onSubmit { save() }
                TextField("Room", text: $room)
                    .onSubmit { save() }
            }
            Section {
                Toggle("Free period", isOn: $isFree)
            }
        }
        .navigationTitle("\(PeriodID.ordinal(number)) Period")
        .onAppear {
            guard !loaded else { return }
            loaded = true
            let customization = model.config.customization(for: .period(number))
            name = customization?.name ?? ""
            room = customization?.room ?? ""
            isFree = model.config.freePeriods.contains(number)
        }
        // Text edits persist on commit or when the editor closes — not on every
        // keystroke, which would fire a store write + reschedule per character.
        .onChange(of: isFree) { save() }
        .onDisappear { save() }
    }

    private func save() {
        guard loaded else { return }
        model.updateConfig { config in
            let key = PeriodID.period(number).storageKey
            let customization = PeriodCustomization(
                name: name.nilIfBlank, room: room.nilIfBlank)
            if customization.isEmpty {
                config.customizations.removeValue(forKey: key)
            } else {
                config.customizations[key] = customization
            }
            if isFree {
                config.freePeriods.insert(number)
            } else {
                config.freePeriods.remove(number)
            }
        }
    }
}

extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }
}
