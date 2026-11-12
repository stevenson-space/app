# Stevenson Space

iOS bell-schedule app for Adlai E. Stevenson High School (D125). One glance answers:
**what period is it, how long until it changes, and what's next** — especially on the
days the normal times are wrong (Late Arrival, finals, assemblies, e-learning days).

Developed by [Shankar Krishnamurthy](https://github.com/ShankarK2009)
 and [Rishabh Sinha](https://github.com/RishabhSinha2009).

Stevenson Space is an independent app. It is not affiliated with or endorsed by
Adlai E. Stevenson High School.

The full app name and App Store listing name are **Stevenson Space**. The Home
Screen icon uses **SHS Space**. Set the **Name** field in App Store Connect to
`Stevenson Space`; it is separate from the installed app's display name.
[App Store name](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information/),
[Home Screen display name](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundledisplayname).

The bundle identifiers, App Group, Keychain service, and `stevenson-space` URL
scheme retain their existing values so the name change preserves app identity
and access to saved data. The target rename did change the Swift module name
(`Stevenson_Space_Companion_App` → `Stevenson_Space`) and the executable name.
Nothing persisted depends on either today; keep it that way, or pin
`PRODUCT_MODULE_NAME`, before storing module-qualified type names such as
`NSKeyedArchiver` class names.

## Architecture

```text
Packages/ScheduleKit/          Schedule logic and shared presentation helpers.
  Sources/ScheduleKit/
    Models/                    PeriodID, DayKey, Block, BellSchedule, UserConfig, DayTimeline…
    Catalog/                   Bundled bell tables + school-year boundaries
    Parsing/                   Day-type map and lunch menu parsers for the website API
    Resolution/                resolveDay(...) priority chain + momentState(at:)
    Sync/                      Day-type map and lunch fetches (ETag), last-good cache semantics
    Storage/                   App Group store + read-only widget snapshot + Keychain SecretStore
    Presentation/              Shared role colors, emoji, and time formatting
    Widgets/                   Pure seven-day timeline planner
    Notifications/             Pure NotificationPlanner (56 alerts + 1 refresh reminder)
    Resources/                 bell-schedules.json
  Tests/ScheduleKitTests/      The quality gate — run with `swift test`
Packages/StudentIDKit/         Student ID logic — no UI.
  Sources/StudentIDKit/
    Code39.swift               Encoder; Code39Decoder is the reader
    Code39Layout.swift         Pixel-snapped sizing so bars stay scannable
    StudentIDExtractor.swift   Screenshot → barcode, name, grade, year, photo
    StudentIDCard.swift        The model; its initializer is internal by design
    StudentIDPhotoStore.swift  The cropped headshot, on disk with complete file protection
  Tests/StudentIDKitTests/     Includes a Vision round-trip on rendered symbols
Stevenson Space/               SwiftUI app target: Home, Lunch, ID, Settings
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

Small and medium Home Screen widgets plus circular and rectangular Lock Screen
widgets show bounded system countdowns, personalized periods, passing, and the next
school day.
They read the app's last successful cache through the App Group; no additional
networking is required. See [widget behavior and validation](docs/schedule-widgets.md).

## The Lunch tab

A week strip (Monday–Friday) over the menu for the chosen day. It opens on the
first day from today that has a menu, so on a weekend it opens on Monday.

The menus come from the website's API (`/api/v1/lunch.json`), which publishes one
menu per school day in a rolling window: a week behind the day the site was built
and three weeks ahead. The website resolves its own rotation, so the app does no
rotation math and carries no rotation dates. It looks each day up, leaves out the
kitchen's placeholder dishes, and applies its own calendar on top, so a student's
overrides still decide whether lunch is served.

No menu ships with the app. Until the first download the tab shows a loading
state, and a retry if the download failed. A response that fails validation never
replaces the last good menus, and days beyond the published window have no menu
until a later refresh brings them in.

The **Lunch Menu** widget offers a configurable small size for one station and
a large size showing all six categories. Both sizes share the app’s menu
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
`WhenUnlockedThisDeviceOnly`: unreadable while locked and not migrated to another
device when restoring a backup, but restorable to the same device), and the
photo is a file in Application Support with complete file protection. The photo
is not excluded from Apple device backups and may be backed up depending on the
user’s settings; file protection does not prevent backup. See the
[privacy policy](docs/privacy-policy.md) for the user-facing explanation. Older
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

3. **Day-type map** — live from the website's API:
   `https://stevenson.space/api/v1/schedule-dates.json`. The website's build
   generates the API (`ingest/api.ts` in `stevenson-space/shs`) from the same
   `schedule-dates.json` the website reads, and serves the map under
   `scheduleDates` inside an envelope of build metadata. It lists
   only exceptions (`Late Arrival`, `Activity Period`, `PM Assembly`,
   `Early Dismissal`, `No School`, `Asynchronous`); unlisted in-session weekdays
   are Standard. Ranges use `"12/17/2026-12/18/2026"`. A weekend inside a range
   stays a weekend unless the range is `No School`; to schedule a weekend, list
   that date on its own. Early Dismissal rotation
   is inferred from position within a range (1st school-weekday → periods
   6·2·3·4, 2nd → 5·1·7·8). The app refetches with ETag on launch/foreground
   (throttled to 1 h after a successful check, 5 min after a failed one) and
   always keeps the last good copy if a fetch or parse fails.
   The site is rebuilt nightly, which restamps the file; a refresh counts as a
   change only when the dates differ.

4. **Lunch menu** — live from `https://stevenson.space/api/v1/lunch.json`,
   refetched with ETag on the same throttle (which applies only while there
   is a menu to show). **Nothing in the app needs a yearly update**: the
   rotation, its date range, and the semester switch live in the website
   (`src/data/lunch-rotating/` and `src/utils/food/rotating-map.ts`), and the
   API serves the resolved days. The window slides forward with each nightly
   build, so the cache holds about three weeks of menus from the last time the
   app was opened. Past that, the Lunch tab and widget report the menu as
   unavailable until the next refresh.

The app only fetches from `stevenson.space` (`SharedStore.allowedHosts`),
redirects included. The API's `signature.json` and `schedules.json` are not
used: each feed is already one small conditional request, and the bell tables
stay bundled (item 1).

Home and Lunch stay quiet about data freshness until their respective feed has
gone two days without a successful update check. A successful check clears
the reminder even when the data is unchanged. Installs that have never synced
get the same grace period from their first attempt; failed retries do not reset
it. Reminders offer **Check for Updates**, which bypasses the usual throttle,
and show a short failure message only after a student requests a check. Automatic
checks keep the reminder hidden while they run. Reminders use the real clock,
independent of the selected date or DEBUG time travel, and update at the two-day
deadline. Future timestamps cannot suppress a reminder after a clock correction.

## Development

- Logic tests (fast, no simulator): `swift test --package-path Packages/ScheduleKit`
  and `swift test --package-path Packages/StudentIDKit`
- App build: `xcodebuild -scheme "Stevenson Space" -destination 'generic/platform=iOS Simulator' build`
- **Time travel**: DEBUG builds have a Developer section in Settings — jump the
  app clock to any instant or use one-tap scenarios (finals rotations, async
  days, breaks…). A purple banner shows whenever the clock is shifted.
- Pending-notification inspector: Settings → Developer — Notifications.

## Shortcuts and Siri

Eight actions open the student ID scanner or a selected tab, and return the
current class/period, next class, schedule, schedule type, and lunch menu.
Class results expose names, periods, saved rooms, and times to subsequent
Shortcuts actions. See [implementation, Apple references, and validation](docs/app-intents.md).

## Deferred (architecture is ready for them)

Live Activities and Dynamic Island remain deferred. Their requirements and the
suspended-transition prerequisite are recorded in [the widget notes](docs/schedule-widgets.md).
BGAppRefresh and the ICS hint layer are also deferred.
