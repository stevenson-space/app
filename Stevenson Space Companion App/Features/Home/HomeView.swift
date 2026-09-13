import SwiftUI
import ScheduleKit

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // nil follows the live day, including midnight and foreground rollovers.
    @State private var selectedDay: DayKey?
    @State private var isTimerCompact = false
    @State private var viewportHeight: CGFloat = 0

    private var today: DayKey { model.todayTimeline.day }
    private var day: DayKey { selectedDay ?? today }

    var body: some View {
        let isToday = day == today
        let timeline = isToday ? model.todayTimeline : model.timeline(for: day)

        ScrollView {
            LazyVStack(spacing: 22, pinnedViews: [.sectionHeaders]) {
                VStack(spacing: 22) {
                    HomeDayPicker(day: day, today: today, select: selectDay)
                    if timeline.isSchoolDay {
                        HomeHeaderView(timeline: timeline)
                    }
                }

                if timeline.isSchoolDay {
                    if isToday {
                        Section {
                            DayTimelineListView(timeline: timeline, isLive: true)
                        } header: {
                            HeroSection(isCompact: isTimerCompact)
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity)
                                .background(Color(.systemGroupedBackground))
                        }
                    } else {
                        DayTimelineListView(timeline: timeline, isLive: false)
                    }
                } else {
                    StatusScreenView(timeline: timeline, isLive: isToday)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
            // Preserve a small scroll range on short schedules and large screens
            // so collapsing cannot clamp straight back to the expanded state.
            .frame(minHeight: isToday && timeline.isSchoolDay ? viewportHeight + 34 : nil,
                   alignment: .top)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isTimerCompact)
        }
        .onGeometryChange(for: CGFloat.self) { geometry in
            geometry.size.height
        } action: { height in
            viewportHeight = height
        }
        .onScrollGeometryChange(for: Int.self) { geometry in
            let offset = geometry.contentOffset.y + geometry.contentInsets.top
            return offset <= 0 ? 0 : (offset > 32 ? 2 : 1)
        } action: { _, region in
            // Keep the compact header until the top is reached, even if its
            // smaller height causes the scroll view to clamp its offset.
            if region == 2 { isTimerCompact = true }
            if region == 0 { isTimerCompact = false }
        }
        .background(Color(.systemGroupedBackground))
        .onChange(of: today) { _, _ in
            selectedDay = nil
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
