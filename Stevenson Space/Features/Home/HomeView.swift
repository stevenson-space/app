import SwiftUI
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
                    HomeDayPicker(day: day, today: today, select: selectDay)
                    if timeline.isSchoolDay {
                        HomeHeaderView(timeline: timeline)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
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
                                       compactHeight: $compactHeaderHeight)
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
        .onChange(of: navigation.homeTodayRequest) { _, _ in
            selectedDay = nil
            scrollPosition.scrollTo(edge: .top)
        }
        .onChange(of: today) { _, _ in
            selectedDay = nil
        }
        .onChange(of: timeline) { _, _ in
            scrollPosition.scrollTo(edge: .top)
        }
        #if DEBUG
        .overlay(alignment: .bottom) {
            if model.isTimeTraveling {
                TimeTravelBanner()
            }
        }
        #endif
    }

    private func selectDay(_ day: DayKey) {
        selectedDay = day == today ? nil : day
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
}

/// Settles a scroll that would come to rest part-way through the collapse, so
/// the hero is never left half-shrunk. It follows the direction of the scroll:
/// moving down, the hero collapses once it is `commitment` of the way there;
/// moving up, it expands once it has come back that far.
private struct CollapseSnap: ScrollTargetBehavior {
    static let commitment: CGFloat = 0.25

    let scroll: HomeScroll

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        let range = scroll.collapseRange
        // The target's origin is already measured from the top of the content,
        // like the offset the hero follows.
        let offset = target.rect.origin.y
        guard offset > range.lowerBound, offset < range.upperBound else { return }

        let progress = (offset - range.lowerBound) / (range.upperBound - range.lowerBound)
        let isScrollingDown = context.velocity.dy == 0
            ? scroll.isScrollingDown : context.velocity.dy > 0
        let collapses = isScrollingDown
            ? progress >= Self.commitment : progress > 1 - Self.commitment
        target.rect.origin.y = collapses ? range.upperBound : range.lowerBound
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
            .onChange(of: pinOffset...(pinOffset + range), initial: true) { _, span in
                scroll.collapseRange = span
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
