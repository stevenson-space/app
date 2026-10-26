import Foundation
import FoundationModels

/// Which Siri this iPhone shows, so the tour can draw a matching glyph.
///
/// No API reports Siri's look directly. Apple Intelligence availability is the
/// public signal: Siri without it is the orb, Siri with it lights the screen
/// edge, and on iOS 27 it becomes Siri AI in the Dynamic Island.
enum SiriGeneration: String {
    /// The orb at the bottom of the screen.
    case classic
    /// iOS 18.1 to 26 with Apple Intelligence: the glowing screen edge.
    case appleIntelligence
    /// iOS 27 with Apple Intelligence: a glass bubble in the Dynamic Island.
    case siriAI

    static var current: SiriGeneration {
        #if DEBUG
        // `-SiriGeneration classic|appleIntelligence|siriAI` previews each look.
        if let name = UserDefaults.standard.string(forKey: "SiriGeneration"),
           let forced = SiriGeneration(rawValue: name) {
            return forced
        }
        #endif
        guard appleIntelligenceIsOn else { return .classic }
        if #available(iOS 27, *) { return .siriAI }
        return .appleIntelligence
    }

    private static var appleIntelligenceIsOn: Bool {
        if #available(iOS 26, *) {
            switch SystemLanguageModel.default.availability {
            // A model still downloading means Apple Intelligence is turned on.
            case .available, .unavailable(.modelNotReady):
                return true
            default:
                return false
            }
        }
        // iOS 18 can't ask. Apple Intelligence arrived in 18.1, is on by default
        // from 18.3, and needs an iPhone 15 Pro (iPhone16,1) or later.
        guard #available(iOS 18.1, *) else { return false }
        return iPhoneGeneration.map { $0 >= 16 } ?? false
    }

    /// The major number of an "iPhoneNN,M" model identifier.
    private static var iPhoneGeneration: Int? {
        var identifier = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"]
        if identifier == nil {
            var info = utsname()
            uname(&info)
            identifier = withUnsafeBytes(of: &info.machine) { buffer in
                String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
            }
        }
        guard let identifier, identifier.hasPrefix("iPhone"),
              let major = identifier.dropFirst("iPhone".count).split(separator: ",").first else {
            return nil
        }
        return Int(major)
    }
}
