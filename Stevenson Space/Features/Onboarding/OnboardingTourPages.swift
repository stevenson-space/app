import SwiftUI
import ScheduleKit

// MARK: - Welcome

struct OnboardingWelcomePage: View {
    @Environment(OnboardingFlow.self) private var flow

    var body: some View {
        OnboardingPage(brand: true) {
            FirstBell(isActive: flow.step == .welcome)
        } content: {
            Text("Stevenson Space")
                .font(.largeTitle.bold())
                .tracking(-0.4)
                .accessibilityAddTraits(.isHeader)
            Text("Know the period, the minutes left, and what's next, even on Late Arrival and finals days.")
                .font(.title3)
                .foregroundStyle(StevensonPalette.onGreenSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } actions: {
            Button("Take the Tour", action: flow.advance)
            Button("Skip Tour", action: flow.skipTour)
                .onboardingSecondary()
                .accessibilityHint("Skips to the end of the tour")
        }
    }
}

/// The welcome's one moment: a clock ring runs out the last seconds of a
/// period, and the bell rings.
private struct FirstBell: View {
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress = 0.0
    @State private var secondsLeft = 3
    @State private var hasRung = false
    @State private var rings = 0

    var body: some View {
        ZStack {
            ForEach(0..<60, id: \.self) { tick in
                let major = tick % 5 == 0
                Capsule()
                    .fill(.white.opacity(major ? 0.6 : 0.25))
                    .frame(width: major ? 3 : 1.5, height: major ? 12 : 6)
                    .offset(y: -120)
                    .rotationEffect(.degrees(Double(tick) * 6))
            }
            Group {
                Circle()
                    .stroke(.white.opacity(0.12), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(StevensonPalette.gold, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .padding(26)

            if hasRung {
                Image(systemName: "bell.fill")
                    .font(.system(size: 76, weight: .semibold))
                    .foregroundStyle(StevensonPalette.gold)
                    .symbolEffect(.wiggle, value: rings)
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            } else {
                Text("0:0\(secondsLeft)")
                    .font(.system(size: 60, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    .transition(.opacity)
            }
        }
        .frame(width: 252, height: 252)
        .sensoryFeedback(.impact(weight: .medium), trigger: rings)
        .task(id: isActive) { await ring() }
        .accessibilityHidden(true)
    }

    private func ring() async {
        guard isActive, !hasRung else { return }
        if reduceMotion {
            progress = 1
            hasRung = true
            return
        }
        guard await pause(0.4) else { return }
        // A clock hand sweeps at a constant rate, so this is the one linear curve.
        withAnimation(.linear(duration: 2.4)) { progress = 1 }
        for second in [2, 1, 0] {
            guard await pause(0.8) else { return }
            withAnimation(.snappy) { secondsLeft = second }
        }
        withAnimation(.spring(duration: 0.5, bounce: 0.35)) { hasRung = true }
        guard await pause(0.2) else { return }
        rings += 1
    }
}

/// Sleeps, reporting whether the demo should carry on (false once cancelled).
func pause(_ seconds: Double) async -> Bool {
    (try? await Task.sleep(for: .seconds(seconds))) != nil
}

// MARK: - Home countdown

struct OnboardingCountdownPage: View {
    @Environment(OnboardingFlow.self) private var flow

    var body: some View {
        OnboardingPage {
            CountdownDemo(isActive: flow.step == .countdown)
        } content: {
            OnboardingHeadline(
                eyebrow: "Home",
                title: "Every period, counted down",
                message: "Home shows how long until the bell and what's next. Passing periods get their own countdown, so you know when to start walking.")
        } actions: {
            Button("Continue", action: flow.advance)
        }
    }
}

/// The end of Chemistry, the walk to lunch, and the start of Lunch, played
/// fast through Home's own dial and passing card.
private struct CountdownDemo: View {
    let isActive: Bool
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var clock: Date?

    var body: some View {
        if let day = OnboardingSample.lunchApproach(catalog: model.catalog) {
            let now = clock ?? day.chemistry.end.addingTimeInterval(-75)
            let offset = now.timeIntervalSinceNow
            let pref = model.config.timeFormat
            Group {
                if now < day.chemistry.end {
                    dial(day.chemistry, next: day.lunch, offset: offset, pref: pref)
                } else if now < day.lunch.start {
                    PassingHero(to: day.lunch, kind: .betweenPeriods, offset: offset, pref: pref)
                        .padding(.horizontal, 24)
                } else {
                    dial(day.lunch, next: day.afterLunch, offset: offset, pref: pref)
                }
            }
            .id(now < day.chemistry.end ? 0 : now < day.lunch.start ? 1 : 2)
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.94)))
            .task(id: isActive) { await play(day) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Example: Home counting down the end of AP Chemistry, the passing period, and Lunch")
        }
    }

    private func dial(_ span: ResolvedSpan, next: ResolvedSpan?, offset: TimeInterval,
                      pref: TimeFormatPref) -> some View {
        VStack(spacing: 14) {
            CountdownDial(start: span.start, end: span.end,
                          tint: ScheduleStyle.tint(for: span.role),
                          offset: offset, label: "left in \(span.displayName)")
            if let next {
                Label("Next: \(next.displayName)\(next.room.map { " · Rm \($0)" } ?? "") at \(TimeDisplay.time(next.start, pref))",
                      systemImage: "arrow.right")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func play(_ day: OnboardingSample.LunchApproach) async {
        guard isActive else { return }
        guard !reduceMotion else {
            // Hold one moment; the dial still ticks in real time.
            clock = day.chemistry.end.addingTimeInterval(-9 * 60)
            return
        }
        // Each scene runs at its own speed: seconds for the bell, minutes for
        // the walk, so the whole loop takes about twenty seconds.
        let scenes: [(from: Date, to: Date, step: TimeInterval)] = [
            (day.chemistry.end.addingTimeInterval(-75), day.chemistry.end, 3),
            (day.chemistry.end, day.lunch.start, 20),
            (day.lunch.start, day.lunch.start.addingTimeInterval(45), 3),
        ]
        while !Task.isCancelled {
            for scene in scenes {
                var time = scene.from
                withAnimation(.smooth(duration: 0.4)) { clock = time }
                while time < scene.to {
                    guard await pause(0.25) else { return }
                    time = min(time.addingTimeInterval(scene.step), scene.to)
                    withAnimation(.smooth(duration: 0.25)) { clock = time }
                }
            }
            guard await pause(1.5) else { return }
        }
    }
}

// MARK: - Special schedules

struct OnboardingSpecialDaysPage: View {
    @Environment(OnboardingFlow.self) private var flow

    var body: some View {
        OnboardingPage {
            DayShapeDemo(isActive: flow.step == .specialDays)
        } content: {
            OnboardingHeadline(
                eyebrow: "Special schedules",
                title: "Right on the odd days",
                message: "Late Arrival, assemblies, and finals all move the bells. The app follows the school calendar and switches schedules for you. Tap the date on Home to check any day ahead.")
        } actions: {
            Button("Continue", action: flow.advance)
        }
    }
}

/// Real bell tables morphing into one another: periods slide later, shrink,
/// reorder for finals, and make room for activities and assemblies.
private struct DayShapeDemo: View {
    let isActive: Bool
    @Environment(AppModel.self) private var model
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0

    private static let kinds: [(BellFamily, EDRotation?)] = [
        (.standard, nil), (.lateArrival, nil), (.activityPeriod, nil),
        (.pmAssembly, nil), (.earlyDismissal, .rotation1),
    ]

    var body: some View {
        let schedules = Self.kinds.compactMap { model.catalog.schedule(family: $0.0, rotation: $0.1) }
        if let schedule = schedules.isEmpty ? nil : schedules[index % schedules.count],
           let first = schedule.fullBlocks.first, let last = schedule.fullBlocks.last {
            let pref = model.config.timeFormat
            let name = OverrideType.bell(family: schedule.family, rotation: schedule.rotation).displayName
            Button(action: step) {
                schedulePreview(schedule, name: name, first: first, last: last, pref: pref)
            }
            .buttonStyle(.plain)
            // Keyed on the index too, so a tap restarts the wait.
            .task(id: isActive ? index : -1) { await cycle() }
            .accessibilityLabel("Example schedule: \(name)")
            .accessibilityValue("First bell \(time(first.start, pref)), out at \(time(last.end, pref))")
            .accessibilityHint("Shows the next schedule")
        }
    }

    private func schedulePreview(_ schedule: BellSchedule, name: String, first: Block, last: Block,
                                 pref: TimeFormatPref) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            // Overlaid while they swap, rather than stacked by the VStack.
            ZStack(alignment: .leading) {
                badge(name, family: schedule.family)
                    .id(name)
                    .transition(reduceMotion ? .opacity : .push(from: .bottom))
            }
            .clipped()
            VStack(alignment: .leading, spacing: 2) {
                Text(time(first.start, pref))
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("First bell · out at \(time(last.end, pref))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            DayBar(schedule: schedule)
        }
        .padding(.horizontal, 24)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func badge(_ name: String, family: BellFamily) -> some View {
        if family == .standard {
            Label(name, systemImage: ScheduleStyle.icon(for: family))
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
        } else {
            let fill = ScheduleStyle.badgeFill(for: family, contrast: contrast)
            Label(name, systemImage: ScheduleStyle.icon(for: family))
                .font(.headline)
                .foregroundStyle(.contrasting(on: fill))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(fill, in: .capsule)
        }
    }

    private func time(_ time: HourMinute, _ pref: TimeFormatPref) -> String {
        OnboardingSample.day.date(at: time).map { TimeDisplay.time($0, pref) } ?? ""
    }

    private func step() {
        withAnimation(reduceMotion ? nil : .spring(duration: 0.6, bounce: 0.1)) { index += 1 }
    }

    private func cycle() async {
        guard isActive, await pause(2.8) else { return }
        step()
    }
}

/// One school day from 8:00 to 3:30, each block placed at its real time.
private struct DayBar: View {
    let schedule: BellSchedule

    private static let opens = 8 * 60
    private static let closes = 15 * 60 + 30

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.quaternary.opacity(0.6))
                ForEach(schedule.fullBlocks, id: \.id) { block in
                    let x = position(block.start) * proxy.size.width
                    let width = (position(block.end) - position(block.start)) * proxy.size.width
                    // Placed by layout rather than offset, so a block that
                    // appears scales in where it sits.
                    segment(block)
                        .frame(width: max(width - 2, 4))
                        .alignmentGuide(.leading) { _ in -(x + 1) }
                        .transition(.opacity.combined(with: .scale(scale: 0.5)))
                }
            }
        }
        .frame(height: 64)
    }

    private func position(_ time: HourMinute) -> CGFloat {
        CGFloat(time.totalMinutes - Self.opens) / CGFloat(Self.closes - Self.opens)
    }

    @ViewBuilder
    private func segment(_ block: Block) -> some View {
        if let number = block.id.periodNumber {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(ScheduleStyle.tint(for: .classPeriod).opacity(0.18))
                .overlay {
                    Text("\(number)")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(ScheduleStyle.tint(for: .classPeriod))
                        .minimumScaleFactor(0.5)
                }
        } else {
            let role = Self.role(of: block.id)
            let tint = ScheduleStyle.tint(for: role)
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tint)
                .overlay {
                    Image(systemName: ScheduleStyle.icon(for: role))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.contrasting(on: tint))
                        .minimumScaleFactor(0.5)
                }
        }
    }

    private static func role(of id: PeriodID) -> BlockRole {
        switch id {
        case .homeroom: .homeroom
        case .activity: .activity
        case .assembly: .assembly
        case .makeup: .makeup
        case .summer: .summerSchool
        case .period: .classPeriod
        }
    }
}

// MARK: - Lunch

struct OnboardingLunchPage: View {
    @Environment(OnboardingFlow.self) private var flow

