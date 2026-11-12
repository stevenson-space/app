import SwiftUI
import AppIntents
import ScheduleKit

struct OnboardingSiriPage: View {
    @Environment(OnboardingFlow.self) private var flow
    @State private var generation = SiriGeneration.current

    var body: some View {
        OnboardingPage {
            SiriDemo(generation: generation, isActive: flow.step == .siri)
        } content: {
            OnboardingHeadline(
                eyebrow: "Siri",
                title: "Just ask Siri",
                message: "Ask about your classes, lunch, or your student ID, and Siri answers without opening the app. Say Stevenson Space or SHS Space.")
            if SiriGeneration.mightBeSiriAI {
                // Siri AI is an opt-in no API reveals, so the student says.
                VStack(alignment: .leading, spacing: 8) {
                    Text("Which Siri do you use?")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Picker("Which Siri do you use?", selection: $generation) {
                        Text("Siri").tag(SiriGeneration.appleIntelligence)
                        Text("Siri AI").tag(SiriGeneration.siriAI)
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.top, 4)
            }
            ShortcutsLink()
                .shortcutsLinkStyle(.automaticOutline)
                .padding(.top, 4)
        } actions: {
            Button("Continue", action: flow.advance)
        }
    }
}

/// One thing to say to Siri, and the answer the app's App Shortcut gives.
private struct SiriRequest {
    enum Answer {
        case text(String)
        case studentID

        /// The answer as words: the card's text, and what VoiceOver reads.
        var spoken: String {
            switch self {
            case .text(let text): text
            case .studentID: "Your student ID is opening."
            }
        }
    }

    let phrase: String
    let answer: Answer

    /// The request and its answer, as VoiceOver reads the demo.
    var spokenExchange: String {
        "\(phrase.hasSuffix("?") ? phrase : phrase + ".") \(answer.spoken)"
    }

    /// When the requests happen: mid-Chemistry on the sample Monday.
    static let moment = HourMinute(hour: 10, minute: 52)

    /// The sample student's day at 10:52, phrased the way the intents phrase
    /// their dialogs. Both app names appear, since either works.
    static func examples(model: AppModel) -> [SiriRequest] {
        let pref = model.config.timeFormat
        let blocks = OnboardingSample.timeline(catalog: model.catalog).blocks
        var requests: [SiriRequest] = []

        func summary(_ block: ResolvedBlock) -> String {
            let period = block.spanLabel.map { "Period \($0)" } ?? block.periodID.defaultDisplayName
            let room = block.room.map { ", room \($0)" } ?? ""
            return "\(block.displayName), \(period)\(room), from \(TimeDisplay.time(block.start, pref)) to \(TimeDisplay.time(block.end, pref))."
        }

        let lunchIndex = blocks.firstIndex { $0.role == .lunch }
        if let lunchIndex, lunchIndex > 0 {
            requests.append(SiriRequest(phrase: "What period is it in SHS Space?",
                                        answer: .text(summary(blocks[lunchIndex - 1]))))
            if let next = blocks[lunchIndex...].first(where: { $0.role == .classPeriod }) {
                requests.append(SiriRequest(phrase: "Where is my next class in Stevenson Space?",
                                            answer: .text("Next is \(summary(next))")))
            }
        }

        // The sample Monday's menu matches the clock behind Siri. Once the
        // bundled menu moves past it, the next real lunch stands in; with no
        // menu at all, the answer is the one the shortcut gives then.
        let menuDay = [OnboardingSample.day, model.preferredLunchDay(startingAt: model.today)]
            .first { model.lunchMenu(for: $0) != nil }
        let lunch = menuDay.flatMap { model.lunchMenu(for: $0) }.map { menu in
            menu.sections.prefix(2)
                .map { "\($0.station.title): \($0.items.joined(separator: ", "))" }
                .joined(separator: "\n")
        }
        let lunchDay = TimeDisplay.shortDayLabel(menuDay ?? OnboardingSample.day)
        requests.append(SiriRequest(
            phrase: "What's for lunch in SHS Space?",
            answer: .text("Lunch for \(lunchDay).\n\(lunch ?? "The lunch menu is unavailable for this date.")")))

        requests.append(SiriRequest(phrase: "Show my student ID in Stevenson Space",
                                    answer: .studentID))
        return requests
    }
}

/// Requests played on a phone screen, with Siri drawn the way this iPhone
/// shows it: the orb, the Apple Intelligence edge glow, or Siri AI's bubble in
/// the Dynamic Island. The answers are the app's, never Siri's own voice.
private struct SiriDemo: View {
    let generation: SiriGeneration
    let isActive: Bool
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0
    @State private var beat = Beat.idle
    @State private var words = 0

