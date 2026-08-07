# Stevenson Space Companion App

iOS bell-schedule app for Adlai E. Stevenson High School (D125). One glance answers:
**what period is it, how long until it changes, and what's next** — especially on the
days the normal times are wrong (Late Arrival, finals, assemblies, e-learning days).

## Architecture

```
Packages/ScheduleKit/          All schedule logic — no UI, no clock access.
  Sources/ScheduleKit/
    Models/                    PeriodID, DayKey, Block, BellSchedule, UserConfig, DayTimeline…
    Catalog/                   Bundled bell tables + school-year boundaries
    Parsing/                   schedule-dates.json parser (exception-based map)
    Resolution/                resolveDay(...) priority chain + momentState(at:)
    Sync/                      ETag fetch with last-good cache semantics
    Storage/                   App-Group-ready SharedStore (UserDefaults suite)
    Notifications/             Pure NotificationPlanner (56-slot budget)
  Tests/ScheduleKitTests/      The quality gate — run with `swift test`
Stevenson Space Companion App/ SwiftUI app target: Home, Settings, system glue
```

Two pure functions are the heart of everything; every surface (and the future
widgets/Live Activity) must go through them so all surfaces agree:

```swift
resolveDay(day, inputs:)          // date → personalized DayTimeline
momentState(at: now, in: timeline) // instant → what's happening right now
```

**Resolution priority:** manual override → remote JSON map → outside-school-year
(never defaults to Standard) → bundled break ranges → weekend → Standard weekday
(by design, not a guess). All date math in `America/Chicago` via calendar
components — never `+24h` arithmetic (DST-safe).

## Data sources and the yearly update runbook

1. **Bell tables** (`Packages/ScheduleKit/Sources/ScheduleKit/Resources/bell-schedules.json`)
   — bundled, ship with the app. If the school changes bell times, edit this file
   and ship an update. The test suite validates ordering, A/B tiling, and both
   Early Dismissal rotations on every run.

2. **School-year boundaries** (`Catalog/../Models/SchoolYear.swift` →
   `SchoolYearCatalog`) — bundled Swift constants. **Each year, append the new
   `SchoolYear`** (first/last day, winter/spring break ranges, labeled days like
   Freshman Orientation). Outside these bounds the app shows Summer Break instead
   of guessing Standard.

3. **Day-type map** — the live JSON shared with stevenson.space:
   `https://raw.githubusercontent.com/stevenson-space/shs/main/src/data/schedule-dates.json`
   (branch ref on purpose; a commit-pinned URL would freeze updates). It lists
   only exceptions (`Late Arrival`, `Activity Period`, `PM Assembly`,
   `Early Dismissal`, `No School`, `Asynchronous`); unlisted in-session weekdays
   are Standard. Ranges use `"12/17/2026-12/18/2026"`. Early Dismissal rotation
   is inferred from position within a range (1st school-weekday → periods
   6·2·3·4, 2nd → 5·1·7·8). The app refetches with ETag on launch/foreground
   (1 h throttle) and always keeps the last good copy if a fetch or parse fails.

## Development

- Logic tests (fast, no simulator): `swift test --package-path Packages/ScheduleKit`
- App build: `xcodebuild -scheme "Stevenson Space Companion App" -destination 'generic/platform=iOS Simulator' build`
- **Time travel**: DEBUG builds have a Developer section in Settings — jump the
  app clock to any instant or use one-tap scenarios (finals rotations, async
  days, breaks…). A purple banner shows whenever the clock is shifted.
- Pending-notification inspector: Settings → Developer — Notifications.

## Deferred (architecture is ready for them)

Widgets and Live Activities (ScheduleKit + SharedStore are App-Group-ready; add
the entitlement + extension targets), BGAppRefresh, appearance settings, ICS
hint layer.