    var body: some View {
        OnboardingPage {
            LunchDemo(isActive: flow.step == .lunch)
        } content: {
            OnboardingHeadline(
                eyebrow: "Lunch",
                title: "Every station, every day",
                message: "See all six stations for any school day, and plan ahead with the week strip. Try it: tap a day.")
        } actions: {
            Button("Continue", action: flow.advance)
        }
    }
}

/// The real menu for this week, walking itself across the days until the
/// student taps one.
private struct LunchDemo: View {
    let isActive: Bool
    @Environment(AppModel.self) private var model
    @State private var selected: DayKey?
    @State private var userPicked = false

    var body: some View {
        let start = model.preferredLunchDay(startingAt: model.today)
        let week = Self.weekdays(containing: start)
        let day = selected ?? start
        VStack(spacing: 16) {
            HStack(spacing: 0) {
                ForEach(week, id: \.self) { candidate in
                    WeekdayButton(
                        day: candidate,
                        weekday: LunchDateDisplay.narrowWeekday(candidate),
                        isSelected: candidate == day,
                        isToday: candidate == model.today,
                        hasMenu: model.lunchMenu(for: candidate) != nil,
                        accent: StevensonPalette.accent,
                        accessibilityLabel: LunchDateDisplay.accessibilityLabel(candidate),
                        select: {
                            userPicked = true
                            selected = candidate
                        })
                }
            }

            Group {
                if let menu = model.lunchMenu(for: day) {
                    // A Grid, not a lazy one, so both tiles in a row share a height.
                    Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                        ForEach(Array(stride(from: 0, to: menu.sections.count, by: 2)), id: \.self) { row in
                            GridRow {
                                ForEach(menu.sections[row..<min(row + 2, menu.sections.count)]) { section in
                                    StationTile(section: section)
                                }
                            }
                        }
                    }
                } else {
                    Label("No lunch menu for this day", systemImage: "calendar.badge.minus")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 120)
                }
            }
            .id(day)
            .transition(.opacity)
        }
        .padding(.horizontal, 20)
        // An illustration of the Lunch tab; the tab itself scales fully.
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .animation(.smooth(duration: 0.3), value: day)
        .task(id: isActive) { await walk(week) }
    }

