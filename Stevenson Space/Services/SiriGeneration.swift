import Foundation
import FoundationModels

/// Which Siri this iPhone shows, so the tour can draw a matching glyph.
///
/// No API reports Siri's look directly. Apple Intelligence availability is the
/// public signal: Siri without it is the orb, and Siri with it lights the
/// screen edge. Siri AI, in the Dynamic Island, is a separate opt-in beta on
/// iOS 27 that no API reveals, so the tour asks when it's possible.
enum SiriGeneration: String {
    /// The orb at the bottom of the screen.
    case classic
    /// Apple Intelligence without Siri AI: the glowing screen edge.
    case appleIntelligence
    /// iOS 27's opt-in Siri AI: a glass bubble in the Dynamic Island.
    case siriAI

    static var current: SiriGeneration {
        #if DEBUG
        // `-SiriGeneration classic|appleIntelligence|siriAI` previews each look.
        if let name = UserDefaults.standard.string(forKey: "SiriGeneration"),
           let forced = SiriGeneration(rawValue: name) {
            return forced
        }
        #endif
        return appleIntelligenceIsOn ? .appleIntelligence : .classic
    }

    /// Whether this iPhone could be using Siri AI. It needs iOS 27 and Apple
    /// Intelligence, then a waitlisted opt-in in Settings › Siri.
    static var mightBeSiriAI: Bool {
        guard #available(iOS 27, *) else { return false }
        return appleIntelligenceIsOn
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
