import SwiftUI
import ScheduleKit

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var scheduleScrollOffset: CGFloat = 0

    private var timerCompactProgress: CGFloat {
        min(max(scheduleScrollOffset / 120, 0), 1)
    }

    var body: some View {
        Group {
            if model.todayTimeline.isSchoolDay {
                VStack(spacing: 0) {
                    VStack(spacing: 22) {
                        HomeHeaderView()
                        HeroSection(compactProgress: timerCompactProgress)
                            .padding(.top, 6)
                        if model.shouldShowLunchPrompt {
                            LunchPromptCard()
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                    ScrollView {
                        DayTimelineListView()
                            .padding(.horizontal, 16)
                            .padding(.top, 22)
                            .padding(.bottom, 24)
                    }
                    .onScrollGeometryChange(for: CGFloat.self) { geometry in
                        max(geometry.contentOffset.y + geometry.contentInsets.top, 0)
                    } action: { _, newOffset in
                        scheduleScrollOffset = newOffset
                    }
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

/// One-time nudge: lunch selection is what makes midday times correct, which
/// is exactly when students check their phones.
struct LunchPromptCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "fork.knife.circle.fill")
                .font(.title2)
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("Set your lunch period")
                    .font(.subheadline.weight(.semibold))
                Text("Midday times depend on your lunch wave.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Set Up") {
                model.selectedTab = .settings
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.borderedProminent)
            .tint(.green)
            Button {
                model.dismissLunchPrompt()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.green.opacity(0.1))
        )
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
