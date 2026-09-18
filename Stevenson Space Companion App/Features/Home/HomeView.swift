import SwiftUI
import ScheduleKit

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // nil follows the live day, including midnight and foreground rollovers.
    @State private var selectedDay: DayKey?
    @State private var isTimerCompact = false
    @State private var viewportHeight: CGFloat = 0
    @State private var compactHeaderHeight: CGFloat = 0
    @State private var scrollPosition = ScrollPosition(edge: .top)

    private var today: DayKey { model.todayTimeline.day }
    private var day: DayKey { selectedDay ?? today }

    var body: some View {
        let isToday = day == today
        let timeline = isToday ? model.todayTimeline : model.timeline(for: day)

        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                VStack(spacing: 22) {
                    HomeDayPicker(day: day, today: today, select: selectDay)
                    if timeline.isSchoolDay {
                        HomeHeaderView(timeline: timeline)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 22)

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
                            HeroSection(isCompact: isTimerCompact)
                                .padding(.horizontal, 16)
                                .padding(.top, 12)
                                .padding(.bottom, 34)
                                .frame(maxWidth: .infinity)
                                .background(Color(.systemGroupedBackground))
                                .background {
                                    HeroSection(isCompact: true)
                                        .padding(.horizontal, 16)
                                        .padding(.top, 12)
                                        .padding(.bottom, 34)
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
        .onChange(of: today) { _, _ in
            selectedDay = nil
        }
        .onChange(of: timeline) { _, _ in
            isTimerCompact = false
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
