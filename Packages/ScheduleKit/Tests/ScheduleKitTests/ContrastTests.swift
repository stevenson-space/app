import SwiftUI
import Testing
@testable import ScheduleKit

@Suite struct ContrastTests {
    @Test func foregroundSwitchesOnEitherSideOfTheLuminanceCrossover() {
        let environment = EnvironmentValues()
        for (brightness, expected): (Double, Color) in [
            (0, .white), (0.178, .white), (0.180, .black), (1, .black)
        ] {
            let fill = Color(.sRGBLinear, white: brightness, opacity: 1)
            let foreground = ContrastingForeground(fill: fill).resolve(in: environment)
            #expect(foreground.resolve(in: environment) == expected.resolve(in: environment))
        }
    }

    @Test func foregroundMeetsTextContrastAcrossOpaqueRGBColors() {
        let environment = EnvironmentValues()
        for red in stride(from: 0.0, through: 1.0, by: 0.125) {
            for green in stride(from: 0.0, through: 1.0, by: 0.125) {
                for blue in stride(from: 0.0, through: 1.0, by: 0.125) {
                    let fill = Color(.sRGB, red: red, green: green, blue: blue)
                    let foreground = ContrastingForeground(fill: fill).resolve(in: environment)
                    #expect(contrast(foreground, fill, in: environment) >= 4.5)
                }
            }
        }
    }

    @Test func customBadgeFillsKeepWhiteLabelsInBothAppearances() {
        for scheme: ColorScheme in [.light, .dark] {
            var environment = EnvironmentValues()
            environment.colorScheme = scheme
            for setting: ColorSchemeContrast in [.standard, .increased] {
                let families: [BellFamily] = setting == .increased
                    ? [.lateArrival, .odyssey, .activityPeriod, .pmAssembly]
                    : [.lateArrival, .odyssey]
                for family in families {
                    let fill = ScheduleStyle.badgeFill(for: family, contrast: setting)
                    let foreground = ContrastingForeground(fill: fill).resolve(in: environment)
                    #expect(fill.resolve(in: environment).opacity == 1)
                    #expect(foreground.resolve(in: environment) == Color.white.resolve(in: environment))
                    #expect(contrast(.white, fill, in: environment) >= 4.5)
                }
                let lateArrival = ScheduleStyle.badgeFill(for: .lateArrival, contrast: setting)
                let requestedPurple = Color(.sRGB, red: 176 / 255, green: 47 / 255, blue: 194 / 255)
                #expect(lateArrival.resolve(in: environment) == requestedPurple.resolve(in: environment))
            }
        }
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
