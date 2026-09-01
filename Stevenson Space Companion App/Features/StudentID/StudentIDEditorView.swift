import SwiftUI
import StudentIDKit

struct StudentIDEditorDraft: Identifiable {
    let id = UUID()
    var studentName: String
    var studentNumber: String
    let barcodeWasDetected: Bool
    let nameWasDetected: Bool

    init(profile: StudentIDProfile) {
        studentName = profile.studentName
        studentNumber = profile.studentNumber
        barcodeWasDetected = true
        nameWasDetected = true
    }

    init(analysis: StudentIDAnalysis) {
        studentName = analysis.suggestedName ?? ""
        studentNumber = analysis.barcodeValue ?? ""
        barcodeWasDetected = analysis.barcodeValue != nil
        nameWasDetected = analysis.suggestedName != nil
    }

    static var empty: StudentIDEditorDraft {
        StudentIDEditorDraft(analysis: StudentIDAnalysis(barcodeValue: nil, suggestedName: nil))
    }
}

struct StudentIDEditorView: View {
    private enum Field: Hashable { case name, number }

    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @State private var studentName: String
    @State private var studentNumber: String
    @FocusState private var focusedField: Field?

    let draft: StudentIDEditorDraft

    init(draft: StudentIDEditorDraft) {
        self.draft = draft
        _studentName = State(initialValue: draft.studentName)
        _studentNumber = State(initialValue: draft.studentNumber)
    }

    private var profile: StudentIDProfile {
        StudentIDProfile(studentName: studentName, studentNumber: studentNumber)
    }

    private var validationMessage: String? {
        if !studentNumber.isEmpty, !studentNumber.allSatisfy(\.isNumber) {
            return "Use the digits shown under Student Number in Infinite Campus."
        }
        return profile.validationMessage
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Student name", text: $studentName)
                        .textContentType(.name)
                        .focused($focusedField, equals: .name)

                    TextField("Student number", text: $studentNumber)
                        .keyboardType(.numberPad)
                        .textContentType(.none)
                        .focused($focusedField, equals: .number)
                        .onChange(of: studentNumber) { _, newValue in
                            let filtered = String(newValue.filter(\.isNumber).prefix(8))
                            if filtered != newValue { studentNumber = filtered }
                        }
                } header: {
                    Text("Confirm details")
                } footer: {
                    if !draft.barcodeWasDetected {
                        Label("The barcode was not detected. Enter the Student Number shown in Campus.",
                              systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    } else if !draft.nameWasDetected {
                        Text("Enter the student name exactly as it should appear on the ID.")
                    } else {
                        Text("Check both fields against Infinite Campus before saving.")
                    }
                }

                if !profile.studentNumber.isEmpty {
                    Section("Barcode preview") {
                        Code39BarcodeView(value: profile.studentNumber, barHeight: 64)
                            .padding(.vertical, 10)
                    }
                }

                if let validationMessage {
                    Section {
                        Label(validationMessage, systemImage: "exclamationmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(model.studentIDProfile == nil ? "Confirm Student ID" : "Edit Student ID")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.saveStudentID(profile)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(validationMessage != nil)
                }
            }
            .onAppear {
                if studentName.isEmpty {
                    focusedField = .name
                } else if studentNumber.isEmpty {
                    focusedField = .number
                }
            }
        }
        .preferredColorScheme(.light)
    }
}
