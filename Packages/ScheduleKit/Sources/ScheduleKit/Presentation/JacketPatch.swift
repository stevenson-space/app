import SwiftUI

/// A sewn-on patch: how a special day announces itself.
public struct JacketPatch: View {
    private let title: String
    private let systemImage: String

    public init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    public var body: some View {
        Label(title, systemImage: systemImage)
            .jacketLabel()
            .tracking(0.6)
            .foregroundStyle(Jacket.patchInk)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(minHeight: 32)
            .background {
                Capsule().fill(Jacket.twill)
                Capsule()
                    .inset(by: 3)
                    .stroke(Jacket.patchInk.opacity(0.42),
                            style: StrokeStyle(lineWidth: 1.2, dash: [3.5, 3]))
            }
    }
}
