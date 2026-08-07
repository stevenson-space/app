import Foundation
import SwiftUI
import Observation
import ScheduleKit

/// Root observable store. Owns the resolver inputs (persisted via SharedStore),
/// derives today's timeline, and coordinates sync + notifications. All schedule
/// math lives in ScheduleKit; this type only orchestrates.
enum RootTab: Hashable {
    case home
    case settings
}

@Observable
@MainActor
final class AppModel {
    var selectedTab: RootTab = .home

    let store: SharedStore
    let catalog: BellScheduleCatalog
    private let syncService: ScheduleSyncService

    // MARK: Resolver inputs (every write goes through `store`)

    private(set) var config: UserConfig
    private(set) var overrides: [DayOverride]
    private(set) var prefs: NotificationPrefs
    private(set) var map: DayTypeMap?
    private(set) var fetchMetadata: FetchMetadata
    private(set) var isSyncing = false

    // MARK: Derived

    private(set) var todayTimeline: DayTimeline
    /// The next upcoming school (or async) day — powers "done for today",
    /// weekend, and break screens.
    private(set) var nextSchoolDay: DayTimeline?
    /// Changes only at block boundaries, so the day list re-renders per
    /// boundary, not per second.
    private(set) var currentSpanID: String?
    private var lastComputedDay: DayKey

    private var dayChangeObserver: NSObjectProtocol?

    // MARK: Time travel (DEBUG builds only)

    #if DEBUG
    var timeTravelOffset: TimeInterval = 0 {
        didSet {
            refreshDerived()
            // Cheap when nothing changed (plan-hash short-circuit); keeps the
            // notification queue consistent with the traveled clock.
            rescheduleNotifications()
        }
    }
    var isTimeTraveling: Bool { timeTravelOffset != 0 }
    #endif

