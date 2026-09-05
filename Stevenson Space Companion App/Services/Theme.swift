import SwiftUI
import ScheduleKit

/// Stevenson's two brand colours, plus the variants each one needs to stay
/// legible in both appearances.
///
/// Measured against the WCAG contrast targets the rest of the app holds to:
///
/// | pair                        | ratio  |
/// |-----------------------------|--------|
/// | `greenInk` on white         | 7.9:1  |
/// | white on `greenInk`         | 7.9:1  |
/// | `gold` on white             | 3.3:1  |
/// | `gold` on `greenInk`        | 2.4:1  |
/// | `ink` on `gold`             | 5.6:1  |
///
/// Green and white are the only pair that carries text; gold fails against
/// both white *and* green, so it is used strictly as a **fill under dark
/// ink** — never as a text or icon colour on a light or green background.
/// That constraint is what shapes the theme: green does the structural work,
/// gold gets exactly one job (marking "now"), white carries the surfaces.
enum StevensonBrand {
    /// #1B5E20 — the school green at its text-safe weight. Fixed, not
    /// adaptive: used where the surface underneath is known to be light.
    static let greenInk = Color(red: 0.106, green: 0.369, blue: 0.125)
    /// #B38825 — the school gold. Fixed for the same reason.
    static let goldInk = Color(red: 0.702, green: 0.533, blue: 0.145)
    /// Near-black, the only ink legible on `goldInk` (5.6:1).
    static let ink = Color(red: 0.086, green: 0.086, blue: 0.102)

    /// The green for anything drawn over a system background. #1B5E20 is far
    /// too dark on a dark background (~1.6:1), so dark mode lightens it to
    /// #35A83F (5.5:1) while keeping the hue.
    static let green = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.208, green: 0.659, blue: 0.247, alpha: 1)
            : UIColor(red: 0.106, green: 0.369, blue: 0.125, alpha: 1)
    })

    /// The gold for the same job. Brightened slightly in dark mode (#C9992B)
    /// so the "now" marker keeps its punch against a dark surface.
    static let gold = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.788, green: 0.600, blue: 0.169, alpha: 1)
            : UIColor(red: 0.702, green: 0.533, blue: 0.145, alpha: 1)
    })

    /// Washed-out gold for large background shapes. The alpha is per-appearance
    /// rather than a single value: over white a light wash reads as cream, but
    /// the same alpha over black muddies into brown and starts competing with
    /// the green it is supposed to sit behind, so dark mode takes less of it.
    static let goldWash = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.788, green: 0.600, blue: 0.169, alpha: 0.17)
            : UIColor(red: 0.702, green: 0.533, blue: 0.145, alpha: 0.28)
    })
}

/// The colours the app's chrome wears, resolved from the user's `ThemePref`.
///
/// Deliberately narrow: a theme may repaint *chrome* (the tint, the hero dial,
/// the "now" marker) but never the semantic colours that flag an abnormal
/// schedule. `ScheduleStyle.accent(for:)` — purple Late Arrival, red Early
/// Dismissal, orange passing period — stays loud in every theme, because those
/// colours are information, not branding.
struct Theme: Equatable {
    let pref: ThemePref

    static let stevenson = Theme(.stevenson)
    static let classic = Theme(.classic)

    init(_ pref: ThemePref) { self.pref = pref }

    /// App-wide tint: controls, links, the selected tab.
    var accent: Color {
        switch pref {
        case .stevenson: return StevensonBrand.green
        case .classic: return .accentColor
        }
    }

    /// The hero dial's progress arc, given the colour Classic would use.
    /// Under Stevenson every dial reads green — which block it is is already
    /// said by the label inside the ring.
    func dial(classic: Color) -> Color {
        switch pref {
        case .stevenson: return StevensonBrand.green
        case .classic: return classic
        }
    }

    /// The dial's unfilled remainder. Gold sits behind nothing here, so it is
    /// free to be gold — and it makes the ring read as both school colours.
    func dialTrack(classic: Color) -> Color {
        switch pref {
        case .stevenson: return StevensonBrand.goldWash
        case .classic: return classic.opacity(0.15)
        }
    }

    func dial(for role: BlockRole) -> Color { dial(classic: ScheduleStyle.tint(for: role)) }

    func dialTrack(for role: BlockRole) -> Color {
        dialTrack(classic: ScheduleStyle.tint(for: role))
    }

    /// The "happening now" marker: the card's wash and the NOW pill's fill.
    func now(for role: BlockRole) -> Color {
        switch pref {
        case .stevenson: return StevensonBrand.gold
        case .classic: return ScheduleStyle.tint(for: role)
        }
    }

    /// How strongly `now(for:)` washes the current card. Gold is a pale, warm
    /// fill at low alpha, so it needs a touch more than the saturated system
    /// colours to register as a highlight at all.
    var nowWashOpacity: Double {
        switch pref {
        case .stevenson: return 0.22
        case .classic: return 0.16
        }
    }

    /// Ink for the NOW pill. White fails on gold (2.4:1); near-black passes
    /// at 5.6:1 — so the pill's text colour has to follow the fill.
    var nowInk: Color {
        switch pref {
        case .stevenson: return StevensonBrand.ink
        case .classic: return .white
        }
    }

    /// The "In 12m" chip on the next block up, and the after-school checkmark.
    var upcoming: Color {
        switch pref {
        case .stevenson: return StevensonBrand.green
        case .classic: return .green
        }
    }
}

extension EnvironmentValues {
    @Entry var theme: Theme = .stevenson
}
