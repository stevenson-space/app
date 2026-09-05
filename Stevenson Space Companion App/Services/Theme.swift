import SwiftUI
import ScheduleKit

/// Stevenson's two brand colours, plus the variants each one needs to stay
/// legible on the surface it lands on.
///
/// One measurement drives most of the design. Against WCAG:
///
/// | pair                          | ratio  |
/// |-------------------------------|--------|
/// | `greenInk` on white           | 7.9:1  |
/// | `goldInk` on white            | 3.3:1  |
/// | `gold` (dark) on dark surface | 6.5:1  |
/// | `greenInk` on dark surface    | 1.6:1  |
/// | white on `greenInk`           | 7.9:1  |
/// | `goldInk` on `greenInk`       | 2.4:1  |
/// | `lightGold` on `greenInk`     | 4.7:1  |
///
/// Green reads on white and dies on black; gold does the reverse. So the app
/// does not pick one accent — it swaps: **green accents in light, gold accents
/// in dark**, which is how stevenson.space handles the same two colours. The
/// third row of the table is the other lever: brand gold is invisible against
/// the green band, but lightening it to `lightGold` clears 4.7:1, which is what
/// lets gold appear *on* green at all.
enum StevensonBrand {
    /// #1B5E20 — the school green at its text-safe weight, for light surfaces.
    static let greenInk = Color(red: 0.106, green: 0.369, blue: 0.125)
    /// #B38825 — the school gold, for light surfaces (fills only; 3.3:1).
    static let goldInk = Color(red: 0.702, green: 0.533, blue: 0.145)
    /// Near-black, the only ink legible on gold (5.6:1).
    static let ink = Color(red: 0.086, green: 0.086, blue: 0.102)
    /// #E8C560 — gold lightened until it clears 4.7:1 on the green band. The
    /// only gold that may be drawn *on* green.
    static let lightGold = Color(red: 0.910, green: 0.773, blue: 0.376)

    /// Green over a system background: #1B5E20 light, #35A83F dark (5.5:1).
    static let green = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.208, green: 0.659, blue: 0.247, alpha: 1)
            : UIColor(red: 0.106, green: 0.369, blue: 0.125, alpha: 1)
    })

    /// Gold over a system background: #B38825 light, #C9992B dark (6.5:1).
    static let gold = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.788, green: 0.600, blue: 0.169, alpha: 1)
            : UIColor(red: 0.702, green: 0.533, blue: 0.145, alpha: 1)
    })

    /// The accent proper — the swap described above. Green in light, gold in
    /// dark, so whichever colour is carrying the UI is the one that can.
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.788, green: 0.600, blue: 0.169, alpha: 1)
            : UIColor(red: 0.106, green: 0.369, blue: 0.125, alpha: 1)
    })

    /// The hero band: full school green in light, a deep forest in dark. Dark
    /// mode keeps a green band rather than a neutral one — it is still clearly
    /// a dark surface (1.5:1 against black) but the screen never goes grey.
    static let band = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.078, green: 0.200, blue: 0.106, alpha: 1)
            : UIColor(red: 0.106, green: 0.369, blue: 0.125, alpha: 1)
    })

    /// #2E7D32 — the green directly under the status bar in light mode. iOS
    /// draws the clock in black there and gives no app outside a navigation bar
    /// any say in it, so the band's own green would carry it at 2.3:1. This is
    /// one step up the same green ramp, where the clock — bold, and large by
    /// WCAG's reckoning — reads at 4.1:1 against a 3:1 bar. Dark mode's clock is
    /// white and the band already carries it at 15:1, so there this *is* the
    /// band and the join below it is invisible.
    static let statusField = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.078, green: 0.200, blue: 0.106, alpha: 1)
            : UIColor(red: 0.180, green: 0.490, blue: 0.196, alpha: 1)
    })

    /// The disc the countdown sits on, punched out of the band. It matches the
    /// system appearance so `.primary`/`.secondary` text stays correct on it.
    static let disc = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.055, green: 0.129, blue: 0.071, alpha: 1)
            : UIColor(white: 1, alpha: 1)
    })

    /// The dial's track — always the school colour the arc is *not* wearing, so
    /// the ring reads as green and gold together in both appearances. Gold over
    /// the white disc, green over the dark one.
    static let dialTrack = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.208, green: 0.659, blue: 0.247, alpha: 0.30)
            : UIColor(red: 0.702, green: 0.533, blue: 0.145, alpha: 0.32)
    })
}

