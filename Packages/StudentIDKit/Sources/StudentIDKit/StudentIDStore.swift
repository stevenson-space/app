import Foundation

public final class StudentIDStore: @unchecked Sendable {
    private static let profileKey = "student-id.profile.v1"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var profile: StudentIDProfile? {
        get {
            guard let data = defaults.data(forKey: Self.profileKey) else { return nil }
            return try? JSONDecoder().decode(StudentIDProfile.self, from: data)
        }
        set {
            guard let newValue else {
                defaults.removeObject(forKey: Self.profileKey)
                return
            }
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: Self.profileKey)
        }
    }
}
