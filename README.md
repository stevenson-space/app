# Stevenson Space Companion App

iOS bell-schedule app for Adlai E. Stevenson High School (D125). One glance answers:
**what period is it, how long until it changes, and what's next** — especially on the
days the normal times are wrong (Late Arrival, finals, assemblies, e-learning days).

## Architecture

```text
Packages/ScheduleKit/          All schedule logic — no UI, no clock access.
  Sources/ScheduleKit/
    Models/                    PeriodID, DayKey, Block, BellSchedule, UserConfig, DayTimeline…
    Catalog/                   Bundled bell tables + school-year boundaries
    Parsing/                   schedule-dates.json parser (exception-based map)
    Resolution/                resolveDay(...) priority chain + momentState(at:)
    Sync/                      ETag fetch with last-good cache semantics
    Storage/                   App-Group-ready SharedStore (UserDefaults suite)
    Notifications/             Pure NotificationPlanner (56 alerts + 1 refresh reminder)
  Tests/ScheduleKitTests/      The quality gate — run with `swift test`
Packages/StudentIDKit/         Student ID logic — no UI.
  Sources/StudentIDKit/
    Code39.swift               Encoder; Code39Decoder is the reader
    Code39Layout.swift         Pixel-snapped sizing so bars stay scannable
    StudentIDExtractor.swift   Screenshot → barcode, name, grade, year, photo
    StudentIDCard.swift        The model; its initializer is internal by design
  Tests/StudentIDKitTests/     Includes a Vision round-trip on rendered symbols
Stevenson Space Companion App/ SwiftUI app target: Home, Lunch, ID, Settings
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

## The ID tab

The school stopped issuing physical IDs, so a student imports one screenshot of
the Infinite Campus Student Profile page. The app reads the Code 39 barcode, the
name, grade, and school year, crops the photo, and redraws the ID as a card whose
barcode is re-encoded from the same payload the school issued.

Two rules shape the code. **Nothing is typeable**: `StudentIDCard`'s initializer
is internal to StudentIDKit, so the only source of a name or number is
`StudentIDExtractor`, and the decoder re-validates stored values. And **the card
does not follow dark mode**: a printed card does not invert, and the barcode has
to stay black on white to scan.

Vision cannot create its barcode or face detectors in the iOS Simulator, so
StudentIDKit carries its own Code 39 reader and a geometric photo finder and
falls back to them. That keeps the feature testable and usable off-device, and
covers a device where Vision declines a symbol.

The source screenshot is never stored — only the extracted fields (in
`sk.studentID`) and the cropped photo (in Application Support).

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

## Lunch menu refresh

The app checks the website's lunch menu when it launches or returns to the
foreground, at most once per hour since the last attempt (including failed
attempts). This is an eligibility interval, not an hourly timer: leaving the app
open does not trigger another network check, and there is no background refresh.

Pull down in the Lunch tab to check immediately, bypassing the one-hour limit.
The status below the week picker shows the check in progress, the last successful
check, or a failure with the saved/bundled menu kept available. A successful check
can leave the dishes unchanged when the website has no new menu data. Selecting
another date uses the downloaded rotation and does not require a new fetch.

## Development

- Logic tests (fast, no simulator): `swift test --package-path Packages/ScheduleKit`
  and `swift test --package-path Packages/StudentIDKit`
- App build: `xcodebuild -scheme "Stevenson Space Companion App" -destination 'generic/platform=iOS Simulator' build`
- **Time travel**: DEBUG builds have a Developer section in Settings — jump the
  app clock to any instant or use one-tap scenarios (finals rotations, async
  days, breaks…). A purple banner shows whenever the clock is shifted.
- Pending-notification inspector: Settings → Developer — Notifications.

## Deferred (architecture is ready for them)

Widgets and Live Activities (ScheduleKit + SharedStore are App-Group-ready; add
the entitlement + extension targets), BGAppRefresh, appearance settings, ICS
hint layer.
