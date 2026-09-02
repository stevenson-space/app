import SwiftUI
import StudentIDKit

/// Full-screen presentation for the moment the barcode is actually read.
///
/// White ground, brightness at maximum, and the screen kept awake — the three
/// things that decide whether a handheld scanner picks a barcode up off a phone.
struct StudentIDScanView: View {
    let card: StudentIDCard

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                Spacer(minLength: 0)

                if let name = card.fullName {
                    Text(name)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(StevensonPalette.cardInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.bottom, 28)
                }

                Code39BarcodeView(payload: card.barcodePayload,
                                  includeCheckDigit: card.requiresCheckDigit,
                                  availableWidth: min(proxy.size.width - 40, 460),
                                  maximumModuleWidth: 4,
                                  minimumBarHeight: 132,
                                  maximumBarHeight: 132)

                Text(card.idNumber)
                    .font(.system(size: 30, weight: .semibold, design: .monospaced))
                    .tracking(6)
                    .foregroundStyle(StevensonPalette.cardInk)
                    .padding(.top, 22)

                Spacer(minLength: 0)

                Text("Hold the screen flat under the scanner.")
                    .font(.footnote)
                    .foregroundStyle(StevensonPalette.cardInk.opacity(0.5))
                    .padding(.bottom, 10)

                Button("Done") { dismiss() }
                    .font(.body.weight(.semibold))
                    .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity)
        }
        .background(Color.white.ignoresSafeArea())
        .contentShape(Rectangle())
        .onTapGesture { dismiss() }
        .modifier(ScreenAwakeAtFullBrightness())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Student ID barcode, number "
                            + card.idNumber.map(String.init).joined(separator: " "))
    }
}

/// Drives the display to full brightness and blocks auto-lock while a barcode is
/// on screen, then puts both back exactly as they were — including when the app
/// is backgrounded mid-scan rather than dismissed.
private struct ScreenAwakeAtFullBrightness: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @State private var previousBrightness: CGFloat?

    func body(content: Content) -> some View {
        content
            .onAppear(perform: engage)
            .onDisappear(perform: restore)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { engage() } else { restore() }
            }
    }

    private var screen: UIScreen? {
        let scenes = UIApplication.shared.connectedScenes
        let active = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return (active as? UIWindowScene)?.screen
    }

    private func engage() {
        guard let screen else { return }
        if previousBrightness == nil { previousBrightness = screen.brightness }
        screen.brightness = 1
        UIApplication.shared.isIdleTimerDisabled = true
    }

    private func restore() {
        if let previousBrightness, let screen {
            screen.brightness = previousBrightness
        }
        previousBrightness = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }
}
