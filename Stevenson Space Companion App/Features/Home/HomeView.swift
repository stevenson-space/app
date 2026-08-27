import SwiftUI
import ScheduleKit

struct HomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.todayTimeline.isSchoolDay {
                ScrollView {
                    VStack(spacing: 22) {
                        HomeHeaderView()
                        if model.isHalfPeriodViewAvailable {
                            ScheduleViewModePicker()
                        }
                        HeroSection()
                            .padding(.top, 6)
                        DayTimelineListView()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
            } else {
                ScrollView {
                    StatusScreenView()
                        .padding(.top, 40)
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        #if DEBUG
        .overlay(alignment: .bottom) {
            if model.isTimeTraveling {
                TimeTravelBanner()
            }
        }
        #endif
    }
}

private struct ScheduleViewModePicker: View {
    @Environment(AppModel.self) private var model

    private var selection: Binding<ScheduleViewMode> {
        Binding(
            get: { model.homeScheduleViewMode },
            set: { viewMode in
                withAnimation(.snappy) {
                    model.setHomeScheduleViewMode(viewMode)
                }
            })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Schedule view")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Picker("Schedule view", selection: selection) {
                ForEach(ScheduleViewMode.allCases, id: \.self) { viewMode in
                    Text(viewMode.displayName).tag(viewMode)
                }
            }
            .pickerStyle(.segmented)
        }
        .accessibilityHint("Switches between full-period and half-period bell times")
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
