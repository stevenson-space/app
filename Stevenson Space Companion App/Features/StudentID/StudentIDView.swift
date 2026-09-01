import PhotosUI
import SwiftUI
import ScheduleKit

/// The complete student-ID setup flow. The scanner is intentionally kept out
/// of the view hierarchy: this view owns only the transient picker, loading,
/// review, and error state for one setup attempt.
struct StudentIDView: View {
    @Environment(AppModel.self) private var model

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var scanTask: Task<Void, Never>?
    @State private var state: StudentIDFlowState = .idle
    @State private var deletionConfirmationPresented = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Student ID")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .toolbarColorScheme(.light, for: .navigationBar)
                .background(StudentIDPalette.canvas.ignoresSafeArea())
                .preferredColorScheme(.light)
        }
        .alert("Delete saved ID?", isPresented: $deletionConfirmationPresented) {
            Button("Delete ID", role: .destructive) {
                deleteSavedID()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the saved number and portrait from this device. You can scan the ID again later.")
        }
        .onDisappear {
            scanTask?.cancel()
            scanTask = nil
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle:
            if let profile = model.studentIDProfile {
                StudentIDDisplayView(profile: profile)
            } else {
                captureContent(errorMessage: nil)
            }

        case .capture:
            captureContent(errorMessage: nil)

        case .scanning:
            StudentIDScanningView()

        case .review(let draft):
            StudentIDReviewView(
                profile: draft.profile,
                onCancel: cancelReview,
                onSave: saveReviewedProfile)

        case .failed(let message):
            if let profile = model.studentIDProfile {
                VStack(spacing: 0) {
                    StudentIDDisplayView(profile: profile)
                    StudentIDInlineError(message: message, retry: beginReplacement)
                }
            } else {
                captureContent(errorMessage: message)
            }
        }
    }

    @ViewBuilder
    private func captureContent(errorMessage: String?) -> some View {
        StudentIDCaptureView(
            errorMessage: errorMessage,
            onRetry: clearError,
            picker: picker)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        switch state {
        case .idle, .failed:
            if model.studentIDProfile != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            beginReplacement()
                        } label: {
                            Label("Replace ID", systemImage: "arrow.triangle.2.circlepath")
                        }

                        Button(role: .destructive) {
                            deletionConfirmationPresented = true
                        } label: {
                            Label("Delete ID", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .accessibilityLabel("Student ID actions")
                    }
                    .accessibilityIdentifier("student-id-actions-menu")
                }
            }

        case .capture, .scanning, .review:
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel", action: cancelSetup)
                    .accessibilityIdentifier("student-id-cancel")
            }
        }
    }

    private var picker: some View {
        let canChoosePhoto: Bool
        switch state {
        case .idle, .capture:
            canChoosePhoto = true
        case .scanning, .review, .failed:
            canChoosePhoto = false
        }

        return PhotosPicker(
            selection: $selectedPhoto,
            matching: .images,
            photoLibrary: .shared()) {
                Label("Choose an ID photo", systemImage: "photo.on.rectangle.angled")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
            }
            .buttonStyle(.borderedProminent)
            .tint(StudentIDPalette.deepGreen)
            .disabled(!canChoosePhoto)
            .accessibilityIdentifier("student-id-choose-photo")
            .accessibilityHint("Select one photo from your library. Barcode and text verification is required before saving.")
            .onChange(of: selectedPhoto) { _, item in
                guard let item else { return }
                scanTask?.cancel()
                scanTask = Task { @MainActor in await scan(item) }
            }
    }

    private func scan(_ item: PhotosPickerItem) async {
        state = .scanning

        do {
            guard let imageData = try await item.loadTransferable(type: Data.self) else {
                throw StudentIDUIError.unreadablePhoto
            }

            let result = try await StudentIDScanner().scan(imageData: imageData)
            try Task.checkCancellation()

            // `StudentIDScanResult` is deliberately converted immediately.
            // The source image only lives in this task and is never assigned to
            // state or passed to the persistence boundary.
            let profile = makeProfile(from: result)
            state = .review(StudentIDReviewDraft(profile: profile))
        } catch is CancellationError {
            // View-driven cancellation is not an error state.
            state = .idle
        } catch {
            state = .failed(Self.userFacingScanError(for: error))
        }

        // Re-selecting the same library item must start a new scan, and the
        // picker item itself is not retained beyond this operation.
        selectedPhoto = nil
        scanTask = nil
    }

    private func makeProfile(from result: StudentIDScanResult) -> StudentIDProfile {
        StudentIDProfile(
            studentNumber: result.studentNumber,
            displayName: result.suggestedName,
            portraitJPEGData: result.portraitJPEGData)
    }

    private func saveReviewedProfile(_ profile: StudentIDProfile, name: String) throws {
        var editedProfile = profile
        editedProfile.displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        editedProfile.updatedAt = Date()
        try model.saveStudentID(editedProfile)
        state = .idle
    }

    private func beginReplacement() {
        state = .capture
    }

    private func cancelSetup() {
        scanTask?.cancel()
        scanTask = nil
        selectedPhoto = nil
        state = .idle
    }

    private func cancelReview() {
        cancelSetup()
    }

    private func clearError() {
        state = .idle
    }

    private func deleteSavedID() {
        do {
            try model.deleteStudentID()
            state = .idle
        } catch {
            state = .failed(Self.userFacingStorageError(for: error))
        }
    }

    private static func userFacingScanError(for error: Error) -> String {
        if let uiError = error as? StudentIDUIError {
            return uiError.localizedDescription
        }
        if let localized = (error as? LocalizedError)?.errorDescription,
           !localized.isEmpty {
            return localized
        }
        return "We couldn’t verify that image. Choose a clear photo where the barcode and student number are both visible, then try again."
    }

    private static func userFacingStorageError(for error: Error) -> String {
        if let storageError = error as? StudentIDStoreError {
            return storageError.localizedDescription
        }
        return "The saved ID could not be changed. Please try again."
    }
}

