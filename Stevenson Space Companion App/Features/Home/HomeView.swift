import SwiftUI
import ScheduleKit

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    // nil follows the live day, including midnight and foreground rollovers.
    @State private var selectedDay: DayKey?

    private var today: DayKey { model.todayTimeline.day }
    private var day: DayKey { selectedDay ?? today }

    var body: some View {
        let isToday = day == today
        let timeline = isToday ? model.todayTimeline : model.timeline(for: day)

        ScrollView {
            VStack(spacing: 22) {
                HomeDayPicker(day: day, today: today, select: selectDay)

                if timeline.isSchoolDay {
                    HomeHeaderView(timeline: timeline)
                    if isToday {
                        HeroSection()
                            .padding(.top, 6)
                    }
                    DayTimelineListView(timeline: timeline, isLive: isToday)
                } else {
                    StatusScreenView(timeline: timeline, isLive: isToday)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                selectedDay = nil
            }
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