    private func walk(_ week: [DayKey]) async {
        guard isActive else { return }
        let served = week.filter { model.lunchMenu(for: $0) != nil }
        guard served.count > 1 else { return }
        var index = served.firstIndex(of: selected ?? served[0]) ?? 0
        while await pause(2.4), !userPicked {
            index = (index + 1) % served.count
            selected = served[index]
        }
    }

    private static func weekdays(containing day: DayKey) -> [DayKey] {
        let daysAfterMonday = ((day.weekday() ?? 2) + 5) % 7
        let monday = day.advanced(by: -daysAfterMonday)
        return (0..<5).map { monday.advanced(by: $0) }
    }
}

/// One lunch station, trimmed to its first dish so the week fits on screen.
private struct StationTile: View {
    let section: LunchMenuSection

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: section.station.icon)
                .font(.subheadline)
                .foregroundStyle(section.station.color)
                .frame(width: 30, height: 30)
                .background(section.station.color.opacity(0.12), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(section.station.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(section.items.first ?? "")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(section.station.title): \(section.items.joined(separator: ", "))")
    }
}

// MARK: - Student ID

struct OnboardingStudentIDPage: View {
    @Environment(OnboardingFlow.self) private var flow

    var body: some View {
        OnboardingPage {
            IDDemo(isActive: flow.step == .studentID)
        } content: {
            OnboardingHeadline(
                eyebrow: "ID",
                title: "Your student ID, ready to scan",
                message: "Import one screenshot of your Infinite Campus profile. The app reads the barcode and keeps a card ready for the scanner. It stays on this iPhone.")
        } actions: {
            Button("Continue", action: flow.advance)
        }
    }
}