private enum StudentIDFlowState {
    case idle
    case capture
    case scanning
    case review(StudentIDReviewDraft)
    case failed(String)
}

private struct StudentIDReviewDraft {
    let profile: StudentIDProfile
}

private enum StudentIDUIError: Error, LocalizedError {
    case unreadablePhoto

    var errorDescription: String? {
        switch self {
        case .unreadablePhoto:
            return "That photo could not be read. Choose another image and try again."
        }
    }
}

private struct StudentIDCaptureView<Picker: View>: View {
    let errorMessage: String?
    let onRetry: () -> Void
    let picker: Picker

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                captureHeader
                privacyCard
                verificationNotice
                picker
                Text("Use one clear image. The original photo is discarded after analysis and is never saved.")
                    .font(.footnote)
                    .foregroundStyle(StudentIDPalette.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .background(StudentIDPalette.canvas)
        .safeAreaInset(edge: .top, spacing: 0) {
            if let errorMessage {
                StudentIDInlineError(message: errorMessage, retry: onRetry)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }
        }
    }

    private var captureHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                Circle()
                    .fill(StudentIDPalette.gold.opacity(0.24))
                    .frame(width: 68, height: 68)
                Image(systemName: "person.text.rectangle")
                    .font(.system(size: 29, weight: .semibold))
                    .foregroundStyle(StudentIDPalette.deepGreen)
            }
            .accessibilityHidden(true)

            Text("Keep your ID ready")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(StudentIDPalette.primaryText)

            Text("Create a fast, easy-to-scan digital version of your Stevenson ID.")
                .font(.body)
                .foregroundStyle(StudentIDPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Private on-device setup", systemImage: "lock.shield.fill")
                .font(.headline)
                .foregroundStyle(StudentIDPalette.deepGreen)

            privacyRow(
                icon: "photo.badge.plus",
                title: "Use the image you already have",
                detail: "A photo of a physical ID or an Infinite Campus screenshot works.")

            privacyRow(
                icon: "iphone.gen3",
                title: "Barcode + text are checked here",
                detail: "Analysis stays on this device; no image is uploaded.")

            privacyRow(
                icon: "trash.slash",
                title: "The original is not retained",
                detail: "Only the verified number, name, and optional portrait are saved after you confirm.")
        }
        .padding(18)
        .background(StudentIDPalette.deepGreen.opacity(0.075))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(StudentIDPalette.deepGreen.opacity(0.14), lineWidth: 1)
        }
    }

    private func privacyRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(StudentIDPalette.deepGreen)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(StudentIDPalette.primaryText)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(StudentIDPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var verificationNotice: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text("Barcode + text verification is required")
                    .font(.subheadline.weight(.semibold))
                Text("Choosing a photo starts on-device analysis. Nothing can be saved unless the visible number matches the barcode.")
                    .font(.footnote)
                    .foregroundStyle(StudentIDPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: "checkmark.shield.fill")
                .font(.title3)
                .foregroundStyle(StudentIDPalette.deepGreen)
        }
        .padding(16)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(StudentIDPalette.line, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("student-id-verification-notice")
    }
}

