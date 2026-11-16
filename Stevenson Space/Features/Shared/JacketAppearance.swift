import SwiftUI
import ScheduleKit

/// Navigation bar titles in the jacket's voice: large titles are varsity
/// numbers (SF Pro Expanded Heavy) in the accent with a gold twill edge.
enum JacketAppearance {
    static func configure() {
        let twill = NSShadow()
        twill.shadowColor = UIColor(Jacket.twill)
        twill.shadowOffset = CGSize(width: 2, height: 2.5)
        twill.shadowBlurRadius = 0

        let large = UIFontMetrics(forTextStyle: .largeTitle)
            .scaledFont(for: .systemFont(ofSize: 34, weight: .heavy, width: .expanded))
        let inline = UIFontMetrics(forTextStyle: .headline)
            .scaledFont(for: .systemFont(ofSize: 17, weight: .bold, width: .expanded))

        let bar = UINavigationBar.appearance()
        bar.largeTitleTextAttributes = [
            .font: large,
            .foregroundColor: dynamic(Jacket.accent),
            .shadow: twill,
        ]
        bar.titleTextAttributes = [
            .font: inline,
            .foregroundColor: dynamic(Jacket.ink),
        ]
    }

    private static func dynamic(_ color: Color) -> UIColor {
        let light = UIColor(color.resolved(for: .light))
        let dark = UIColor(color.resolved(for: .dark))
        return UIColor { $0.userInterfaceStyle == .dark ? dark : light }
    }
}
