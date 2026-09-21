# Stevenson Space Companion App

iOS bell-schedule app for Adlai E. Stevenson High School (D125). One glance answers:
**what period is it, how long until it changes, and what's next** — especially on the
days the normal times are wrong (Late Arrival, finals, assemblies, e-learning days).

## Architecture

```text
Packages/ScheduleKit/          Schedule logic and shared presentation helpers.
  Sources/ScheduleKit/
    Models/                    PeriodID, DayKey, Block, BellSchedule, UserConfig, DayTimeline…
    Catalog/                   Bundled bell tables + school-year boundaries
    Parsing/                   schedule-dates.json and lunch-manifest parsers
    Resolution/                resolveDay(...) priority chain + momentState(at:)
    Sync/                      Schedule (ETag) and lunch fetches, last-good cache semantics
    Storage/                   App Group store + read-only widget snapshot + Keychain SecretStore
    Presentation/              Shared role colors, emoji, and time formatting
    Widgets/                   Pure seven-day timeline planner
    Notifications/             Pure NotificationPlanner (56 alerts + 1 refresh reminder)
    Resources/                 bell-schedules.json, lunch-menu.json
  Tests/ScheduleKitTests/      The quality gate — run with `swift test`
Packages/StudentIDKit/         Student ID logic — no UI.
  Sources/StudentIDKit/
    Code39.swift               Encoder; Code39Decoder is the reader
    Code39Layout.swift         Pixel-snapped sizing so bars stay scannable
    StudentIDExtractor.swift   Screenshot → barcode, name, grade, year, photo
    StudentIDCard.swift        The model; its initializer is internal by design
    StudentIDPhotoStore.swift  The cropped headshot, on disk with complete file protection
  Tests/StudentIDKitTests/     Includes a Vision round-trip on rendered symbols
Stevenson Space Companion App/ SwiftUI app target: Home, Lunch, ID, Settings
ScheduleWidgets/              Schedule widgets and small/large lunch widgets
```

Two pure functions are the heart of everything; the app and widgets must go through them so all surfaces agree:

```swift
resolveDay(day, inputs:)          // date → personalized DayTimeline
momentState(at: now, in: timeline) // instant → what's happening right now
```

**Resolution priority:** manual override → remote JSON map → outside-school-year
(never defaults to Standard) → bundled break ranges → weekend → Standard weekday
(by design, not a guess). All date math in `America/Chicago` via calendar
components — never `+24h` arithmetic (DST-safe).

## The Home tab

Home shows today's timeline with a countdown card that stays pinned while the
schedule scrolls. The day picker steps a day at a time or jumps to any date in
the school years the catalog knows, so students can check tomorrow's (or next
week's) schedule before it arrives.

## Schedule widgets

Small and medium Home Screen widgets plus a rectangular Lock Screen widget show
bounded system countdowns, personalized periods, passing, and the next school day.
They read the app's last successful cache through the App Group; no additional
networking is required. See [widget behavior and validation](docs/schedule-widgets.md).

## The Lunch tab

A week strip (Monday–Friday) over the menu for the chosen day. It opens on the
first day from today that has a menu, so on a weekend it opens on Monday.

The website publishes the menu as six station files (`comfort`, `international`,
`mindful`, `sides`, `soup`, `special`) with no combined manifest, so the app
fetches all six and assembles one itself. The rotation metadata the website
doesn't publish — `validFrom`, `validTo`, `semesterSwitch`, `offset` — comes from
the bundled `lunch-menu.json`. The rotation length is read from the data rather
than hardcoded, and every station must agree on it. One failed or invalid station
fails the whole refresh, and the last good menu stays.

The configurable small **Lunch Category** widget shows one station; the large
**Today’s Lunch** widget shows all six categories. Both share the app’s menu
cache and serving-day rules. See [lunch widget behavior](docs/lunch-widgets.md).

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

The source screenshot is never stored — only the extracted fields and the
cropped photo. The fields live in the Keychain (`sk.studentID`,
`WhenUnlockedThisDeviceOnly`: not in backups, unreadable while locked), and the
photo is a file in Application Support with complete file protection. Older
builds kept the card in `UserDefaults`; `SharedStore` moves it to the Keychain on
launch and deletes the plaintext copies only once the Keychain write succeeds.

## Data sources and the yearly update runbook

1. **Bell tables** (`Packages/ScheduleKit/Sources/ScheduleKit/Resources/bell-schedules.json`)
   — bundled, ship with the app. If the school changes bell times, edit this file
   and ship an update. The test suite validates ordering, A/B tiling, and both
   Early Dismissal rotations on every run.

2. **School-year boundaries** (`Packages/ScheduleKit/Sources/ScheduleKit/Models/SchoolYear.swift` →
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

4. **Lunch menu** — the six station files under
   `https://raw.githubusercontent.com/stevenson-space/shs/main/src/data/lunch-rotating/`,
   refetched on the same 1 h throttle. **Each year, update the bundled
   `Packages/ScheduleKit/Sources/ScheduleKit/Resources/lunch-menu.json`**:
   `validFrom`/`validTo` (the menu's date range), `semesterSwitch` (when the
   `special` station moves to its second semester), and `offset` (which rotation
   week `validFrom` falls in). Outside that range the Lunch tab shows no menu.

The app only fetches from `raw.githubusercontent.com` (`SharedStore.allowedHosts`),
redirects included.

## Development

- Logic tests (fast, no simulator): `swift test --package-path Packages/ScheduleKit`
  and `swift test --package-path Packages/StudentIDKit`
- App build: `xcodebuild -scheme "Stevenson Space Companion App" -destination 'generic/platform=iOS Simulator' build`
- **Time travel**: DEBUG builds have a Developer section in Settings — jump the
  app clock to any instant or use one-tap scenarios (finals rotations, async
  days, breaks…). A purple banner shows whenever the clock is shifted.
- Pending-notification inspector: Settings → Developer — Notifications.

## Deferred (architecture is ready for them)

Live Activities and Dynamic Island remain deferred. Their requirements and the
suspended-transition prerequisite are recorded in [the widget notes](docs/schedule-widgets.md).
BGAppRefresh and the ICS hint layer are also deferred.