    init(store: SharedStore = SharedStore()) {
        self.store = store
        do {
            self.catalog = try BellScheduleCatalog.loadBundled()
        } catch {
            // The bundle ships inside the binary and is validated by tests;
            // failing to load it is a programmer error, not a runtime state.
            fatalError("Bundled bell schedules failed to load: \(error)")
        }
        self.syncService = ScheduleSyncService(store: store)

        // @Observable rewrites stored properties into computed accessors, so
        // work with locals until everything is assigned.
        let config = store.userConfig
        let overrides = store.overrides
        let map = store.cachedMapData.flatMap { try? ScheduleDatesParser.parse($0) }
        self.config = config
        self.overrides = overrides
        self.map = map
        self.prefs = store.notificationPrefs
        self.fetchMetadata = store.fetchMetadata

        let today = DayKey(date: Date())
        self.lastComputedDay = today
        let inputs = ResolverInputs(
            map: map,
            overrides: Dictionary(overrides.map { ($0.day, $0) }, uniquingKeysWith: { _, last in last }),
            config: config,
            catalog: catalog)
        self.todayTimeline = resolveDay(today, inputs: inputs)

        self.nextSchoolDay = findNextSchoolDay(after: today)
        updateCurrentSpan()

        dayChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSCalendarDayChanged, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshDerived() }
        }
    }

    // MARK: - Clock

    func now() -> Date {
        #if DEBUG
        Date().addingTimeInterval(timeTravelOffset)
        #else
        Date()
        #endif
    }

    /// Offset views add to wall-clock dates from TimelineView contexts, so
    /// ticking UI follows time travel in DEBUG builds. Zero in release.
    var displayOffset: TimeInterval {
        #if DEBUG
        return timeTravelOffset
        #else
        return 0
        #endif
    }

    var today: DayKey { DayKey(date: now()) }

    // MARK: - Resolution

    private var overridesByDay: [DayKey: DayOverride] {
        Dictionary(overrides.map { ($0.day, $0) }, uniquingKeysWith: { _, last in last })
    }

    private var resolverInputs: ResolverInputs {
        ResolverInputs(map: map, overrides: overridesByDay, config: config, catalog: catalog)
    }

    func timeline(for day: DayKey) -> DayTimeline {
        resolveDay(day, inputs: resolverInputs)
    }

    var currentState: MomentState {
        momentState(at: now(), in: todayTimeline)
    }

    func refreshDerived() {
        let today = self.today
        lastComputedDay = today
        todayTimeline = timeline(for: today)
        nextSchoolDay = findNextSchoolDay(after: today)
        updateCurrentSpan()
    }

    /// Called once per second by the hero's TimelineView. Cheap: a state
    /// lookup plus two guarded writes — Observation only fans out when a value
    /// actually changes (block boundary or midnight rollover).
    func tick() {
        if today != lastComputedDay {
            refreshDerived()
            return
        }
        updateCurrentSpan()
    }

    private func updateCurrentSpan() {
        let id: String?
        switch currentState {
        case .inBlock(let current, _): id = current.id
        case .passing(let from, _, _): id = "passing-\(from.id)"
        case .beforeSchool: id = "before"
        case .afterSchool: id = "after"
        default: id = nil
        }
        if id != currentSpanID {
            currentSpanID = id
        }
    }

    private func findNextSchoolDay(after day: DayKey, limit: Int = 450) -> DayTimeline? {
        var candidate = day.advanced(by: 1)
        for _ in 0..<limit {
            let timeline = timeline(for: candidate)
            if timeline.isSchoolDay || timeline.kind == .asynchronous {
                return timeline
            }
            candidate = candidate.advanced(by: 1)
        }
        return nil
    }

    // MARK: - Mutations (each persists, re-derives, and reschedules)

    func updateConfig(_ transform: (inout UserConfig) -> Void) {
        var updated = config
        transform(&updated)
        guard updated != config else { return }
        config = updated
        store.userConfig = updated
        refreshDerived()
        rescheduleNotifications()
    }

    func updatePrefs(_ transform: (inout NotificationPrefs) -> Void) {
        var updated = prefs
        transform(&updated)
        guard updated != prefs else { return }
        prefs = updated
        store.notificationPrefs = updated
        rescheduleNotifications()
    }

    func setOverride(day: DayKey, type: OverrideType) {
        overrides.removeAll { $0.day == day }
        overrides.append(DayOverride(day: day, type: type))
        overrides.sort { $0.day < $1.day }
        store.overrides = overrides
        refreshDerived()
        rescheduleNotifications()
    }

    func removeOverride(day: DayKey) {
        overrides.removeAll { $0.day == day }
        store.overrides = overrides
        refreshDerived()
        rescheduleNotifications()
    }

    // MARK: - Sync

    var mapURL: URL { store.mapURL }

    func setMapURL(_ url: URL) {
        store.mapURL = url
        invalidateETagAndResync()
    }

    func resetMapURL() {
        store.resetMapURL()
        invalidateETagAndResync()
    }

    private func invalidateETagAndResync() {
        var metadata = store.fetchMetadata
        metadata.etag = nil
        store.fetchMetadata = metadata
        fetchMetadata = metadata
        Task { await sync(force: true) }
    }

    func sync(force: Bool) async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        // Throttling runs on the real clock even while time-traveling.
        let result = await syncService.refresh(force: force, now: Date())
        fetchMetadata = store.fetchMetadata
        if result == .updated, let cached = store.cachedMapData {
            map = try? ScheduleDatesParser.parse(cached)
            refreshDerived()
            rescheduleNotifications()
        }
    }

    func handleScenePhase(_ phase: ScenePhase) {
        guard phase == .active else { return }
        if today != lastComputedDay {
            refreshDerived()
        }
        rescheduleNotifications()
        Task { await sync(force: false) }
    }

    /// Data is stale enough to mention only when a sync hasn't succeeded for a
    /// week — absence of exceptions is otherwise normal, not a warning.
    var isDataStale: Bool {
        guard let lastSuccess = fetchMetadata.lastSuccess else { return store.cachedMapData == nil }
        return now().timeIntervalSince(lastSuccess) > 7 * 24 * 3600
    }

    // MARK: - Lunch prompt card

    var lunchPromptDismissed: Bool { store.lunchPromptDismissed }

    func dismissLunchPrompt() {
        store.lunchPromptDismissed = true
        lunchPromptVersion += 1
    }

    /// Bumped so views observing the prompt state re-render (the flag itself
    /// lives in UserDefaults, outside Observation).
    private var lunchPromptVersion = 0

    var shouldShowLunchPrompt: Bool {
        _ = lunchPromptVersion
        return config.lunch == nil && !store.lunchPromptDismissed
    }

    // MARK: - Notifications

    private(set) var notificationAuthDenied = false

    /// Enabling a notification feature must clear the system permission first;
    /// on denial the toggle snaps back and Settings explains why.
    func setNotificationFeatureEnabled(_ feature: WritableKeyPath<NotificationPrefs, Bool>, _ enabled: Bool) {
        guard enabled else {
            updatePrefs { $0[keyPath: feature] = false }
            return
        }
        Task {
            let granted = await NotificationScheduler.shared.ensureAuthorization()
            if granted {
                notificationAuthDenied = false
                updatePrefs { $0[keyPath: feature] = true }
            } else {
                notificationAuthDenied = true
                updatePrefs { $0[keyPath: feature] = false }
            }
        }
    }

    func rescheduleNotifications() {
        let days = (0..<14).map { timeline(for: today.advanced(by: $0)) }
        let prefs = self.prefs
        let now = self.now()
        Task {
            await NotificationScheduler.shared.reschedule(days: days, prefs: prefs, now: now)
        }
    }
}