    enum Beat: Int, Comparable {
        case idle, listening, answering

        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    var body: some View {
        let requests = SiriRequest.examples(model: model)
        let request = requests[index % requests.count]
        TimelineView(.animation(paused: !isActive || reduceMotion)) { context in
            // Wrapped to an hour: angles of ~10⁹ radians lose all precision
            // once the renderer converts them to Float.
            let time = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600)
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 46, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.09, green: 0.10, blue: 0.14),
                                                  Color(red: 0.02, green: 0.02, blue: 0.04)],
                                         startPoint: .top, endPoint: .bottom))
                SampleLockScreen(isDimmed: beat > .idle)

                switch generation {
                case .classic:
                    conversation(request)
                        .padding(.top, 34)
                    SiriOrb(time: time, isActive: beat > .idle, isListening: beat == .listening)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 22)
                case .appleIntelligence:
                    conversation(request)
                        .padding(.top, 34)
                    SiriEdgeGlow(time: time, cornerRadius: 46)
                        .opacity(beat > .idle ? 1 : 0)
                case .siriAI:
                    SiriIsland(time: time, beat: beat) {
                        conversation(request)
                    }
                    .padding(.top, 11)
                }
            }
        }
        .frame(height: 360)
        .padding(.horizontal, 24)
        .environment(\.colorScheme, .dark)
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .animation(reduceMotion ? nil : .spring(duration: 0.55, bounce: 0.15), value: beat)
        .animation(.smooth(duration: 0.2), value: words)
        .task(id: isActive) { await play(count: requests.count) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Things to ask Siri")
        .accessibilityValue(requests.map(\.spokenExchange).joined(separator: " "))
    }

    /// What the student said, word by word, then the app's answer.
    @ViewBuilder
    private func conversation(_ request: SiriRequest) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if beat > .idle {
                transcript(request.phrase)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
            if beat == .answering {
                SiriAnswerCard(answer: request.answer)
                    .transition(.asymmetric(
                        insertion: reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 16)),
                        removal: .opacity))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22)
    }

    /// Words appear as they're heard; the hidden ones keep their place so the
    /// line never reflows.
    private func transcript(_ phrase: String) -> Text {
        phrase.split(separator: " ").enumerated().reduce(Text(verbatim: "")) { text, item in
            let word = Text(verbatim: (item.offset == 0 ? "" : " ") + item.element)
                .foregroundStyle(item.offset < words ? Color.white : Color.white.opacity(0))
            return Text("\(text)\(word)")
        }
    }

    private func play(count: Int) async {
        guard isActive else { return }
        if reduceMotion {
            while !Task.isCancelled {
                words = .max
                beat = .answering
                guard await pause(4.5) else { return }
                withAnimation(.easeInOut(duration: 0.3)) { index += 1 }
            }
            return
        }
        while !Task.isCancelled {
            let phrase = SiriRequest.examples(model: model)[index % count].phrase
            guard await pause(0.6) else { return }
            beat = .listening
            guard await pause(0.5) else { return }
            for word in 1...phrase.split(separator: " ").count {
                words = word
                guard await pause(0.16) else { return }
            }
            guard await pause(0.35) else { return }
            beat = .answering
            guard await pause(3.2) else { return }
            beat = .idle
            guard await pause(0.45) else { return }
            words = 0
            index += 1
        }
    }
}

/// The sample moment as a Lock Screen shows it, so the answers read as
/// happening then. Siri blurs it while active, as the real one does.
private struct SampleLockScreen: View {
    let isDimmed: Bool
    @Environment(AppModel.self) private var model

