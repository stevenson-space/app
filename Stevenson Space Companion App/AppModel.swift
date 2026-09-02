import Foundation
import SwiftUI
import Observation
import ScheduleKit
import StudentIDKit

/// Root observable store. Owns the resolver inputs (persisted via SharedStore),
/// derives today's timeline, and coordinates sync + notifications. All schedule
/// math lives in ScheduleKit; this type only orchestrates.
enum RootTab: Hashable {
    case home
    case lunch
    case id
    case settings
}

@Observable
@MainActor
final class AppModel {
    var selectedTab: RootTab = .home

    let store: SharedStore
    let catalog: BellScheduleCatalog
    private let syncService: ScheduleSyncService
    private let lunchSyncService: LunchMenuSyncService
    private let photoStore: StudentIDPhotoStore

    // MARK: Resolver inputs (every write goes through `store`)

    private(set) var config: UserConfig
    private(set) var overrides: [DayOverride]
    private(set) var prefs: NotificationPrefs
    private(set) var map: DayTypeMap?
    private(set) var fetchMetadata: FetchMetadata
    private(set) var isSyncing = false
    private(set) var lunchMenu: LunchMenu?
    private(set) var lunchFetchMetadata: FetchMetadata
    private(set) var isLunchSyncing = false
    /// Only ever written from a screenshot the extractor read; there is no code
    /// path, in this type or the UI, that builds one from typed input.
    private(set) var studentID: StudentIDCard?
    private(set) var studentIDPhoto: UIImage?

    // MARK: Derived

    private(set) var todayTimeline: DayTimeline
    /// Stored so SwiftUI observes boundary changes driven by the heartbeat.
    /// Computing this on demand would only track `todayTimeline`, which does
    /// not change when the clock crosses from passing into the next block.
    private(set) var currentState: MomentState
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
        self.lunchSyncService = LunchMenuSyncService(store: store)
        let photoStore = StudentIDPhotoStore()
        self.photoStore = photoStore

        // @Observable rewrites stored properties into computed accessors, so
        // work with locals until everything is assigned.
        let today = DayKey(date: Date())
        let config = store.userConfig
        let overrides = store.overrides
        let map = store.cachedMapData.flatMap { try? ScheduleDatesParser.parse($0) }
        let cachedLunchMenu = store.cachedLunchMenuData.flatMap { try? LunchMenuParser.parse($0) }
        let bundledLunchMenu = try? LunchMenuParser.loadBundled()
        let lunchMenu: LunchMenu?
        if let cachedLunchMenu,
           cachedLunchMenu.validFrom <= today, today <= cachedLunchMenu.validTo {
            lunchMenu = cachedLunchMenu
        } else if let bundledLunchMenu,
                  bundledLunchMenu.validFrom <= today, today <= bundledLunchMenu.validTo {
            lunchMenu = bundledLunchMenu
        } else {
            lunchMenu = [cachedLunchMenu, bundledLunchMenu]
                .compactMap { $0 }
                .max { $0.validTo < $1.validTo }
        }
        self.config = config
        self.overrides = overrides
        self.map = map
        self.prefs = store.notificationPrefs
        self.fetchMetadata = store.fetchMetadata
        self.lunchMenu = lunchMenu
        self.lunchFetchMetadata = store.lunchFetchMetadata

        let studentID = store.studentIDData.flatMap(StudentIDCard.decoded(from:))
        self.studentID = studentID
        // A photo with no card behind it is orphaned data; drop it rather than
        // keeping a face on disk for an ID that no longer exists.
        if studentID == nil {
            photoStore.remove()
            self.studentIDPhoto = nil
        } else {
            self.studentIDPhoto = photoStore.loadData().flatMap(UIImage.init(data:))
        }

        self.lastComputedDay = today
        let inputs = ResolverInputs(
            map: map,
            overrides: Dictionary(overrides.map { ($0.day, $0) }, uniquingKeysWith: { _, last in last }),
            config: config,
            catalog: catalog)
        let todayTimeline = resolveDay(today, inputs: inputs)
        self.todayTimeline = todayTimeline
        self.currentState = momentState(at: Date(), in: todayTimeline)

        self.nextSchoolDay = cachedNextSchoolDay(after: today)
        updateCurrentState()

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

    /// Lunch follows the website's policy: only regular school days, never
    /// weekends, breaks, or the Summer bell schedule.
    func lunchMenu(for day: DayKey) -> LunchMenuDay? {
        let timeline = timeline(for: day)
        guard timeline.isSchoolDay, timeline.family != .summer else { return nil }
        return lunchMenu?.menu(for: day)
    }

    /// The tab opens on today when lunch is served, otherwise the next day for
    /// which both the school calendar and lunch manifest have data.
    func preferredLunchDay(startingAt day: DayKey) -> DayKey {
        guard let menu = lunchMenu, day <= menu.validTo else { return day }

        var candidate = max(day, menu.validFrom)
        while candidate <= menu.validTo {
            if lunchMenu(for: candidate) != nil { return candidate }
            candidate = candidate.advanced(by: 1)
        }
        return day
    }

    func refreshDerived() {
        let today = self.today
        lastComputedDay = today
        todayTimeline = timeline(for: today)
        nextSchoolDay = cachedNextSchoolDay(after: today)
        updateCurrentState()
    }

