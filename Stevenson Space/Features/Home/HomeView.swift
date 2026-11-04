import SwiftUI
import ScheduleKit

struct HomeView: View {
    @Environment(SceneNavigation.self) private var navigation
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appColorScheme) private var appColorScheme
    // nil follows the live day, including midnight and foreground rollovers.
    @State private var selectedDay: DayKey?
    @State private var isTimerCompact = false
    @State private var viewportHeight: CGFloat = 0
    @State private var compactHeaderHeight: CGFloat = 0
    @State private var scrollPosition = ScrollPosition(edge: .top)
    @State private var showsCalendar = false

    private var today: DayKey { model.todayTimeline.day }
    private var day: DayKey { selectedDay ?? today }

    /// Green while a block is on, gold between bells, the lining otherwise.
    /// Preview days are always the lining: nothing is happening on them yet.
    private var ground: JacketGround {
        day == today ? JacketGround(state: model.currentState) : .lining
    }

    var body: some View {
        let isToday = day == today
        let timeline = isToday ? model.todayTimeline : model.timeline(for: day)
        let ground = ground

        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    UpdateCheckSection(
                        title: "Schedule updates",
                        metadata: model.fetchMetadata,
                        isChecking: model.isSyncing,
                        spacing: 24,
                        checkForUpdates: {
                            await model.sync(force: true)
                            return model.fetchMetadata.lastError == nil
                        }
                    ) {
                        if timeline.isSchoolDay {
                            HomeHeaderView(timeline: timeline)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, timeline.isSchoolDay ? 28 : 8)

                    if timeline.isSchoolDay {
                        if isToday {
                            Section {
                                // Fill the compact viewport with rows rather than a
                                // blank footer, while keeping enough scroll range to pin.
                                DayTimelineListView(
                                    timeline: timeline, isLive: true, title: "Today",
                                    minimumHeight: max(viewportHeight - compactHeaderHeight - 60, 0))
                                    .padding(.horizontal, 20)
                            } header: {
                                pinnedHero(timeline: timeline)
                            }
                        } else {
                            DayTimelineListView(
                                timeline: timeline, isLive: false,
                                title: TimeDisplay.dayLabel(day, relativeTo: today))
                                .padding(.horizontal, 20)
                        }
                    } else {
                        StatusScreenView(timeline: timeline, isLive: isToday)
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                    }
                }
                .padding(.bottom, 32)
                .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86), value: isTimerCompact)
            }
            .onGeometryChange(for: CGFloat.self) { geometry in
                geometry.size.height
            } action: { height in
                viewportHeight = height
            }
            .scrollPosition($scrollPosition)
            .onScrollGeometryChange(for: Int.self) { geometry in
                let offset = geometry.contentOffset.y + geometry.contentInsets.top
                return offset <= 16 ? 0 : (offset > 32 ? 2 : 1)
            } action: { _, region in
                // Use hysteresis to avoid toggling during a small drag near the top.
                if region == 2 { isTimerCompact = true }
                if region == 0 { isTimerCompact = false }
            }
            .background { FieldBackground(ground: ground, day: day) }
            .environment(\.jacketGround, ground)
            .foregroundStyle(ground.ink)
            .tint(ground == .lining ? Jacket.accent : ground.ink)
            .animation(reduceMotion ? .easeInOut(duration: 0.25) : .spring(duration: 0.55, bounce: 0),
                       value: ground)
            .onChange(of: ground, initial: true) { _, newGround in
                navigation.homeGround = newGround
            }
            .sensoryFeedback(.impact(weight: .heavy), trigger: ground) { old, new in
                // The bell: a live change between the field and the gold side.
                isToday && old != .lining && new != .lining
            }
            .toolbar {
                HomeDayToolbar(day: day, today: today, select: selectDay, showsCalendar: $showsCalendar)
            }
            .navigationBarTitleDisplayMode(.inline)
            .homeBars(ground: ground, isDark: ground.isDark(in: appColorScheme))
            .sheet(isPresented: $showsCalendar) {
                HomeDayPicker(day: day, today: today, select: selectDay)
                    .environment(\.colorScheme, appColorScheme)
            }
            #if DEBUG
            .overlay(alignment: .bottom) {
                if model.isTimeTraveling {
                    TimeTravelBanner()
                }
            }
            #endif
        }
        .onChange(of: navigation.homeTodayRequest) { _, _ in
            selectedDay = nil
            isTimerCompact = false
            scrollPosition.scrollTo(edge: .top)
        }
        .onChange(of: today) { _, _ in
            selectedDay = nil
        }
        .onChange(of: timeline) { _, _ in
            isTimerCompact = false
            scrollPosition.scrollTo(edge: .top)
        }
    }

    private func pinnedHero(timeline: DayTimeline) -> some View {
        HeroSection(timeline: timeline, isCompact: isTimerCompact)
            .padding(.horizontal, isTimerCompact ? 16 : 20)
            .padding(.top, isTimerCompact ? 4 : 8)
            .padding(.bottom, isTimerCompact ? 20 : 44)
            .frame(maxWidth: .infinity)
            .background {
                HeroSection(timeline: timeline, isCompact: true)
                    .padding(.top, 4)
                    .padding(.bottom, 20)
                    .fixedSize(horizontal: false, vertical: true)
                    .hidden()
                    .accessibilityHidden(true)
                    .onGeometryChange(for: CGFloat.self) { geometry in
                        geometry.size.height
                    } action: { height in
                        compactHeaderHeight = height
                    }
            }
    }

    private func selectDay(_ day: DayKey) {
        selectedDay = day == today ? nil : day
    }
}

private extension View {
    /// Bars over the ground: the status bar and tab bar take light content on
    /// the field (and in dark mode), dark content on the gold and the lining.
    /// iOS 26 lets content scroll under the toolbar with its edge effect;
    /// earlier versions get a bar of the ground's own colour.
    @ViewBuilder
    func homeBars(ground: JacketGround, isDark: Bool) -> some View {
        let scheme: ColorScheme = isDark ? .dark : .light
        if #available(iOS 26, *) {
            toolbarColorScheme(scheme, for: .navigationBar, .tabBar)
                .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        } else {
            toolbarColorScheme(scheme, for: .navigationBar, .tabBar)
                .toolbarBackground(ground.background, for: .navigationBar)
                .toolbarBackgroundVisibility(.visible, for: .navigationBar)
        }
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
