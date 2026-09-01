import Foundation
import Observation

/// The single handoff point between system app intents and the app's scene.
///
/// An intent can be performed while the app is cold, before the SwiftUI scene
/// has finished constructing its model. Keeping the latest request here lets
/// the scene consume it when it becomes ready, while the observable property
/// also handles requests delivered to an already-running scene.
@Observable
@MainActor
final class AppIntentRouter {
    enum Destination: Equatable, Sendable {
        case studentID
    }

    struct Request: Identifiable, Equatable, Sendable {
        let id: UUID
        let destination: Destination

        init(destination: Destination) {
            self.id = UUID()
            self.destination = destination
        }
    }

    static let shared = AppIntentRouter()

    private(set) var pendingRequest: Request?

    private init() {}

    func enqueue(_ destination: Destination) {
        pendingRequest = Request(destination: destination)
    }

    /// Returns and clears the current request. A scene consumes a request only
    /// after it has applied the destination to its own navigation state.
    func consumePendingRequest() -> Request? {
        defer { pendingRequest = nil }
        return pendingRequest
    }
}
