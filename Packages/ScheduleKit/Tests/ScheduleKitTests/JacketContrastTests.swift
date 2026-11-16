import SwiftUI
import Testing
@testable import ScheduleKit

/// Every ink the jacket puts on a ground must stay readable there: 4.5:1 for
/// text, 3:1 for the large varsity numerals and for glyphs. Main-actor bound:
/// AppKit resolves the dynamic colours there under `swift test`.
@MainActor @Suite struct JacketContrastTests {
    private let grounds: [JacketGround] = [.field, .gold, .lining]

    @Test(arguments: [ColorScheme.light, .dark])
    func groundInksReadAsText(_ scheme: ColorScheme) {
        let environment = environment(scheme)
        for ground in grounds {
            for (name, ink) in [("ink", ground.ink), ("ink2", ground.ink2), ("live", ground.live)] {
                let ratio = contrast(ink, ground.background, in: environment)
                #expect(ratio >= 4.5, "\(name) on \(ground) in \(scheme): \(ratio)")
            }
        }
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func heroNumeralsReadAsLargeText(_ scheme: ColorScheme) {
        let environment = environment(scheme)
        for ground in grounds {
            let ratio = contrast(ground.heroFace, ground.background, in: environment)
            #expect(ratio >= 3, "hero on \(ground) in \(scheme): \(ratio)")
        }
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func liningSurfacesAndControlsReadAsText(_ scheme: ColorScheme) {
        let environment = environment(scheme)
        let pairs: [(String, Color, Color)] = [
            ("ink on raised", Jacket.ink, Jacket.raised),
            ("ink2 on raised", Jacket.ink2, Jacket.raised),
            ("accent on raised", Jacket.accent, Jacket.raised),
            ("on-accent on accent", Jacket.onAccent, Jacket.accent),
            ("patch ink on twill", Jacket.patchInk, Jacket.twill),
            ("field green on chenille", Jacket.field.resolved(.light), Jacket.chenille),
            ("chenille on field green", Jacket.chenille, Jacket.field),
        ]
        for (name, foreground, background) in pairs {
            let ratio = contrast(foreground, background, in: environment)
            #expect(ratio >= 4.5, "\(name) in \(scheme): \(ratio)")
        }
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func placeholderGlyphsStayVisible(_ scheme: ColorScheme) {
        let environment = environment(scheme)
        #expect(contrast(Jacket.ink3, Jacket.lining, in: environment) >= 3)
    }

    /// Guards the suite itself: dark mode must resolve to the dark values, or
    /// every dark-mode check above would quietly test the light ones.
    @Test func darkModeResolvesItsOwnValues() {
        let light = Jacket.field.resolve(in: environment(.light))
        let dark = Jacket.field.resolve(in: environment(.dark))
        #expect(light != dark)
    }

    @Test func groundsFollowTheMoment() {
        let span = ResolvedSpan(id: "1", role: .classPeriod, displayName: "AP Physics C", room: "1616",
                                start: .distantPast, end: .distantFuture, periodID: .period(1),
                                half: nil, blockIDs: ["1"])
        #expect(JacketGround(state: .inBlock(current: span, next: nil)) == .field)
        #expect(JacketGround(state: .passing(from: span, to: span, kind: .betweenPeriods)) == .gold)
        #expect(JacketGround(state: .beforeSchool(first: span)) == .gold)
        #expect(JacketGround(state: .afterSchool) == .lining)
        #expect(JacketGround(state: .weekend) == .lining)
    }

    private func environment(_ scheme: ColorScheme) -> EnvironmentValues {
        var environment = EnvironmentValues()
        environment.colorScheme = scheme
        return environment
    }

    private func contrast(_ foreground: Color, _ background: Color,
                          in environment: EnvironmentValues) -> Double {
        func luminance(_ color: Color) -> Double {
            let resolved = color.resolve(in: environment)
            func linear(_ channel: Float) -> Double {
                let value = Double(channel)
                return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(resolved.red)
                + 0.7152 * linear(resolved.green)
                + 0.0722 * linear(resolved.blue)
        }
        let a = luminance(foreground), b = luminance(background)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

private extension Color {
    func resolved(_ scheme: ColorScheme) -> Color {
        var environment = EnvironmentValues()
        environment.colorScheme = scheme
        return Color(resolve(in: environment))
    }
}
