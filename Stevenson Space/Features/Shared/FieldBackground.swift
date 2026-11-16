import SwiftUI
import ScheduleKit

/// The ground under Home, and the signature: when a bell changes the ground
/// while the day is live, the new colour rises from the bottom edge over the
/// old one, like the jacket turned to its other side. Any other change (a
/// different day, a rollover) cross-fades, and Reduce Motion always does.
struct FieldBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appColorScheme) private var appColorScheme

    let ground: JacketGround
    let day: DayKey

    @State private var shown: JacketGround?
    @State private var rising: JacketGround?
    @State private var progress: CGFloat = 0

    private struct Change: Equatable {
        let ground: JacketGround
        let day: DayKey
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            (shown ?? ground).background.resolved(for: appColorScheme)
            if let rising {
                // A flat colour scaled from the bottom edge looks the same as
                // one growing upward, and animates as a transform.
                rising.background.resolved(for: appColorScheme)
                    .scaleEffect(x: 1, y: progress, anchor: .bottom)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .onChange(of: Change(ground: ground, day: day)) { old, new in
            guard old.ground != new.ground else { return }
            if shown == nil { shown = old.ground }
            // Settle an unfinished rise before starting the next change.
            if let rising {
                shown = rising
                self.rising = nil
                progress = 0
            }
            if old.day == new.day && !reduceMotion {
                rise(to: new.ground)
            } else {
                withAnimation(.easeInOut(duration: 0.25)) { shown = new.ground }
            }
        }
    }

    private func rise(to newGround: JacketGround) {
        rising = newGround
        progress = 0
        withAnimation(.spring(duration: 0.55, bounce: 0)) {
            progress = 1
        } completion: {
            guard rising == newGround else { return }
            shown = newGround
            rising = nil
            progress = 0
        }
    }
}