    var body: some View {
        let day = OnboardingSample.day
        VStack(spacing: 0) {
            Text(LunchDateDisplay.header(day))
                .font(.title3.weight(.semibold))
            if let date = day.date(at: SiriRequest.moment) {
                Text(TimeDisplay.time(date, model.config.timeFormat, includesMeridiem: false))
                    .font(.system(size: 84, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
        }
        .foregroundStyle(.white.opacity(0.9))
        .padding(.top, 64)
        .blur(radius: isDimmed ? 14 : 0)
        .opacity(isDimmed ? 0.35 : 1)
    }
}

/// The App Shortcut's reply, as Siri shows an app's dialog and snippet.
private struct SiriAnswerCard: View {
    let answer: SiriRequest.Answer

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text("SHS Space")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "clock.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(StevensonPalette.green, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            switch answer {
            case .text(let text):
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            case .studentID:
                HStack(spacing: 12) {
                    StudentIDCardView(content: .placeholder)
                        .frame(width: 96)
                    Text(answer.spoken)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

// MARK: - The three looks

/// Apple Intelligence's colours, in the order they run around the glow.
private let intelligenceColors: [Color] = [
    Color(red: 1.00, green: 0.62, blue: 0.20), Color(red: 1.00, green: 0.33, blue: 0.47),
    Color(red: 0.76, green: 0.38, blue: 1.00), Color(red: 0.25, green: 0.53, blue: 1.00),
    Color(red: 0.36, green: 0.85, blue: 1.00), Color(red: 1.00, green: 0.62, blue: 0.20),
]

/// Classic Siri: a dark sphere of coloured light that swells with the voice.
private struct SiriOrb: View {
    let time: TimeInterval
    let isActive: Bool
    let isListening: Bool

    private static let ribbons = [
        Color(red: 0.15, green: 0.5, blue: 1), Color(red: 1, green: 0.2, blue: 0.55),
        Color(red: 0.15, green: 0.9, blue: 0.8), Color(red: 0.6, green: 0.3, blue: 1),
    ]

    var body: some View {
        let level = isListening ? 0.5 + 0.5 * abs(sin(time * 7) * sin(time * 2.3)) : 0.25
        ZStack {
            Circle().fill(.black)
            ForEach(Array(Self.ribbons.enumerated()), id: \.offset) { index, color in
                Ellipse()
                    .fill(color)
                    .frame(width: 64, height: 18 + 22 * level)
                    .blur(radius: 5)
                    .rotationEffect(.radians(time * (0.8 + Double(index) * 0.4) + Double(index) * 1.6))
                    .blendMode(.screen)
            }
            Circle()
                .fill(RadialGradient(colors: [.white.opacity(0.4), .clear],
                                     center: .center, startRadius: 0, endRadius: 10 + 8 * level))
                .blendMode(.screen)
        }
        .frame(width: 72, height: 72)
        .clipShape(Circle())
        .overlay { Circle().strokeBorder(.white.opacity(0.18), lineWidth: 1) }
        .scaleEffect(isActive ? 1 + 0.06 * level : 0.2)
        .opacity(isActive ? 1 : 0)
    }
}

/// Siri with Apple Intelligence: light running around the edge of the screen.
private struct SiriEdgeGlow: View {
    let time: TimeInterval
    let cornerRadius: CGFloat

    var body: some View {
        let gradient = AngularGradient(colors: intelligenceColors, center: .center,
                                       angle: .radians(time * 1.6))
        let edge = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            edge.strokeBorder(gradient, lineWidth: 18).blur(radius: 16).opacity(0.8)
            edge.strokeBorder(gradient, lineWidth: 8).blur(radius: 5)
            edge.strokeBorder(gradient, lineWidth: 3)
        }
        .clipShape(edge)
        .allowsHitTesting(false)
    }
}

/// Siri AI on iOS 27: the Dynamic Island grows into a glass bubble with a
/// glowing rim, and the conversation happens inside it.
private struct SiriIsland<Content: View>: View {
    let time: TimeInterval
    let beat: SiriDemo.Beat
    @ViewBuilder let content: Content

    var body: some View {
        let isOpen = beat > .idle
        let shape = RoundedRectangle(cornerRadius: isOpen ? 30 : 19, style: .continuous)
        let rim = AngularGradient(colors: intelligenceColors, center: .center, angle: .radians(time * 1.8))
        content
            .padding(.vertical, isOpen ? 18 : 0)
            .frame(width: isOpen ? nil : 124, height: isOpen ? nil : 37)
            .frame(maxWidth: isOpen ? .infinity : 124)
            .opacity(isOpen ? 1 : 0)
            .background {
                ZStack {
                    shape.fill(.black)
                    shape.fill(.white.opacity(isOpen ? 0.08 : 0))
                    shape.strokeBorder(rim, lineWidth: 6).blur(radius: 10).opacity(isOpen ? 0.9 : 0)
                    shape.strokeBorder(rim, lineWidth: 1.5).opacity(isOpen ? 1 : 0)
                }
            }
            .padding(.horizontal, isOpen ? 12 : 0)
    }
}