/// The ID tab's empty card, catching the light as if held up to a scanner.
private struct IDDemo: View {
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweep = -1.0

    var body: some View {
        StudentIDCardView(content: .placeholder)
            .overlay {
                GeometryReader { proxy in
                    LinearGradient(colors: [.clear, .white.opacity(0.5), .clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: proxy.size.width * 0.35)
                        .rotationEffect(.degrees(18))
                        .offset(x: sweep * proxy.size.width)
                        .blendMode(.plusLighter)
                        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
                        // The card's own corner radius (StudentIDCardView.Metrics.corner).
                        .clipShape(RoundedRectangle(cornerRadius: proxy.size.width * 0.043, style: .continuous))
                }
                .allowsHitTesting(false)
            }
            .padding(.horizontal, 32)
            .task(id: isActive) { await shine() }
            .accessibilityHidden(true)
    }

    private func shine() async {
        guard isActive, !reduceMotion else { return }
        while await pause(1.2) {
            sweep = -0.4
            withAnimation(.easeInOut(duration: 1.1)) { sweep = 1.1 }
            guard await pause(2) else { return }
        }
    }
}

// MARK: - Widgets

struct OnboardingWidgetsPage: View {
    @Environment(OnboardingFlow.self) private var flow

    var body: some View {
        OnboardingPage {
            WidgetsDemo()
        } content: {
            OnboardingHeadline(
                eyebrow: "Widgets",
                title: "The bell on your Home Screen",
                message: "Put the countdown and lunch menu on your Home Screen, and the countdown on your Lock Screen. Touch and hold the Home Screen, tap Edit, then Add Widget, and search for SHS Space.")
        } actions: {
            Button("Continue", action: flow.advance)
        }
    }
}

/// Small renditions of the real widgets on a Stevenson-green wallpaper, with
/// the countdown ticking live.
private struct WidgetsDemo: View {
    @Environment(AppModel.self) private var model
    @State private var bell = Date.now.addingTimeInterval(12 * 60 + 4)

