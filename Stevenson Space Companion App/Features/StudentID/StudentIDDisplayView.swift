import CoreGraphics
import SwiftUI
import UIKit
import ScheduleKit

/// The saved ID display is intentionally a separate screen from setup. It is
/// light-only, high contrast, and sized around the needs of a real barcode
/// scanner rather than a decorative card.
struct StudentIDDisplayView: View {
    let profile: StudentIDProfile

    @Environment(\.scenePhase) private var scenePhase
    @State private var screenSession = StudentIDScreenSession()

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                StudentIDCard(profile: profile)

                Label("Show this screen to a scanner", systemImage: "barcode.viewfinder")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(StudentIDPalette.secondaryText)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .background(StudentIDPalette.canvas.ignoresSafeArea())
        .environment(\.colorScheme, .light)
        .preferredColorScheme(.light)
        .onAppear {
            screenSession.activate()
        }
        .onDisappear {
            screenSession.deactivate()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                screenSession.activate()
            case .background, .inactive:
                screenSession.deactivate()
            @unknown default:
                screenSession.deactivate()
            }
        }
        .accessibilityIdentifier("student-id-display")
    }
}

private struct StudentIDCard: View {
    let profile: StudentIDProfile

    var body: some View {
        VStack(spacing: 0) {
            cardHeader
            cardDetails
            Divider()
                .overlay(StudentIDPalette.line)
                .padding(.horizontal, 18)
            barcodeSection
        }
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(StudentIDPalette.deepGreen.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.11), radius: 18, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("student-id-card")
    }

    private var cardHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("STEVENSON")
                    .font(.caption.weight(.black))
                    .tracking(1.7)
                Text("STUDENT ID")
                    .font(.title2.weight(.bold))
            }
            .foregroundStyle(.white)

            Spacer(minLength: 8)

            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 29, weight: .semibold))
                .foregroundStyle(StudentIDPalette.gold)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 19)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StudentIDPalette.deepGreen)
    }

    private var cardDetails: some View {
        HStack(alignment: .top, spacing: 16) {
            StudentIDPortraitView(data: profile.portraitJPEGData, size: 100)

            VStack(alignment: .leading, spacing: 8) {
                Text("Name")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(StudentIDPalette.secondaryText)
                Text(profile.displayName ?? "Student")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(StudentIDPalette.primaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Verified student number")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(StudentIDPalette.secondaryText)
                    .padding(.top, 4)
                Text(profile.studentNumber)
                    .font(.system(.title3, design: .monospaced).weight(.bold))
                    .foregroundStyle(StudentIDPalette.primaryText)
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Student ID for \(profile.displayName ?? "student")")
        .accessibilityValue("Verified student number \(profile.studentNumber)")
    }

    private var barcodeSection: some View {
        VStack(spacing: 8) {
            GeometryReader { proxy in
                let barcodeWidth = min(max(proxy.size.width - 12, 280), 360)

                StudentIDBarcodeView(value: profile.studentNumber)
                    .frame(width: barcodeWidth, height: 112)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(height: 122)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Code 39 barcode")
            .accessibilityValue("Student number \(profile.studentNumber)")
            .accessibilityIdentifier("student-id-barcode")

            Text("Code 39")
                .font(.caption.weight(.medium))
                .foregroundStyle(StudentIDPalette.secondaryText)
        }
        .padding(.horizontal, 12)
        .padding(.top, 16)
        .padding(.bottom, 20)
    }
}

/// A portrait is stored only when the scanner could safely crop and encode
/// one. The neutral fallback keeps the card useful for screenshots without
/// implying that a portrait is required.
struct StudentIDPortraitView: View {
    let data: Data?
    let size: CGFloat

    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    StudentIDPalette.deepGreen.opacity(0.08)
                    Image(systemName: "person.crop.square.fill")
                        .font(.system(size: size * 0.38, weight: .medium))
                        .foregroundStyle(StudentIDPalette.deepGreen.opacity(0.68))
                }
            }
        }
        .frame(width: size, height: size)
        .background(StudentIDPalette.deepGreen.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(StudentIDPalette.deepGreen.opacity(0.22), lineWidth: 1)
        }
        .accessibilityLabel(data == nil ? "No portrait saved" : "Saved portrait")
        .accessibilityIdentifier("student-id-portrait")
    }
}

/// Generates a fresh Code 39 image from the verified number on every device.
/// Both supported source layouts use Code 39, so preserving that symbology
/// avoids assuming the school's scanners are configured for another format.
struct StudentIDBarcodeView: View {
    let value: String

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { proxy in
            let requestedWidth = proxy.size.width > 0 ? proxy.size.width : 320
            let targetWidth = min(max(requestedWidth, 280), 360)
            let image = StudentIDBarcodeGenerator.image(
                for: value,
                targetWidthPoints: targetWidth,
                displayScale: displayScale)

            Group {
                if let image {
                    // Do not make this image resizable. The generator chooses
                    // an integer module scale and this intrinsic size keeps
                    // SwiftUI from applying a fractional resampling pass.
                    Image(uiImage: image)
                        .interpolation(.none)
                        .frame(width: image.size.width, height: image.size.height)
                } else {
                    Image(systemName: "barcode")
                        .font(.largeTitle)
                        .foregroundStyle(StudentIDPalette.primaryText)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.white)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Code 39 barcode")
        .accessibilityValue(value)
    }
}

@MainActor
private enum StudentIDBarcodeGenerator {
    private static let cache = NSCache<NSString, UIImage>()

