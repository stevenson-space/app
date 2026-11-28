import SwiftUI
import ScheduleKit

extension EnvironmentValues {
    /// The app's real appearance. Home draws its chrome dark over the green
    /// field even in light mode; views that must not follow that override
    /// (the field itself, sheets) read this instead of `colorScheme`.
    @Entry var appColorScheme: ColorScheme = .light
}

extension Color {
    /// This colour as it resolves in the given appearance, fixed.
    func resolved(for scheme: ColorScheme) -> Color {
        var environment = EnvironmentValues()
        environment.colorScheme = scheme
        return Color(resolve(in: environment))
    }
}