    var body: some View {
        let lunch = model.lunchMenu(for: model.preferredLunchDay(startingAt: model.today))?
            .sections.first
        VStack(spacing: 18) {
            HStack(spacing: 16) {
                widget {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Period ends in")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ScheduleStyle.tint(for: .classPeriod))
                        TickingCountdown(target: bell, offset: 0, size: 34)
                        Text("AP Chemistry")
                            .font(.headline)
                            .lineLimit(1)
                        Text("Room 1616")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                widget {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("LUNCH", systemImage: "fork.knife")
                            .font(.caption2.weight(.bold))
                            .tracking(1.2)
                            .foregroundStyle(ScheduleStyle.tint(for: .classPeriod))
                        if let lunch {
                            Label(lunch.station.title, systemImage: lunch.station.icon)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(lunch.station.color)
                                .lineLimit(1)
                            Text(lunch.items.first ?? "")
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(3)
                        }
                    }
                }
            }

            HStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
                VStack(alignment: .leading, spacing: 0) {
                    Text("Period ends in")
                        .font(.caption2)
                    TickingCountdown(target: bell, offset: 0, size: 22, tint: .white)
                    Text("AP Chemistry")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.white)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .frame(maxWidth: 316)
        }
        .padding(22)
        .background {
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(LinearGradient(colors: [StevensonPalette.green, Color(red: 0.05, green: 0.16, blue: 0.11)],
                                     startPoint: .top, endPoint: .bottom))
        }
        .padding(.horizontal, 24)
        .dynamicTypeSize(...DynamicTypeSize.large)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Example widgets: a period countdown and today's lunch on the Home Screen, and a countdown on the Lock Screen")
    }

    private func widget(@ViewBuilder content: () -> some View) -> some View {
        content()
            .padding(14)
            .frame(width: 150, height: 150, alignment: .topLeading)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