/// The colours the app's chrome wears, resolved from the user's `ThemePref`.
///
/// Deliberately narrow: a theme may repaint *chrome* — the tint, the hero band,
/// the dial, the "now" marker — but never the semantic colours that flag an
/// abnormal schedule. Purple Late Arrival, red Early Dismissal and orange
/// passing periods are information, not branding, and stay loud in every theme.
/// Where the band would swallow one of those (a red capsule clears only 2.2:1
/// against green) the fix is to reinforce its *shape* with a white border, not
/// to repaint it.
struct Theme: Equatable {
    let pref: ThemePref

    static let stevenson = Theme(.stevenson)
    static let classic = Theme(.classic)

    init(_ pref: ThemePref) { self.pref = pref }

    private var isStevenson: Bool { pref == .stevenson }

    // MARK: - Chrome

    /// App-wide tint: controls, links, the selected tab.
    var accent: Color { isStevenson ? StevensonBrand.accent : .accentColor }

    // MARK: - The hero band

    /// The colour block behind the day header and the countdown. `clear` under
    /// Classic, which leaves that surface exactly as it shipped.
    var heroBackground: Color { isStevenson ? StevensonBrand.band : .clear }

    /// Whether the band is a painted surface — the switch every on-band colour
    /// below keys off.
    var hasHeroBand: Bool { isStevenson }

    /// The disc behind the countdown, or nil to draw the dial bare.
    var heroDisc: Color? { isStevenson ? StevensonBrand.disc : nil }
    /// The colour behind the system clock, and the top stop of the band's join.
    var statusField: Color { isStevenson ? StevensonBrand.statusField : .clear }

    /// Primary text on the band.
    var onHero: Color { isStevenson ? .white : .primary }

    /// Supporting text on the band. 78% white still clears 6.1:1 on green.
    var onHeroSecondary: Color { isStevenson ? .white.opacity(0.78) : .secondary }

    /// A glyph or accent mark on the band, given the colour Classic would use.
    /// Everything on green collapses to `lightGold`: it is the one gold that
    /// clears 4.7:1 there, and most system tints (indigo, teal, green) would be
    /// invisible against it.
    func heroGlyph(classic: Color) -> Color {
        isStevenson ? StevensonBrand.lightGold : classic
    }

    /// An opaque surface for panels that sit on the band and carry their own
    /// tinted fill — without it, a 12%-orange wash would blend into the green.
    var heroCard: Color { isStevenson ? Color(.secondarySystemGroupedBackground) : .clear }

    /// A header badge's text colour on the band. Light gold rather than white,
    /// so a badge still reads as a flag rather than another line of copy.
    func badgeInk(classic: Color) -> Color {
        isStevenson ? StevensonBrand.lightGold : classic
    }

    /// The matching badge capsule fill.
    func badgeFill(classic: Color) -> Color {
        isStevenson ? StevensonBrand.lightGold.opacity(0.18) : classic.opacity(0.15)
    }

    // MARK: - The countdown dial

    /// The dial's progress arc, given the colour Classic would use. Follows the
    /// accent swap: green on the light disc, gold on the dark one.
    func dial(classic: Color) -> Color {
        isStevenson ? StevensonBrand.accent : classic
    }

    /// The dial's unfilled remainder — the opposite school colour, so the ring
    /// reads as green *and* gold in both appearances.
    func dialTrack(classic: Color) -> Color {
        isStevenson ? StevensonBrand.dialTrack : classic.opacity(0.15)
    }

    func dial(for role: BlockRole) -> Color { dial(classic: ScheduleStyle.tint(for: role)) }

    func dialTrack(for role: BlockRole) -> Color {
        dialTrack(classic: ScheduleStyle.tint(for: role))
    }

    // MARK: - The timeline

    /// The "happening now" marker: the card's wash and the NOW pill's fill.
    /// Gold in both appearances — in dark mode that sets it apart from the gold
    /// *accent* by being a solid fill rather than tinted text.
    func now(for role: BlockRole) -> Color {
        isStevenson ? StevensonBrand.gold : ScheduleStyle.tint(for: role)
    }

    /// How strongly `now(for:)` washes the current card. Gold is a pale, warm
    /// fill at low alpha, so it needs more than the saturated system colours.
    var nowWashOpacity: Double { isStevenson ? 0.22 : 0.16 }

    /// Ink for the NOW pill. White fails on gold (2.4:1); near-black clears
    /// 5.6:1 — the pill's text colour has to follow its fill.
    var nowInk: Color { isStevenson ? StevensonBrand.ink : .white }

    /// The "In 12m" chip on the next block up. Held at green in both
    /// appearances so it stays distinct from the gold "now" marker.
    var upcoming: Color { isStevenson ? StevensonBrand.green : .green }
}

extension EnvironmentValues {
    @Entry var theme: Theme = .stevenson
}
