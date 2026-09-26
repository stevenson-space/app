import SwiftUI
import Observation
import ScheduleKit

enum RootTab: Hashable {
    case home
    case lunch
    case id
    case settings
}

enum StudentIDPresentationError: LocalizedError {
    case presentationInProgress

    var errorDescription: String? {
        "Close the open sheet or picker in Stevenson Space, then ask to show your student ID again."
    }
}

enum StudentIDPresentationResult {
    case presented, opening, needsImport
}

/// Each RootView owns this state; the shared app model only routes requests.
@Observable
@MainActor
final class SceneNavigation {
    let model: AppModel
    @ObservationIgnored weak var window: UIWindow?
    var selectedTab: RootTab = .home
    var isStudentIDScanning = false
    var isStudentIDScannerPresented = false
    var isStudentIDScannerDismissing = false
    private var reopenStudentIDAfterDismissal = false
    private(set) var studentIDScannerPresentationID = UUID()
    private(set) var homeTodayRequest = 0
    private(set) var lunchTodayRequest = 0

    init(model: AppModel) {
        self.model = model
    }

    func openStudentIDScanner() throws -> StudentIDPresentationResult {
        if isStudentIDScannerDismissing || (!isStudentIDScanning && isStudentIDScannerPresented) {
            reopenStudentIDAfterDismissal = true
            return .opening
        }
        if isStudentIDScanning && isStudentIDScannerPresented { return .presented }
        let presentations = (window?.windowScene?.windows ?? [])
            .compactMap { $0.rootViewController?.presentedViewController }
        // viewDidAppear hasn't acknowledged an animating cover yet. Preserve
        // its host and binding until UIKit finishes the presentation.
        if isStudentIDScanning && presentations.contains(where: \.isBeingPresented) {
            return .opening
        }
        if isStudentIDScanning {
            isStudentIDScanning = false
            // Recreate only the cover's host so a stale true binding cannot
            // swallow the next request in the same SwiftUI update.
            studentIDScannerPresentationID = UUID()
        }
        // A failed cover presentation can leave its binding true. Check before
        // changing either navigation or the binding, and preserve unfinished edits.
        guard presentations.isEmpty else {
            throw StudentIDPresentationError.presentationInProgress
        }
        model.reloadStudentIDIfUnread()
        selectedTab = .id
        isStudentIDScanning = model.studentID != nil
        return isStudentIDScanning ? .opening : .needsImport
    }

    func studentIDScannerDidDismiss() {
        isStudentIDScannerPresented = false
        isStudentIDScannerDismissing = false
        guard reopenStudentIDAfterDismissal else { return }
        reopenStudentIDAfterDismissal = false
        // Wait for the old cover to finish dismissing before requesting another.
        selectedTab = .id
        isStudentIDScanning = model.studentID != nil
    }

    func openTab(_ tab: RootTab) {
        reopenStudentIDAfterDismissal = false
        isStudentIDScanning = false
        switch tab {
        case .home: openWidgetURL(WidgetTimelinePlanner.homeURL)
        case .lunch: openWidgetURL(LunchWidgetTimelinePlanner.lunchURL)
        case .id, .settings: selectedTab = tab
        }
    }

    func openWidgetURL(_ url: URL) {
        if url == LunchWidgetTimelinePlanner.lunchURL {
            reopenStudentIDAfterDismissal = false
            isStudentIDScanning = false
            model.prepareForNavigation()
            selectedTab = .lunch
            lunchTodayRequest += 1
            return
        }
        guard WidgetTimelinePlanner.isHomeURL(url) else { return }
        reopenStudentIDAfterDismissal = false
        isStudentIDScanning = false
        model.prepareForNavigation()
        selectedTab = .home
        homeTodayRequest += 1
    }
}

/// Foreground intents select one attached window. A cold-launch request waits
/// for the first foreground root to attach, and is consumed exactly once.
@MainActor
final class AppNavigation {
    private struct SceneReference {
        weak var scene: SceneNavigation?
    }
    private enum Request {
        case scanner
        case tab(RootTab)
    }
    private var scenes: [SceneReference] = []
    private var pending: Request?

    private var target: SceneNavigation? {
        let foreground = scenes.reversed().compactMap(\.scene).filter {
            guard let phase = $0.window?.windowScene?.activationState else { return false }
            return phase == .foregroundActive || phase == .foregroundInactive
        }
        let active = foreground.filter { $0.window?.windowScene?.activationState == .foregroundActive }
        return active.first { $0.window?.isKeyWindow == true } ?? active.first
            ?? foreground.first { $0.window?.isKeyWindow == true } ?? foreground.first
    }

    func attach(_ scene: SceneNavigation) throws {
        scenes.removeAll { $0.scene == nil || $0.scene === scene }
        scenes.append(SceneReference(scene: scene))
        guard let target, let request = pending else { return }
        pending = nil
        switch request {
        case .scanner: _ = try target.openStudentIDScanner()
        case .tab(let tab): target.openTab(tab)
        }
    }

    func openStudentIDScanner() throws -> StudentIDPresentationResult {
        guard let target else {
            pending = .scanner
            return .opening
        }
        pending = nil
        return try target.openStudentIDScanner()
    }

    func openTab(_ tab: RootTab) {
        guard let target else {
            pending = .tab(tab)
            return
        }
        pending = nil
        target.openTab(tab)
    }
}

/// Capture the owning window instead of inspecting unrelated scenes' sheets.
struct SceneWindowReader: UIViewRepresentable {
    let windowChanged: (UIWindow?) -> Void

    func makeUIView(context: Context) -> WindowView {
        let view = WindowView()
        view.windowChanged = windowChanged
        return view
    }

    func updateUIView(_ view: WindowView, context: Context) {
        view.windowChanged = windowChanged
    }

    final class WindowView: UIView {
        var windowChanged: ((UIWindow?) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            windowChanged?(window)
        }
    }
}
