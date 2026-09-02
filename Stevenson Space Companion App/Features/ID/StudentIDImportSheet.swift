import SwiftUI
import StudentIDKit

/// What the import is doing right now.
enum StudentIDImportStage {
    case processing
    case review(StudentIDExtraction)
    case failed(String)
}

/// Reads back what the screenshot gave up, and asks for a yes.
///
/// Every value here is text, never a field. The name and number come from the
/// screenshot or they do not appear at all — there is no path in this screen, or
/// anywhere else, that lets someone type their own.
struct StudentIDImportSheet: View {
    let stage: StudentIDImportStage
    let onSave: (StudentIDExtraction) -> Void
    let onChooseAnother: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .processing:
                    processing
                case .review(let extraction):
                    review(extraction)
                case .failed(let message):
                    failure(message)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Import ID")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if case .review(let extraction) = stage {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { onSave(extraction) }
                            .fontWeight(.semibold)
                    }
                }
            }
        }
    }

    // MARK: - Stages

    private var processing: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Reading your ID\u{2026}")
                .font(.headline)
            Text("Scanning the barcode and reading the page.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func review(_ extraction: StudentIDExtraction) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                StudentIDCardView(content: .card(extraction.card, photo: photo(extraction)))

                VStack(spacing: 0) {
                    detail("Name", extraction.card.fullName ?? "Not found")
                    Divider().padding(.leading, 16)
                    detail("Student number", extraction.card.idNumber)
                    if let grade = extraction.card.gradeLabel {
                        Divider().padding(.leading, 16)
                        detail("Grade", grade)
                    }
                    if let year = extraction.card.schoolYearLabel {
                        Divider().padding(.leading, 16)
                        detail("School year", year)
                    }
                }
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground)))

                if !warnings(extraction).isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(warnings(extraction), id: \.self) { warning in
                            Label(warning, systemImage: "exclamationmark.circle")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button("Choose a Different Screenshot", action: onChooseAnother)
                    .font(.subheadline)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
    }

    private func failure(_ message: String) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "barcode.viewfinder")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("Could not read that screenshot")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try Another Screenshot", action: onChooseAnother)
                .buttonStyle(.borderedProminent)
                .tint(StevensonPalette.accent)
                .padding(.top, 4)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Pieces

    private func detail(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.subheadline.weight(.medium))
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func photo(_ extraction: StudentIDExtraction) -> UIImage? {
        extraction.photoJPEG.flatMap(UIImage.init(data:))
    }

    /// Only the gaps a student can do something about are worth a line; a
    /// missing grade or school year is not worth re-taking a screenshot for.
    private func warnings(_ extraction: StudentIDExtraction) -> [String] {
        var messages: [String] = []
        if extraction.warnings.contains(.nameNotFound) {
            messages.append("Your name was not on the part of the page you captured. "
                            + "Screenshot the whole Student Profile to include it.")
        }
        if extraction.warnings.contains(.photoNotFound) {
            messages.append("No photo was found, so the card shows the school crest instead.")
        }
        return messages
    }
}
