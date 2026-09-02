import PhotosUI
import ScheduleKit
import SwiftUI
import StudentIDKit
import UniformTypeIdentifiers

/// The ID tab: import a Student Profile screenshot once, then have a clean,
/// scannable card two taps away for the rest of the year.
struct StudentIDView: View {
    @Environment(AppModel.self) private var model

    @State private var isPickerPresented = false
    @State private var pickedItem: PhotosPickerItem?
    @State private var stage: StudentIDImportStage?
    @State private var isScanning = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let card = model.studentID {
                        savedCard(card)
                    } else {
                        emptyState
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("ID")
            .toolbar {
                if model.studentID != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button {
                                isPickerPresented = true
                            } label: {
                                Label("Replace Screenshot", systemImage: "photo.badge.arrow.down")
                            }
                            Button(role: .destructive) {
                                model.removeStudentID()
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
        .sheet(isPresented: isImporting) {
            StudentIDImportSheet(stage: stage ?? .processing,
                                 onSave: save,
                                 onChooseAnother: chooseAnother)
        }
        .fullScreenCover(isPresented: $isScanning) {
            if let card = model.studentID {
                StudentIDScanView(card: card)
            }
        }
    }

    // MARK: - Saved

    private func savedCard(_ card: StudentIDCard) -> some View {
        VStack(spacing: 18) {
            StudentIDCardView(content: .card(card, photo: model.studentIDPhoto))
                .onTapGesture { isScanning = true }
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Opens the barcode full screen for scanning")

            Button {
                isScanning = true
            } label: {
                Label("Show for Scanning", systemImage: "barcode.viewfinder")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(StevensonPalette.accent)

            VStack(spacing: 6) {
                Text("Imported \(card.importedAt.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if model.studentIDIsFromAnEarlierSchoolYear, let year = card.schoolYearLabel {
                    Label("This ID was imported for the \(year) school year. "
                          + "Import a fresh screenshot if yours has changed.",
                          systemImage: "calendar.badge.exclamationmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 20) {
            StudentIDCardView(content: .placeholder)
                .opacity(0.5)
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text("Add your student ID")
                    .font(.title2.weight(.bold))
                Text("Import one screenshot from Infinite Campus and the app rebuilds "
                     + "your ID here, sharp and ready to scan.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 8)

            VStack(alignment: .leading, spacing: 14) {
                step(1, "Open Infinite Campus and go to Student Profile.")
                step(2, "Screenshot the page, including the barcode.")
                step(3, "Import it below. Your name and number are read from it.")
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground)))

            VStack(spacing: 10) {
                Button {
                    isPickerPresented = true
                } label: {
                    Label("Choose Screenshot", systemImage: "photo.on.rectangle")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(StevensonPalette.accent)

                PasteButton(supportedContentTypes: [.image], payloadAction: paste)
                    .buttonBorderShape(.capsule)
                    .labelStyle(.titleAndIcon)
            }

            Text("Nothing leaves your phone. The screenshot itself is not saved \u{2014} "
                 + "only your name, number, and photo.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(StevensonPalette.accent))
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Import flow

    private var isImporting: Binding<Bool> {
        Binding(get: { stage != nil }, set: { if !$0 { stage = nil } })
    }

    private func load(_ item: PhotosPickerItem?) {
        guard let item else { return }
        stage = .processing
        Task {
            defer { pickedItem = nil }
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                stage = .failed(StudentIDImportError.unreadableImage.description)
                return
            }
            await extract(from: data)
        }
    }

    private func paste(_ providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }
        stage = .processing
        _ = provider.loadDataRepresentation(for: .image) { data, _ in
            Task { @MainActor in
                guard let data else {
                    stage = .failed(StudentIDImportError.unreadableImage.description)
                    return
                }
                await extract(from: data)
            }
        }
    }

    /// Vision runs off the main actor: the package is not MainActor-isolated, so
    /// awaiting it hops off and the sheet keeps animating while it works.
    private func extract(from data: Data) async {
        do {
            stage = .review(try await StudentIDExtractor.extract(from: data))
        } catch let error as StudentIDImportError {
            stage = .failed(error.description)
        } catch {
            stage = .failed("Something went wrong reading that screenshot.")
        }
    }

    private func save(_ extraction: StudentIDExtraction) {
        model.saveStudentID(extraction)
        stage = nil
    }

    private func chooseAnother() {
        stage = nil
        isPickerPresented = true
    }
}

#Preview {
    StudentIDView()
        .environment(AppModel(store: SharedStore(defaults: UserDefaults(suiteName: "student-id-preview")!)))
}