    /// Nine alternating bar/space elements per character. `n` occupies one
    /// module and `w` occupies two, a valid Code 39 wide-to-narrow ratio.
    private static let patterns: [Character: String] = [
        "0": "nnnwwnwnn",
        "1": "wnnwnnnnw",
        "2": "nnwwnnnnw",
        "3": "wnwwnnnnn",
        "4": "nnnwwnnnw",
        "5": "wnnwwnnnn",
        "6": "nnwwwnnnn",
        "7": "nnnwnnwnw",
        "8": "wnnwnnwnn",
        "9": "nnwwnnwnn",
        "*": "nwnnwnwnn",
    ]

    static func image(for value: String,
                      targetWidthPoints: CGFloat,
                      displayScale: CGFloat) -> UIImage? {
        let cleanValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanValue.isEmpty,
              cleanValue.allSatisfy(\.isNumber) else { return nil }

        let safeDisplayScale = max(displayScale, 1)
        let pixelTarget = max(Int((targetWidthPoints * safeDisplayScale).rounded()), 1)
        let scaleKey = Int((safeDisplayScale * 100).rounded())
        let key = "code39-\(cleanValue)-\(pixelTarget)-\(scaleKey)" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let encodedCharacters = Array("*\(cleanValue)*")
        let wideRatio = 2
        let modulesPerCharacter = 6 + 3 * wideRatio
        let interCharacterGaps = max(0, encodedCharacters.count - 1)
        let quietZoneModules = 10
        let totalModules = quietZoneModules * 2 +
            encodedCharacters.count * modulesPerCharacter + interCharacterGaps
        let minimumWidthPixels = Int(ceil(280 * safeDisplayScale))
        let maximumWidthPixels = Int(floor(360 * safeDisplayScale))
        let targetModuleWidth = max(1, pixelTarget / totalModules)
        let minimumModuleWidth = max(1, Int(ceil(
            CGFloat(minimumWidthPixels) / CGFloat(totalModules))))
        let maximumModuleWidth = max(1, maximumWidthPixels / totalModules)
        let moduleWidth = min(maximumModuleWidth,
                              max(minimumModuleWidth, targetModuleWidth))
        let pixelWidth = totalModules * moduleWidth
        let pixelHeight = Int(ceil(96 * safeDisplayScale))

        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: pixelWidth,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
            return nil
        }

        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        context.setFillColor(gray: 0, alpha: 1)

        var x = quietZoneModules * moduleWidth
        for (characterIndex, character) in encodedCharacters.enumerated() {
            guard let pattern = patterns[character] else { return nil }
            for (elementIndex, widthCode) in pattern.enumerated() {
                let elementModules = widthCode == "w" ? wideRatio : 1
                let elementWidth = elementModules * moduleWidth
                if elementIndex.isMultiple(of: 2) {
                    context.fill(CGRect(x: x,
                                        y: 0,
                                        width: elementWidth,
                                        height: pixelHeight))
                }
                x += elementWidth
            }
            if characterIndex < encodedCharacters.count - 1 {
                x += moduleWidth
            }
        }

        guard let cgImage = context.makeImage() else { return nil }
        let image = UIImage(cgImage: cgImage, scale: safeDisplayScale, orientation: .up)
        cache.setObject(image, forKey: key)
        return image
    }
}

@MainActor
private final class StudentIDScreenSession {
    private var previousBrightness: CGFloat?
    private var previousIdleTimerDisabled: Bool?
    private var isActive = false

    func activate() {
        guard !isActive else { return }

        previousBrightness = UIScreen.main.brightness
        previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
        UIScreen.main.brightness = 1.0
        UIApplication.shared.isIdleTimerDisabled = true
        isActive = true
    }

    func deactivate() {
        guard isActive else { return }

        if let previousBrightness {
            UIScreen.main.brightness = previousBrightness
        }
        if let previousIdleTimerDisabled {
            UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled
        }

        self.previousBrightness = nil
        self.previousIdleTimerDisabled = nil
        isActive = false
    }
}

#Preview("Barcode") {
    StudentIDBarcodeView(value: "012345")
        .frame(width: 320, height: 112)
        .padding()
        .background(.white)
}

#Preview("Student ID Card") {
    ScrollView {
        StudentIDCard(profile: StudentIDProfile(
            studentNumber: "012345",
            displayName: "Sample Student"))
        .padding(16)
    }
    .background(StudentIDPalette.canvas)
    .preferredColorScheme(.light)
}

/// A deliberately small palette keeps the ID legible under a scanner while
/// still carrying a restrained Stevenson-like green and gold identity.
enum StudentIDPalette {
    static let canvas = Color.white
    static let deepGreen = Color(red: 0.055, green: 0.275, blue: 0.145)
    static let gold = Color(red: 0.88, green: 0.64, blue: 0.16)
    static let primaryText = Color(red: 0.055, green: 0.075, blue: 0.065)
    static let secondaryText = Color(red: 0.27, green: 0.31, blue: 0.285)
    static let line = Color(red: 0.84, green: 0.87, blue: 0.84)
}
