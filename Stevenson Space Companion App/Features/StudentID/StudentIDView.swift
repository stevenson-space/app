import PhotosUI
import SwiftUI
import StudentIDKit

struct StudentIDView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    @State private var photoSelection: PhotosPickerItem?
    @State private var isPhotoPickerPresented = false
    @State private var isAnalyzing = false
    @State private var importError: String?
    @State private var editorDraft: StudentIDEditorDraft?
    @State private var isConfirmingRemoval = false
    @State private var displayController = StudentIDDisplayController()

    var body: some View {
        NavigationStack {
            Group {
                if isAnalyzing {
                    StudentIDAnalyzingView()
                } else if let profile = model.studentIDProfile {
                    savedID(profile)
                } else {
                    StudentIDEmptyState(
                        errorMessage: importError,
                        chooseScreenshot: { isPhotoPickerPresented = true },
                        enterManually: { editorDraft = .empty }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white.ignoresSafeArea())
            .navigationTitle("Student ID")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.white, for: .navigationBar, .tabBar)
            .toolbarBackground(.visible, for: .navigationBar, .tabBar)
            .toolbar {
                if let profile = model.studentIDProfile {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button {
                                editorDraft = StudentIDEditorDraft(profile: profile)
                            } label: {
                                Label("Edit Details", systemImage: "pencil")
                            }
                            Button {
                                isPhotoPickerPresented = true
                            } label: {
                                Label("Replace Screenshot", systemImage: "photo")
                            }
                            Divider()
                            Button(role: .destructive) {
                                isConfirmingRemoval = true
                            } label: {
                                Label("Remove ID", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .accessibilityLabel("Student ID options")
                    }
                }
            }
        }
        .preferredColorScheme(.light)
        .photosPicker(
            isPresented: $isPhotoPickerPresented,
            selection: $photoSelection,
            matching: .images
        )
        .sheet(item: $editorDraft) { draft in
            StudentIDEditorView(draft: draft)
                .environment(model)
        }
        .confirmationDialog(
            "Remove this student ID?",
            isPresented: $isConfirmingRemoval,
            titleVisibility: .visible
        ) {
            Button("Remove ID", role: .destructive) {
                model.removeStudentID()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The saved name and student number will be deleted from this device.")
        }
        .task(id: photoSelection) {
            guard let photoSelection else { return }
            await importScreenshot(photoSelection)
        }
        .onAppear { synchronizeDisplay() }
        .onDisappear { displayController.deactivate() }
        .onChange(of: scenePhase) { _, _ in synchronizeDisplay() }
        .onChange(of: model.studentIDProfile) { _, _ in synchronizeDisplay() }
        .onChange(of: isPhotoPickerPresented) { _, _ in synchronizeDisplay() }
        .onChange(of: isAnalyzing) { _, _ in synchronizeDisplay() }
        .onChange(of: editorDraft?.id) { _, _ in synchronizeDisplay() }
    }

    private func savedID(_ profile: StudentIDProfile) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                StudentIDCardView(profile: profile)
                    .frame(maxWidth: 430)

                Label("Screen brightness is raised while this ID is open.",
                      systemImage: "sun.max.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.top, 22)
            .padding(.bottom, 28)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func importScreenshot(_ item: PhotosPickerItem) async {
        importError = nil
        isAnalyzing = true
        defer {
            isAnalyzing = false
            photoSelection = nil
        }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw StudentIDAnalysisError.unreadableImage
            }
            let analysis = try await StudentIDAnalyzer.analyze(data)
            guard !Task.isCancelled else { return }
            editorDraft = StudentIDEditorDraft(analysis: analysis)
        } catch is CancellationError {
            return
        } catch {
            importError = (error as? LocalizedError)?.errorDescription
                ?? "The screenshot could not be analyzed. Try choosing it again."
        }
    }

    private func synchronizeDisplay() {
        let shouldBeScannerReady = model.studentIDProfile != nil
            && scenePhase == .active
            && !isPhotoPickerPresented
            && !isAnalyzing
            && editorDraft == nil

        if shouldBeScannerReady {
            displayController.activate()
        } else {
            displayController.deactivate()
        }
    }
}

struct StudentIDEmptyState: View {
    let errorMessage: String?
    let chooseScreenshot: () -> Void
    let enterManually: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Image(systemName: "person.text.rectangle.fill")
                    .font(.system(size: 58))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(StudentIDStyle.forestGreen)

                VStack(spacing: 9) {
                    Text("Keep your ID ready")
                        .font(.title2.bold())
                    Text("Choose a screenshot of your Infinite Campus student profile. Stevenson Space will read the barcode and rebuild it at scanner quality.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Button(action: chooseScreenshot) {
                    Label("Choose ID Screenshot", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(StudentIDStyle.forestGreen)
                .controlSize(.large)

                Button("Enter details manually", action: enterManually)
                    .font(.subheadline.weight(.medium))

                Label("The screenshot is analyzed on this device and is not saved.",
                      systemImage: "lock.shield.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                        .padding(12)
                        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .frame(maxWidth: 420)
            .padding(.horizontal, 28)
            .padding(.top, 58)
            .frame(maxWidth: .infinity)
        }
    }
}

struct StudentIDAnalyzingView: View {
    var body: some View {
        VStack(spacing: 18) {
            ProgressView()
                .controlSize(.large)
                .tint(StudentIDStyle.forestGreen)
            Text("Reading your ID…")
                .font(.headline)
            Text("Finding the Code 39 barcode and student name")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview("ID Setup") {
    StudentIDEmptyState(errorMessage: nil, chooseScreenshot: {}, enterManually: {})
        .preferredColorScheme(.light)
}

#Preview("Analyzing") {
    StudentIDAnalyzingView()
        .preferredColorScheme(.light)
}
