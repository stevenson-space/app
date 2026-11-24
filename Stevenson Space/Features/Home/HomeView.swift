import SwiftUI
import UIKit.UIGestureRecognizerSubclass
import ScheduleKit

struct HomeView: View {
    @Environment(SceneNavigation.self) private var navigation
    @Environment(AppModel.self) private var model
    // nil follows the live day, including midnight and foreground rollovers.
    @State private var selectedDay: DayKey?
    @State private var scroll = HomeScroll()
    @State private var viewportHeight: CGFloat = 0
    /// Scroll offset at which the hero reaches the top and pins.
    @State private var heroPinOffset: CGFloat = 0
    @State private var compactHeaderHeight: CGFloat = 0
    @State private var scrollPosition = ScrollPosition(edge: .top)
    @State private var showsCalendar = false
    /// Bumped by `selectDay` only, to play one selection haptic per change.
    @State private var dayChanges = 0
    /// Set while the Home tab takes another day back to today, so the new
    /// timeline keeps the animated scroll instead of jumping to the top.
    @State private var glidesToTop = false

    private var today: DayKey { model.todayTimeline.day }
    private var day: DayKey { selectedDay ?? today }

    var body: some View {
        let isToday = day == today
        let timeline = isToday ? model.todayTimeline : model.timeline(for: day)

        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                UpdateCheckSection(
                    title: "Schedule updates",
                    metadata: model.fetchMetadata,
                    isChecking: model.isSyncing,
                    spacing: 22,
                    checkForUpdates: {
                        await model.sync(force: true)
                        return model.fetchMetadata.lastError == nil
                    }
                ) {
                    HomeDayBar(day: day, today: today, select: selectDay) {
                        showsCalendar = true
                    }
                    if timeline.isSchoolDay {
                        HomeHeaderView(timeline: timeline)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 22)
                .onGeometryChange(for: CGFloat.self) { geometry in
                    geometry.size.height
                } action: { height in
                    heroPinOffset = height
                }

                if timeline.isSchoolDay {
                    if isToday {
                        Section {
                            // Fill the compact viewport with cards rather than a blank
                            // footer, while retaining enough scroll range for pinning.
                            DayTimelineListView(
                                timeline: timeline, isLive: true,
                                minimumHeight: max(viewportHeight - compactHeaderHeight - 24, 0))
                                .padding(.horizontal, 16)
                        } header: {
                            PinnedHero(scroll: scroll, pinOffset: heroPinOffset,
                                       compactHeight: $compactHeaderHeight,
                                       collapseRangeChanged: keepCollapseEnd)
                        }
                    } else {
                        DayTimelineListView(timeline: timeline, isLive: false)
                            .padding(.horizontal, 16)
                    }
                } else {
                    StatusScreenView(timeline: timeline, isLive: isToday)
                        .padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 24)
            .background {
                // The scroll phase can be stale once a finger has caught a
                // moving scroll, so also settle once UIKit says it has stopped.
                ScrollTouchReader(scroll: scroll) {
                    settleScroll(at: scroll.offset)
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { geometry in
            geometry.size.height
        } action: { height in
            viewportHeight = height
        }
        .scrollPosition($scrollPosition)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { old, offset in
            if offset != old { scroll.isScrollingDown = offset > old }
            scroll.offset = offset
        }
        .scrollTargetBehavior(CollapseSnap(scroll: scroll))
        .onScrollPhaseChange { _, phase, context in
            scroll.isAnimating = phase == .animating
            if phase == .interacting { scroll.settleTarget = nil }
            guard phase == .idle else { return }
            settleScroll(at: context.geometry.contentOffset.y + context.geometry.contentInsets.top)
        }
        .background(Color(.systemGroupedBackground))
        .overlay(alignment: .top) {
            GeometryReader { geometry in
                // Scroll views can draw into the safe area. Cover only the
                // status-bar region while leaving the pinned timer below it.
                Color(.systemGroupedBackground)
                    .frame(height: geometry.safeAreaInsets.top)
                    .offset(y: -geometry.safeAreaInsets.top)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .sheet(isPresented: $showsCalendar) {
            HomeDayPicker(day: day, today: today, select: selectDay)
        }
        #if DEBUG
        .overlay(alignment: .bottom) {
            if model.isTimeTraveling {
                TimeTravelBanner()
            }
        }
        #endif
        .sensoryFeedback(.selection, trigger: dayChanges)
        .onChange(of: navigation.homeTodayRequest) { _, _ in
            // Today glides back to the top, even when it replaces another day.
            glidesToTop = day != today
            selectedDay = nil
            withAnimation {
                scrollPosition.scrollTo(edge: .top)
            }
        }
        .onChange(of: today) { _, _ in
            selectedDay = nil
        }
        .onChange(of: timeline) { _, _ in
            guard !glidesToTop else {
                glidesToTop = false
                return
            }
            scrollPosition.scrollTo(edge: .top)
        }
    }

    /// The arrows, Today and the calendar all land here. Only these count as
    /// a change for the haptic, so the midnight rollover and the Home tab's
    /// return to today stay silent.
    private func selectDay(_ newDay: DayKey) {
        if newDay != day { dayChanges += 1 }
        selectedDay = newDay == today ? nil : newDay
    }

    private func settleScroll(at offset: CGFloat) {
        guard scroll.isAtRest else { return }
        guard let end = scroll.settledOffset(from: offset,
                                             isScrollingDown: scroll.isScrollingDown)
        else {
            // Resting on an end or outside the collapse, so any settle is over.
            // VoiceOver and keyboard scrolls never touch down, so nothing else
            // would clear it before they next stop part-way.
            scroll.settleTarget = nil
            return
        }
        guard end != scroll.settleTarget else { return }
        scroll.settleTarget = end
        // A timing curve avoids a spring's lingering movement near the end.
        withAnimation(.easeOut(duration: 0.25)) {
            scrollPosition.scrollTo(y: end)
        }
    }

    /// Keeps a resting hero on its end, or the list in place past the collapsed
    /// end, when the hero resizes or moves without a user scroll.
    private func keepCollapseEnd(from old: ClosedRange<CGFloat>, to new: ClosedRange<CGFloat>) {
        guard scroll.isAtRest,
              let offset = scroll.offsetKeepingEnd(from: old, to: new)
        else { return }
        scrollPosition.scrollTo(y: offset)
    }
}

/// Home's scroll offset. It lives outside `HomeView`'s own state so that
/// scrolling redraws only the pinned hero, not the whole screen.
@Observable
private final class HomeScroll {
    var offset: CGFloat = 0
    /// Scroll offsets, as in `offset`, that the hero collapses across. Read only
    /// when a scroll is about to settle, so it doesn't redraw anything.
    @ObservationIgnored var collapseRange: ClosedRange<CGFloat> = 0...0
    /// Which way the last movement went, for a scroll released without momentum.
    @ObservationIgnored var isScrollingDown = false
    /// Where the running settle is heading, so a second trigger for the same
    /// stop doesn't restart it.
    @ObservationIgnored var settleTarget: CGFloat?
    /// Whether a finger is on the scroll view, as UIKit reports it.
    @ObservationIgnored var isTouching = false
    /// The UIKit scroll view behind Home's `ScrollView`.
    @ObservationIgnored weak var scrollView: UIScrollView?
    /// Whether an animated scroll is running, such as a settle or the Home
    /// tab's return to the top, as the scroll phase reports it.
    @ObservationIgnored var isAnimating = false

    /// Whether nothing is moving the scroll, so a settle can't fight a finger,
    /// momentum or an animated scroll. Fingers and momentum come from UIKit,
    /// since the scroll phase can read idle while a finger is down, or stay
    /// behind once one lifts.
    var isAtRest: Bool {
        !isTouching && !isAnimating
            && !(scrollView?.isDragging ?? false) && !(scrollView?.isDecelerating ?? false)
    }

    /// How far through the collapse a scroll must get, going down, to carry on
    /// to the pill, and how far back, going up, to carry on to the full hero.
    private static let commitment: CGFloat = 0.25
    /// Subpoint rounding at either end that still counts as resting on it.
    private static let tolerance: CGFloat = 0.5

    /// The end of the collapse that a scroll resting at `offset` should settle
    /// on, or nil when it is already at one end or outside the collapse.
    func settledOffset(from offset: CGFloat, isScrollingDown: Bool) -> CGFloat? {
        guard isInsideCollapse(offset, collapseRange) else { return nil }
        let progress = (offset - collapseRange.lowerBound)
            / (collapseRange.upperBound - collapseRange.lowerBound)
        let collapses = isScrollingDown
            ? progress >= Self.commitment : progress > 1 - Self.commitment
        return collapses ? collapseRange.upperBound : collapseRange.lowerBound
    }

    /// Where the scroll should move once the collapse range changes under it,
    /// say when a bell swaps in a taller or shorter hero, so a hero resting on
    /// either end stays there, and a list scrolled past the collapsed end keeps
    /// its position. Nil when the scroll can stay put.
    func offsetKeepingEnd(from old: ClosedRange<CGFloat>, to new: ClosedRange<CGFloat>) -> CGFloat? {
        // Preserve the distance past the collapsed end as well as the end itself.
        // A shorter hero moves every card up, even far beyond the collapse range.
        // A zero-width range is one still being measured, with no end to keep.
        if old.upperBound - old.lowerBound > Self.tolerance,
           offset >= old.upperBound - Self.tolerance,
           abs(new.upperBound - old.upperBound) > Self.tolerance {
            return offset + new.upperBound - old.upperBound
        }
        guard isInsideCollapse(offset, new) else { return nil }
        if offset <= old.lowerBound + Self.tolerance {
            return offset + new.lowerBound - old.lowerBound
        }
        return nil
    }

    private func isInsideCollapse(_ offset: CGFloat, _ range: ClosedRange<CGFloat>) -> Bool {
        offset > range.lowerBound + Self.tolerance && offset < range.upperBound - Self.tolerance
    }
}

/// Carries a flick that would come to rest part-way through the collapse on to
/// an end, so the hero is never left half-shrunk. A scroll let go of nearly
/// still is left alone here: `HomeView` animates it itself once it stops, much
/// faster than the scroll view would carry it.
private struct CollapseSnap: ScrollTargetBehavior {
    /// Points per millisecond, the unit the scroll view reports its velocity
    /// in, below which a release counts as still.
    private static let stillSpeed: CGFloat = 0.2

    let scroll: HomeScroll

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        guard abs(context.velocity.dy) >= Self.stillSpeed else { return }
        // The target's origin is already measured from the top of the content,
        // like the offset the hero follows.
        if let end = scroll.settledOffset(from: target.rect.origin.y,
                                          isScrollingDown: context.velocity.dy > 0) {
            target.rect.origin.y = end
        }
    }
}

/// Follows fingers on the UIKit scroll view behind Home's `ScrollView`.
/// SwiftUI misses the finger that catches a moving scroll: the scroll phase
/// turns idle while it is still down, and a `DragGesture` hears of it late or
/// not at all, so a settle could start under the finger and jump on its next
/// move. A gesture recognizer on the scroll view sees every touch first.
private struct ScrollTouchReader: UIViewRepresentable {
    let scroll: HomeScroll
    /// Called once the last finger has lifted and the scroll view has stopped
    /// dragging and decelerating.
    let onRest: () -> Void

    func makeUIView(context: Context) -> Probe {
        Probe()
    }

    func updateUIView(_ probe: Probe, context: Context) {
        let observer = probe.observer
        observer.onTouchDown = { [scroll] in
            scroll.isTouching = true
            scroll.settleTarget = nil
        }
        observer.onLift = { [scroll] in
            scroll.isTouching = false
        }
        observer.onRest = onRest
        observer.onAttach = { [scroll] scrollView in
            scroll.scrollView = scrollView
        }
    }

    /// Sits inside the scroll content and hands the observer to the nearest
    /// scroll view above it.
    final class Probe: UIView {
        let observer = TouchObserver()

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            observer.view?.removeGestureRecognizer(observer)
            guard window != nil else { return }
            var ancestor = superview
            while let view = ancestor, !(view is UIScrollView) {
                ancestor = view.superview
            }
            guard let scrollView = ancestor as? UIScrollView else { return }
            scrollView.addGestureRecognizer(observer)
            observer.onAttach(scrollView)
        }
    }

    /// Reports touches without ever recognizing, delaying or blocking them,
    /// then watches the scroll view after a lift until it comes to rest.
    final class TouchObserver: UIGestureRecognizer {
        var onTouchDown: () -> Void = {}
        var onLift: () -> Void = {}
        var onRest: () -> Void = {}
        var onAttach: (UIScrollView) -> Void = { _ in }
        private var activeTouches: Set<UITouch> = []
        private var isDown = false
        private var restWatch: CADisplayLink?

        init() {
            super.init(target: nil, action: nil)
            cancelsTouchesInView = false
            delaysTouchesEnded = false
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            activeTouches.formUnion(touches)
            if !isDown {
                isDown = true
                stopWatchingForRest()
                onTouchDown()
            }
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
            endTouches(touches)
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
            endTouches(touches)
        }

        private func endTouches(_ touches: Set<UITouch>) {
            activeTouches.subtract(touches)
            // Failing ends this attempt; `reset()` then reports the lift.
            if activeTouches.isEmpty { state = .failed }
        }

        override func reset() {
            super.reset()
            activeTouches.removeAll()
            if isDown {
                isDown = false
                onLift()
                watchForRest()
            }
        }

        /// Checks once a frame, since UIKit doesn't announce the end of a drag
        /// or deceleration to anyone but the scroll view's delegate.
        private func watchForRest() {
            stopWatchingForRest()
            let link = CADisplayLink(target: self, selector: #selector(checkForRest))
            link.add(to: .main, forMode: .common)
            restWatch = link
        }

        @objc private func checkForRest() {
            guard let scrollView = view as? UIScrollView else {
                stopWatchingForRest()
                return
            }
            guard !scrollView.isDragging, !scrollView.isDecelerating else { return }
            stopWatchingForRest()
            onRest()
        }

        private func stopWatchingForRest() {
            restWatch?.invalidate()
            restWatch = nil
        }

        override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool {
            false
        }

        override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool {
            false
        }
    }
}

/// The hero above the day's cards. It keeps its full height in the layout, so
/// the list never jumps; once pinned, the part that shows gives way to the
/// list point for point until only the pill is left.
private struct PinnedHero: View {
    private static let insets = EdgeInsets(top: 12, leading: 16, bottom: 34, trailing: 16)

    let scroll: HomeScroll
    /// Scroll offset at which the hero reaches the top and pins.
    let pinOffset: CGFloat
    /// Height of the header once only the pill is left.
    @Binding var compactHeight: CGFloat
    /// Called with the old and new collapse ranges whenever the hero resizes or moves.
    let collapseRangeChanged: (ClosedRange<CGFloat>, ClosedRange<CGFloat>) -> Void

    @State private var fullHeight: CGFloat = 0
    @State private var pillHeight: CGFloat = 0

    var body: some View {
        // What the hero can give up, and how much of it the list has taken.
        let range = max(fullHeight - pillHeight, 0)
        let given = min(max(scroll.offset - pinOffset, 0), range)

        HeroSection(collapse: range > 0 ? given / range : 0, pillHeight: $pillHeight)
            .onGeometryChange(for: CGFloat.self) { geometry in
                geometry.size.height
            } action: { height in
                fullHeight = height
            }
            .padding(Self.insets)
            .frame(maxWidth: .infinity)
            .background(Color(.systemGroupedBackground))
            .clipShape(Rectangle().offset(y: -given))
            .onChange(of: pillHeight, initial: true) { _, height in
                compactHeight = height + Self.insets.top + Self.insets.bottom
            }
            .onChange(of: pinOffset...(pinOffset + range), initial: true) { old, span in
                scroll.collapseRange = span
                collapseRangeChanged(old, span)
            }
            .onDisappear { scroll.collapseRange = 0...0 }
    }
}

#if DEBUG
/// Visible whenever the DEBUG clock is shifted, so a screenshot can never be
/// mistaken for real time.
struct TimeTravelBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.arrow.2.circlepath")
            Text(model.now().formatted(date: .abbreviated, time: .shortened))
                .monospacedDigit()
            Button("Exit") {
                model.timeTravelOffset = 0
            }
            .font(.caption.weight(.bold))
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(.purple.opacity(0.9)))
        .foregroundStyle(.white)
        .padding(.bottom, 8)
    }
}
#endif