    /// The next-school-day *search* depends only on the day, the synced map, and
    /// overrides — never on personalization — so the found `DayKey` is cached and
    /// only the (up-to-450-day) scan is skipped. The single re-resolve keeps the
    /// returned timeline fresh when config changes.
    private struct NextDayCache {
        let today: DayKey
        let map: DayTypeMap?
        let overrides: [DayOverride]
        let foundDay: DayKey?
    }
    private var nextDayCache: NextDayCache?

    private func cachedNextSchoolDay(after today: DayKey) -> DayTimeline? {
        if let cache = nextDayCache, cache.today == today,
           cache.map == map, cache.overrides == overrides {
            return cache.foundDay.map { timeline(for: $0) }
        }
        let found = findNextSchoolDay(after: today)
        nextDayCache = NextDayCache(today: today, map: map,
                                    overrides: overrides, foundDay: found?.day)
        return found
    }

    /// Called once per second by the app heartbeat. Cheap: a state lookup plus
    /// guarded writes — Observation only fans out when a value actually changes
    /// (block boundary or midnight rollover).
    func tick() {
        if today != lastComputedDay {
            refreshDerived()
            return
        }
        updateCurrentState()
    }

    private func updateCurrentState() {
        let state = momentState(at: now(), in: todayTimeline)
        if state != currentState {
            currentState = state
        }

        let id: String?
        switch state {
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
        // Re-selecting the same override is a no-op — skip the store write and
        // the resolve/reschedule churn it would trigger.
        if let existing = overrides.first(where: { $0.day == day }), existing.type == type {
            return
        }
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

    // MARK: - Student ID

    func saveStudentID(_ extraction: StudentIDExtraction) {
        guard let encoded = try? extraction.card.encoded() else { return }
        store.studentIDData = encoded
        studentID = extraction.card

        if let jpeg = extraction.photoJPEG {
            try? photoStore.save(jpeg)
            studentIDPhoto = UIImage(data: jpeg)
        } else {
            photoStore.remove()
            studentIDPhoto = nil
        }
    }

    func removeStudentID() {
        store.studentIDData = nil
        photoStore.remove()
        studentID = nil
        studentIDPhoto = nil
    }

    /// School years roll over in August, so an ID imported last year is worth a
    /// gentle nudge — the number rarely changes, but the grade on the card does.
    var studentIDIsFromAnEarlierSchoolYear: Bool {
        guard let start = studentID?.schoolYearStart else { return false }
        let components = SchoolTime.calendar.dateComponents([.year, .month], from: now())
        guard let year = components.year, let month = components.month else { return false }
        return start < (month >= 8 ? year : year - 1)
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
        Task {
            // Clear the ETag inside the sync actor (serialized with refresh),
            // then queue a forced resync rather than mutating the store directly.
            await syncService.invalidateETag()
            fetchMetadata = store.fetchMetadata
            await sync(force: true)
        }
    }

    private var pendingSync: Task<Void, Never>?
    private var syncGeneration = 0

    func sync(force: Bool) async {
        // Coalesce onto any in-flight sync. A non-forced request is satisfied by
        // the one already running; a forced request waits its turn and then runs,
        // so a URL/ETag change is queued instead of discarded.
        if let inFlight = pendingSync {
            await inFlight.value
            if !force { return }
        }
        syncGeneration += 1
        let generation = syncGeneration
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performSync(force: force)
        }
        pendingSync = task
        await task.value
        if syncGeneration == generation { pendingSync = nil }
    }

    private func performSync(force: Bool) async {
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

    private var pendingLunchSync: Task<Void, Never>?
    private var lunchSyncGeneration = 0

    func syncLunch(force: Bool) async {
        if let inFlight = pendingLunchSync, !force {
            await inFlight.value
            return
        }

        // Forced refreshes reserve a successor before awaiting the current
        // task. Concurrent callers therefore build one serial chain instead of
        // resuming together and starting overlapping requests.
        let predecessor = pendingLunchSync
        lunchSyncGeneration += 1
        let generation = lunchSyncGeneration
        isLunchSyncing = true
        let task = Task { @MainActor [weak self] in
            if let predecessor {
                await predecessor.value
            }
            guard let self else { return }
            await self.performLunchSync(force: force)
        }
        pendingLunchSync = task
        await task.value
        if lunchSyncGeneration == generation {
            pendingLunchSync = nil
            isLunchSyncing = false
        }
    }

    private func performLunchSync(force: Bool) async {
        let result = await lunchSyncService.refresh(force: force, now: Date())
        lunchFetchMetadata = store.lunchFetchMetadata
        if result == .updated, let cached = store.cachedLunchMenuData {
            lunchMenu = try? LunchMenuParser.parse(cached)
        }
    }

    func handleScenePhase(_ phase: ScenePhase) {
        guard phase == .active else { return }
        if today != lastComputedDay {
            refreshDerived()
        }
        rescheduleNotifications()
        Task { await sync(force: false) }
        Task { await syncLunch(force: false) }
    }

    /// Data is stale enough to mention only when a sync hasn't succeeded for a
    /// week — absence of exceptions is otherwise normal, not a warning.
    var isDataStale: Bool {
        guard let lastSuccess = fetchMetadata.lastSuccess else { return store.cachedMapData == nil }
        return now().timeIntervalSince(lastSuccess) > 7 * 24 * 3600
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
        let timeFormat = config.timeFormat
        Task {
            await NotificationScheduler.shared.reschedule(
                days: days, prefs: prefs, now: now, timeFormat: timeFormat)
        }
    }
}
