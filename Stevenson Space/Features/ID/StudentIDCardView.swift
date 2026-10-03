import SwiftUI
import StudentIDKit

/// A recreation of the Stevenson student ID: gold crest band, green name band,
/// and a white lower body carrying the barcode.
///
/// Two deliberate departures from the rest of the app. The card keeps its
/// printed colours in dark mode, because a physical card does not invert and the
/// barcode has to stay black on white to scan. And it is the only element that
/// casts a shadow, because it is the only one pretending to be an object.
///
/// Everything is proportional to the card's width, so it holds its printed
/// proportions from an iPhone SE to an iPad.
struct StudentIDCardView: View {
    enum Content {
        case card(StudentIDCard, photo: UIImage?)
        /// The same chrome with nothing filled in — what the ID tab shows before
        /// a screenshot has been imported.
        case placeholder
    }

    let content: Content

    /// Credit-card proportions: 85.6mm × 53.98mm.
    static let aspectRatio: CGFloat = 1.586
    static let maximumWidth: CGFloat = 420

    var body: some View {
        GeometryReader { proxy in
            let metrics = Metrics(size: proxy.size)
            VStack(spacing: 0) {
                crestBand(metrics)
                nameBand(metrics)
                lowerBody(metrics)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: metrics.corner, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: metrics.corner, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.10), lineWidth: 0.5)
            }
        }
        .aspectRatio(StudentIDCardView.aspectRatio, contentMode: .fit)
        .frame(maxWidth: StudentIDCardView.maximumWidth)
        .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 4)
        // A fixed-aspect printed card cannot reflow; clamping keeps the largest
        // text sizes from shredding the layout while the rest of the screen
        // scales normally.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Bands

    private func crestBand(_ metrics: Metrics) -> some View {
        HStack(spacing: 0) {
            Image(.patriot)
                .resizable()
                .scaledToFit()
                .frame(height: metrics.crestHeight * 0.72)
                .frame(maxWidth: .infinity, alignment: .leading)

            photoWell(metrics)

            VStack(alignment: .trailing, spacing: metrics.height * 0.012) {
                if let year = schoolYearLabel {
                    Text(year)
                        .font(.system(size: metrics.metaFont, weight: .heavy))
                }
                if let grade = gradeLabel {
                    Text(grade)
                        .font(.system(size: metrics.metaFont, weight: .semibold))
                }
            }
            .foregroundStyle(StevensonPalette.cardInk)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, metrics.inset)
        .frame(height: metrics.crestHeight)
        .background {
            LinearGradient(colors: [StevensonPalette.gold, StevensonPalette.goldShade],
                           startPoint: .top, endPoint: .bottom)
        }
    }

    private func photoWell(_ metrics: Metrics) -> some View {
        let height = metrics.crestHeight * 0.84
        let width = height * 0.78
        return Group {
            if case .card(_, let photo) = content, let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    // Bias to the top: if anything has to go, it is the collar,
                    // never the top of the head.
                    .frame(width: width, height: height, alignment: .top)
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: height * 0.5))
                    .foregroundStyle(StevensonPalette.cardInk.opacity(0.25))
                    .frame(width: width, height: height)
                    .background(Color.white.opacity(0.55))
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: metrics.height * 0.018, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: metrics.height * 0.018, style: .continuous)
                .strokeBorder(Color.white.opacity(0.85), lineWidth: metrics.height * 0.008)
        }
    }

    private func nameBand(_ metrics: Metrics) -> some View {
        Text(displayName)
            .font(.system(size: metrics.nameFont, weight: .bold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.45)
            .padding(.horizontal, metrics.inset)
            .frame(maxWidth: .infinity)
            .frame(height: metrics.nameHeight)
            .background(StevensonPalette.green)
            .opacity(isPlaceholder ? 0.55 : 1)
    }

    private func lowerBody(_ metrics: Metrics) -> some View {
        VStack(spacing: 0) {
            Text("ADLAI E. STEVENSON HIGH SCHOOL")
                .font(.system(size: metrics.schoolFont, weight: .semibold))
                .tracking(metrics.schoolFont * 0.06)
                .foregroundStyle(StevensonPalette.cardInk.opacity(0.62))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.top, metrics.height * 0.035)

            Spacer(minLength: 0)

            Code39BarcodeView(payload: barcodePayload,
                              includeCheckDigit: includeCheckDigit,
                              availableWidth: metrics.barcodeWidth,
                              minimumBarHeight: metrics.barHeight,
                              maximumBarHeight: metrics.barHeight)
                .blur(radius: isPlaceholder ? 2.5 : 0)

            Spacer(minLength: 0)

            Text(numberLabel)
                .font(.system(size: metrics.numberFont, weight: .semibold, design: .monospaced))
                .tracking(metrics.numberFont * 0.18)
                .foregroundStyle(StevensonPalette.cardInk)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.bottom, metrics.height * 0.04)
        }
        .frame(maxWidth: .infinity)
        .background(Color.white)
    }

    // MARK: - Content

    private var card: StudentIDCard? {
        if case .card(let card, _) = content { return card }
        return nil
    }

    private var isPlaceholder: Bool { card == nil }

    private var displayName: String {
        card?.fullName ?? (isPlaceholder ? "Your Name" : "Name not found")
    }

    private var numberLabel: String { card?.idNumber ?? "00000" }
    private var barcodePayload: String { card?.barcodePayload ?? "00000" }
    private var includeCheckDigit: Bool { card?.requiresCheckDigit ?? false }
    private var schoolYearLabel: String? { card?.schoolYearLabel ?? (isPlaceholder ? "26\u{2013}27" : nil) }
    private var gradeLabel: String? { card?.gradeLabel ?? (isPlaceholder ? "Grade 12" : nil) }

    private var accessibilityLabel: String {
        guard let card else { return "Student ID card, not set up yet" }
        var parts = ["Student ID"]
        if let name = card.fullName { parts.append(name) }
        parts.append("number " + card.spokenNumber)
        if let grade = card.gradeLabel { parts.append(grade) }
        if let year = card.schoolYearLabel { parts.append("school year " + year) }
        return parts.joined(separator: ", ")
    }

    // MARK: - Proportions

    private struct Metrics {
        let width: CGFloat
        let height: CGFloat

        init(size: CGSize) {
            width = size.width
            height = size.height
        }

        var inset: CGFloat { width * 0.05 }
        var corner: CGFloat { width * 0.043 }
        var crestHeight: CGFloat { height * 0.37 }
        var nameHeight: CGFloat { height * 0.147 }
        var barcodeWidth: CGFloat { width - inset * 2 }
        /// The lower body has to hold the school line, the symbol, and the
        /// number; this is the share the symbol can take without crowding them.
        var barHeight: CGFloat { height * 0.20 }
        var nameFont: CGFloat { nameHeight * 0.63 }
        var metaFont: CGFloat { height * 0.062 }
        var schoolFont: CGFloat { height * 0.050 }
        var numberFont: CGFloat { height * 0.080 }
    }
}

#Preview("Card") {
    StudentIDCardView(content: .placeholder)
        .padding()
        .background(Color(.systemGroupedBackground))
}