private struct StudentIDScanningView: View {
    var body: some View {
        VStack(spacing: 22) {
            ProgressView()
                .controlSize(.large)
                .tint(StudentIDPalette.deepGreen)

            VStack(spacing: 8) {
                Text("Checking your ID…")
                    .font(.title2.weight(.bold))
                Text("Reading the barcode and visible student number on this device.")
                    .font(.body)
                    .foregroundStyle(StudentIDPalette.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Label("Your original image is not saved", systemImage: "lock.fill")
                .font(.footnote.weight(.medium))
                .foregroundStyle(StudentIDPalette.deepGreen)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(StudentIDPalette.canvas)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Checking your ID. Reading the barcode and visible student number on this device.")
        .accessibilityIdentifier("student-id-scanning")
    }
}

private struct StudentIDReviewView: View {
    let profile: StudentIDProfile
    let onCancel: () -> Void
    let onSave: (StudentIDProfile, String) throws -> Void

    @State private var displayName: String
    @State private var saveError: String?

    init(profile: StudentIDProfile,
         onCancel: @escaping () -> Void,
         onSave: @escaping (StudentIDProfile, String) throws -> Void) {
        self.profile = profile
        self.onCancel = onCancel
        self.onSave = onSave
        _displayName = State(initialValue: profile.displayName ?? "")
    }

    private var trimmedName: String {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isValidName: Bool {
        !trimmedName.isEmpty &&
            trimmedName.count <= StudentIDProfile.maxDisplayNameLength &&
            !trimmedName.contains(where: { $0 == "\n" || $0 == "\r" || $0 == "\t" })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                reviewHeader
                portraitPreview
                nameEditor
                verifiedNumber
                verificationExplanation
                if let saveError {
                    Label(saveError, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("student-id-save-error")
                }
                saveButton
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .background(StudentIDPalette.canvas)
    }

    private var reviewHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Check your details")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(StudentIDPalette.primaryText)
            Text("The number below was matched between the barcode and the ID text. You can adjust the name shown on your digital ID.")
                .font(.body)
                .foregroundStyle(StudentIDPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var portraitPreview: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Portrait")
                .font(.headline)
                .foregroundStyle(StudentIDPalette.primaryText)

            StudentIDPortraitView(data: profile.portraitJPEGData, size: 112)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var nameEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Name shown on your ID")
                .font(.headline)
            TextField("Enter your name", text: $displayName)
                .textContentType(.name)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(StudentIDPalette.line, lineWidth: 1)
                }
                .accessibilityIdentifier("student-id-display-name")
        }
    }

    private var verifiedNumber: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Verified student number")
                    .font(.headline)
                Spacer(minLength: 8)
                Label("Locked", systemImage: "lock.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(StudentIDPalette.deepGreen)
            }

            HStack(spacing: 12) {
                Image(systemName: "number.square.fill")
                    .font(.title3)
                    .foregroundStyle(StudentIDPalette.gold)
                    .accessibilityHidden(true)
                Text(profile.studentNumber)
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(StudentIDPalette.primaryText)
                Spacer()
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(StudentIDPalette.deepGreen)
                    .accessibilityHidden(true)
            }
            .padding(16)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(StudentIDPalette.deepGreen.opacity(0.26), lineWidth: 1.5)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Verified student number")
            .accessibilityValue(profile.studentNumber)
            .accessibilityHint("This value is locked because it was matched by barcode and text analysis.")
            .accessibilityIdentifier("student-id-verified-number")
        }
    }

    private var verificationExplanation: some View {
        Label {
            Text("Verified successfully")
                .font(.subheadline.weight(.semibold))
        } icon: {
            Image(systemName: "checkmark.shield.fill")
        }
        .foregroundStyle(StudentIDPalette.deepGreen)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StudentIDPalette.deepGreen.opacity(0.09))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var saveButton: some View {
        Button {
            do {
                try onSave(profile, trimmedName)
                saveError = nil
            } catch {
                saveError = error.localizedDescription
            }
        } label: {
            Text("Save ID")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
        }
        .buttonStyle(.borderedProminent)
        .tint(StudentIDPalette.deepGreen)
        .disabled(!isValidName)
        .accessibilityIdentifier("student-id-save")
        .accessibilityHint(isValidName
                           ? "Save your verified digital ID"
                           : "Enter a valid name before saving")
    }
}

private struct StudentIDInlineError: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Couldn’t finish", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.red)
            Text(message)
                .font(.footnote)
                .foregroundStyle(StudentIDPalette.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Button("Try another photo", action: retry)
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("student-id-retry")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

#Preview("Student ID setup") {
    StudentIDCapturePreview()
}

private struct StudentIDCapturePreview: View {
    var body: some View {
        StudentIDCaptureView(
            errorMessage: nil,
            onRetry: {},
            picker: Button("Choose a preview image") {}
                .buttonStyle(.borderedProminent))
    }
}
