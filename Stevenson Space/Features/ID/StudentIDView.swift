import PhotosUI
import ScheduleKit
import SwiftUI
import StudentIDKit

/// The ID tab: import a Student Profile screenshot once, then have a clean,
/// scannable card two taps away for the rest of the year.
struct StudentIDView: View {
    @Environment(SceneNavigation.self) private var navigation
    @Environment(AppModel.self) private var model

    @State private var isPickerPresented = false
    @State private var pickedItem: PhotosPickerItem?
    @State private var stage: StudentIDImportStage?
    @State private var importID: UUID?
    @State private var removeFailed = false
    /// Set when the student asks for a different screenshot: the picker can only
    /// be presented once the import sheet has actually gone away.
    @State private var picksAgainOnDismiss = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let card = model.studentID {
                        savedCard(card)
                    } else {
                        emptyState
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .background(Jacket.lining)
            .environment(\.jacketGround, .lining)
            .navigationTitle("ID")
            .toolbar {
                if model.studentID != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            if model.studentIDPhoto != nil {
                                Toggle(isOn: Binding(
                                    get: { model.studentIDPhotoHidden },
                                    set: { model.setStudentIDPhotoHidden($0) })) {
                                    Label("Hide ID Photo", systemImage: "eye.slash")
                                }
                            }
                            Button {
                                isPickerPresented = true
                            } label: {
                                Label("Replace Screenshot", systemImage: "photo.badge.arrow.down")
                            }
                            Button(role: .destructive) {
                                do { try model.removeStudentID() }
                                catch { removeFailed = true }
                            } label: {
                                Label("Remove ID", systemImage: "trash")
                            }
                        } label: {
                            Label("ID options", systemImage: "ellipsis.circle")
                        }
                    }
                }
            }
        }
        .photosPicker(isPresented: $isPickerPresented, selection: $pickedItem, matching: .images)
        .onChange(of: pickedItem) { _, item in load(item) }
        .sheet(isPresented: isImporting, onDismiss: presentPickerIfAsked) {
            StudentIDImportSheet(stage: stage ?? .processing,
                                 onSave: save,
                                 onChooseAnother: chooseAnother)
        }
        .alert("Could not remove your ID", isPresented: $removeFailed) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Your ID is still saved on this phone. Try again when the device is unlocked.")
        }
    }

    // MARK: - Saved

    private func savedCard(_ card: StudentIDCard) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            StudentIDCardView(content: .card(card, photo: model.studentIDPhotoHidden ? nil : model.studentIDPhoto))
                .frame(maxWidth: .infinity)
                .onTapGesture { navigation.isStudentIDScanning = true }
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Opens the barcode full screen for scanning")

            Button {
                navigation.isStudentIDScanning = true
            } label: {
                Label("Show for Scanning", systemImage: "barcode.viewfinder")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .tint(Jacket.accent)
            .padding(.top, 24)

            Text("Tap the card to show the barcode full screen at full brightness.")
                .font(.subheadline)
                .foregroundStyle(Jacket.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)

            if model.studentIDIsFromAnEarlierSchoolYear, let year = card.schoolYearLabel {
                Label("This ID was imported for the \(year) school year. "
                      + "Import a fresh screenshot if yours has changed.",
                      systemImage: "calendar.badge.exclamationmark")
                    .font(.subheadline)
                    .foregroundStyle(Jacket.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)
            }

            VStack(spacing: 0) {
                if let year = card.schoolYearLabel {
                    fact("School year", year)
                }
                if model.studentIDPhoto != nil {
                    fact("Photo", model.studentIDPhotoHidden ? "Hidden" : "Shown")
                }
                fact("Stored", "On this iPhone only")
            }
            .padding(.top, 44)
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(spacing: 0) {
            StitchRule(JacketGround.lining.stitch)
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .foregroundStyle(Jacket.ink)
                Spacer(minLength: 12)
                Text(value)
                    .foregroundStyle(Jacket.ink2)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
            }
            .font(.body)
            .padding(.vertical, 13)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 0) {
            StudentIDCardView(content: .placeholder)
                .opacity(0.5)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)

            Text("Add your student ID")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Jacket.ink)
                .padding(.top, 28)
            Text("Import a screenshot from Infinite Campus to create a sharp, scannable ID.")
                .font(.subheadline)
                .foregroundStyle(Jacket.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            VStack(spacing: 0) {
                step(1, "Open Infinite Campus.")
                step(2, "Screenshot the homepage, including your student details and barcode.")
                step(3, "Import it below.")
            }
            .padding(.top, 24)

            Button {
                isPickerPresented = true
            } label: {
                Label("Choose Screenshot", systemImage: "photo.on.rectangle")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .tint(Jacket.accent)
            .padding(.top, 28)

            Text("Your ID is processed on this device and isn’t uploaded to us.")
                .font(.subheadline)
                .foregroundStyle(Jacket.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
        }
    }

    /// Numbered like the day's periods: a varsity number, then the step.
    private func step(_ number: Int, _ text: String) -> some View {
        VStack(spacing: 0) {
            StitchRule(JacketGround.lining.stitch)
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("\(number)")
                    .font(.varsity(.headline))
                    .foregroundStyle(Jacket.accent)
                    .frame(width: 36, alignment: .leading)
                Text(text)
                    .font(.body)
                    .foregroundStyle(Jacket.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 13)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Import flow

    private var isImporting: Binding<Bool> {
        Binding(get: { stage != nil }, set: { if !$0 { dismissImport() } })
    }

    private func beginImport() -> UUID {
        let id = UUID()
        importID = id
        stage = .processing
        return id
    }

    private func dismissImport() {
        importID = nil
        stage = nil
        pickedItem = nil
    }

    private func load(_ item: PhotosPickerItem?) {
        guard let item else { return }
        let id = beginImport()
        Task {
            let data = try? await item.loadTransferable(type: Data.self)
            guard importID == id else { return }
            pickedItem = nil
            guard let data else {
                stage = .failed(StudentIDImportError.unreadableImage.description)
                return
            }
            await extract(from: data, importID: id)
        }
    }

    /// Vision runs off the main actor: the package is not MainActor-isolated, so
    /// awaiting it hops off and the sheet keeps animating while it works.
    private func extract(from data: Data, importID id: UUID) async {
        do {
            let extraction = try await StudentIDExtractor.extract(from: data)
            guard importID == id else { return }
            stage = .review(extraction, photo: extraction.photoJPEG.flatMap(UIImage.init(data:)))
        } catch let error as StudentIDImportError {
            guard importID == id else { return }
            stage = .failed(error.description)
        } catch {
            guard importID == id else { return }
            stage = .failed("Something went wrong reading that screenshot.")
        }
    }

    private func save(_ extraction: StudentIDExtraction) throws {
        try model.saveStudentID(extraction)
        dismissImport()
    }

    private func chooseAnother() {
        picksAgainOnDismiss = true
        dismissImport()
    }

    private func presentPickerIfAsked() {
        guard picksAgainOnDismiss else { return }
        picksAgainOnDismiss = false
        isPickerPresented = true
    }
}

#Preview {
    let model = AppModel(store: SharedStore(
        defaults: UserDefaults(suiteName: "student-id-preview")!,
        secrets: InMemorySecretStore()))
    StudentIDView()
        .environment(model)
        .environment(SceneNavigation(model: model))
}
