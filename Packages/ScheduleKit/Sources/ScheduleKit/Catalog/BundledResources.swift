import Foundation

/// Access to resources bundled inside the ScheduleKit library target.
/// Lives inside the library so `Bundle.module` resolves to the library's
/// resource bundle (test and app targets have different `Bundle.module`s).
enum BundledResources {
    static func bellSchedulesData() throws -> Data {
        guard let url = Bundle.module.url(forResource: "bell-schedules", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try Data(contentsOf: url)
    }
}
