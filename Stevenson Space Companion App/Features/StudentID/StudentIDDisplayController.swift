import UIKit

/// Makes a saved ID immediately scanner-ready, then returns every global
/// display setting to the value the student had before opening the tab.
@MainActor
final class StudentIDDisplayController {
    private weak var activeScreen: UIScreen?
    private var previousBrightness: CGFloat?
    private var previousIdleTimerState: Bool?

    func activate() {
        guard previousBrightness == nil, let screen = foregroundScreen else { return }
        activeScreen = screen
        previousBrightness = screen.brightness
        previousIdleTimerState = UIApplication.shared.isIdleTimerDisabled
        screen.brightness = 1
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func deactivate() {
        if let previousBrightness, let screen = activeScreen {
            screen.brightness = previousBrightness
        }
        if let previousIdleTimerState {
            UIApplication.shared.isIdleTimerDisabled = previousIdleTimerState
        }
        activeScreen = nil
        previousBrightness = nil
        previousIdleTimerState = nil
    }

    private var foregroundScreen: UIScreen? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first(where: { $0.activationState == .foregroundActive })?.screen
            ?? scenes.first?.screen
    }
}
