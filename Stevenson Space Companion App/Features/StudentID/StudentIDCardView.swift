import SwiftUI
import StudentIDKit

enum StudentIDStyle {
    static let forestGreen = Color(red: 0.10, green: 0.22, blue: 0.14)
    static let brightGreen = Color(red: 0.31, green: 0.55, blue: 0.24)
}

struct StudentIDCardView: View {
    let profile: StudentIDProfile

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "building.columns.fill")
                    .font(.title2)
                    .frame(width: 42, height: 42)
                    .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 11))

                VStack(alignment: .leading, spacing: 1) {
                    Text("STEVENSON SPACE")
                        .font(.headline.weight(.heavy))
                        .tracking(0.7)
                    Text("Adlai E. Stevenson High School")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.82))
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .padding(18)
            .background(StudentIDStyle.forestGreen)

            VStack(alignment: .leading, spacing: 6) {
                Text("STUDENT ID")
                    .font(.caption.weight(.bold))
                    .tracking(1.3)
                    .foregroundStyle(StudentIDStyle.brightGreen)
                Text(profile.studentName)
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .foregroundStyle(StudentIDStyle.forestGreen)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                    .accessibilityAddTraits(.isHeader)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 20)

            Divider()

            VStack(spacing: 14) {
                Code39BarcodeView(value: profile.studentNumber)

                VStack(spacing: 3) {
                    Text(profile.studentNumber)
                        .font(.title3.monospaced().weight(.semibold))
                        .foregroundStyle(.black)
                    Text("STUDENT NUMBER")
                        .font(.caption2.weight(.semibold))
                        .tracking(1)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 22)
            .padding(.bottom, 20)
            .background(.white)
        }
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.black.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: StudentIDStyle.forestGreen.opacity(0.12), radius: 20, y: 8)
        .privacySensitive()
    }
}

#Preview("Saved ID") {
    StudentIDCardView(profile: StudentIDProfile(
        studentName: "Sample Student",
        studentNumber: "12345"
    ))
    .padding()
    .background(.white)
    .preferredColorScheme(.light)
}
