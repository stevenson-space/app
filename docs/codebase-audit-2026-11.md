# Codebase Audit — November 2026

Scope: the whole repository at `main` `025acba` (version 1.1.0, build 3) —
`Packages/ScheduleKit`, `Packages/StudentIDKit`, the `Stevenson Space` app
target, the `ScheduleWidgets` extension, project configuration, privacy
manifests, and documentation.

This report is the plan for, and the record of, the
`audit/reliability-and-test-hardening` branch. Each finding states whether it
was fixed on that branch or only documented.

| Commit | Change |
|--------|--------|
| `73b9243` | This report |
| `8deadba` | Weekends inside multi-day ranges stay weekends (finding 1) |
| `af21c63` | Schedule sync retries a 304 at most once (finding 2) |
| `64bed8e` | Shared day labels use the school calendar (finding 3) |
| `ddff239` | Tests for subject-emoji matching (finding 5) |
| `e477540` | Subject-emoji rule table is built once (finding 5) |
| `badb983` | The Lunch tab rolls over at midnight (finding 4) |
| `6764fc2` | Corrected photo-storage comment (finding 6) |
| `0cce50b` | A weekend listed on its own beats a No School range (finding 1) |
| `03d1a07` | Any 304 to an unconditional request fails (finding 2) |
| `1fbf234` | A weekend inside a summer session stays a weekend (finding 1) |
| `360065f` | A Lunch selection pinned to the previous today follows the new day (finding 4) |

## How the app is built

- **Languages and frameworks.** Swift and SwiftUI throughout, iOS 18+. The app
  target builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and
  approachable concurrency. The two packages use Swift 5 language mode and do
  not default to MainActor isolation. `StudentIDExtractor`'s Vision pipeline is
  nonisolated, and `ScheduleSyncService` and `LunchMenuSyncService` are
  ordinary actors, so that work runs off the main actor.
- **Architecture.** All logic lives in two packages that run without UI.
  `ScheduleKit` holds the bell tables, `resolveDay` / `momentState`, sync,
  storage, notification planning, and widget timeline planning.
  `StudentIDKit` holds Code 39 encode/decode, screenshot extraction, and the
  card model. The app and the widgets only arrange their output.
- **State and data flow.** One `@Observable @MainActor AppModel` owns the
  resolver inputs, persists every change through `SharedStore` (an App Group
  `UserDefaults` suite), and derives today's timeline, the moment state, and
  the next school day. A 1 Hz heartbeat in `RootView` moves state across bell
  boundaries.
- **Networking.** Two actors, `ScheduleSyncService` (ETag) and
  `LunchMenuSyncService` (the lunch API, ETag). They are throttled to one check
  an hour, coalesced through `SyncQueue`, and only commit a payload once it
  parses. Requests go to an allow-listed host, redirects included.
- **Persistence.** The schedule, overrides, preferences, and caches are in the
  App Group suite. The student ID fields are in the Keychain
  (`WhenUnlockedThisDeviceOnly`). The cropped photo is a file with complete
  protection in the app's own container.
- **Extensions.** WidgetKit schedule and lunch widgets, and App Intents
  (Siri/Shortcuts). They read a read-only snapshot through
  `SharedStore.readScheduleData()` and never touch the student ID.
- **Tests.** Swift Testing suites in both packages (about 4,700 lines),
  run with `swift test` on macOS. There is no CI workflow.

Overall the codebase is in good shape. It is carefully documented, its
invariants are explicit, and the hard parts (DST-safe date math, last-good
caching, keychain migration ordering, notification budgeting, decode bounds
for untrusted images) are tested well. **No Critical or High severity issues
were found.** The findings below are Medium and Low.

## Findings

Severity: **Critical**: data loss, security breach, or crash for most users.
**High**: wrong answer or broken feature for many users. **Medium**: wrong
answer or broken feature under realistic but uncommon conditions. **Low**:
minor or rare impact, maintainability, or performance.

Kind: **Bug** = confirmed by reading the code paths (and covered by a new
regression test where it is fixed); **Potential** = depends on external
conditions; **Improvement** = optional quality work.

| # | Severity | Kind | Area | Status |
|---|----------|------|------|--------|
| 1 | Medium | Bug | Weekends inside multi-day calendar ranges resolve as school days | Fixed in `8deadba`, `0cce50b`, `1fbf234` |
| 2 | Medium | Potential | Schedule sync retries a 304 without end when no cached copy exists | Fixed in `af21c63`, `03d1a07` |
| 3 | Low | Bug | Shared day labels use the device's calendar, not the school's | Fixed in `64bed8e` |
| 4 | Low | Bug | Lunch tab's "today" is not observable, so it can go stale after midnight | Fixed in `badb983`, `360065f` |
| 5 | Low | Improvement | Subject-emoji rule table is rebuilt on every call, and has no tests | Fixed in `ddff239`, `e477540` |
| 6 | Low | Bug (docs) | Photo-store comment recommends moving the ID photo into the App Group | Fixed in `6764fc2` |
| 7 | Medium | Bug (UX) | "Rotation unverified — tap to fix" cannot be fixed in release builds | Documented |
| 8 | Low | Improvement | Past overrides are never pruned | Documented |
| 9 | Low | Improvement | The ID photo is rewritten on every launch | Documented |
| 10 | Low | Potential | ID import reads the whole picked file into memory before size checks | Documented |
| 11 | Low | Improvement | Two copies of the bounded response-body reader | Documented |
| 12 | Low | Improvement | No CI runs the test suites | Documented |

### 1. Weekends inside multi-day calendar ranges resolve as school days — Medium, Bug

**Where.** `Packages/ScheduleKit/Sources/ScheduleKit/Parsing/ScheduleDatesParser.swift`
(`DayTypeMap.match(_:)`), consumed by step 2 of `resolveDay` in
`Resolution/DayResolver.swift`.

**What.** A remote-map entry beats the weekend check. That is right for a
weekend listed as its own date, such as a Saturday event. It is wrong for a
weekend that only falls between the two ends of a range. The suite already
expects ranges that cross a weekend: `rangeCrossingAWeekendCountsSchoolDaysOnly`
uses a Friday–Monday finals range and skips the weekend when counting
rotations. The weekend days themselves still resolved as *Early Dismissal ·
Finals Day 1*, with bells and an "unverified rotation" badge.

**Why it matters.** Every surface reads `resolveDay`. On that Saturday and
Sunday, Home showed a finals bell schedule, end-of-period and morning
notifications were scheduled, widgets counted down, and Siri answered with
classes. The same applies to Late Arrival, Summer School, Asynchronous (which
sends a morning alert), and unknown event ranges.

**Fix.** On a weekend, `match` ignores entries whose *multi-day* span merely
covers the date. Single-date entries still win, so `mapWinsOverWeekend` holds.
No School ranges still apply, because either reading means no school and that
keeps today's labels for breaks such as Memorial Day weekend. A weekend date
listed on its own still outranks a No School range around it. A weekend
inside a range that falls outside every bundled school year, such as a summer
session, resolves as a weekend rather than Summer Break.

**Risk.** This changes how ranges are read for weekend dates. If the school
ever means a weekend inside a range to be a school day, it has to list that
date on its own, as the website data already does for single events.
Maintainers should confirm that reading.

### 2. Schedule sync retries a 304 without end when no cached copy exists — Medium, Potential

**Where.** `Packages/ScheduleKit/Sources/ScheduleKit/Sync/ScheduleSyncService.swift`,
the `case 304` branch of `refresh(force:now:)`.

**What.** When a 304 arrives and the cache is empty, the service drops the
ETag and calls itself again. Nothing limits that to one retry. A server,
proxy, or captive portal that answers 304 to an *unconditional* request (on a
fresh install there is no ETag and no cache) makes the service request again
indefinitely. Each attempt goes over the network and nests another async
frame.

**Why it matters.** The refresh never returns, so `SyncQueue` never finishes.
The "Checking…" state never clears, and every later forced check queues behind
it for the rest of the session, which blocks schedule updates. This is the
kind of unreliable network students run into.

**Fix.** Retry in full only when the request that got the 304 was
conditional. A 304 to an unconditional request is recorded as `HTTP 304` and
the last-good cache is left alone. That holds with a cache too, as after a
data-source reset clears the ETag, so the 304 can't record a success and
hide an overdue check. New tests cover the single retry and the
termination.

**Risk.** Low. The happy paths (200, conditional 304 with a cache) are
unchanged and already tested.

### 3. Shared day labels use the device's calendar — Low, Bug

**Where.** `Packages/ScheduleKit/Sources/ScheduleKit/Presentation/TimeDisplay.swift`
(`shortWeekday`, `weekdayMonthDay`, `shortWeekdayMonthDay`).

**What.** These formatters set a fixed pattern and the Chicago time zone but
no calendar, so they format in whatever calendar the student picked in iOS
Settings. For a student using the Islamic, Hebrew, or Persian calendar,
"Wed, Aug 12" comes out as a different month and day. Home's day picker and
the Lunch tab already pin `SchoolTime.calendar`, so the same date showed two
different ways in one session.

**Where it shows.** The next-school-day card, the Settings override list, the
widgets' "back to school" line, and Siri answers ("Lunch for …").

**Fix.** Pin the formatters to `SchoolTime.calendar`. Day and month names
still follow the device language. A test formats with an Islamic-calendar
locale.

**Risk.** Low. The output is unchanged for Gregorian users.

### 4. The Lunch tab's "today" can go stale after midnight — Low, Bug

**Where.** `Stevenson Space/Features/Lunch/LunchMenuView.swift`.

**What.** The view reads `model.today`, which in release builds is computed
from `Date()` and is not an observed property. The week strip's "today" ring,
the preferred serving day, and the Today/Next Lunch button only refresh when
something else re-renders the tab. One example: the tab is left open across
midnight. Another: the app comes back after midnight within the one-hour sync
throttle.

**Fix.** Read `model.todayTimeline.day`, which the heartbeat refreshes and
SwiftUI observes. Home already does this. When today changes, clear a
selection pinned to the previous today so it follows the new preferred lunch
day. Selections of other dates remain unchanged.

**Risk.** Low. It is the same value except for under one second around
midnight. This is an app-target change, so it needs an Xcode build to verify
(see *Verification*).

### 5. Subject-emoji rules are rebuilt on every call — Low, Improvement

**Where.** `Packages/ScheduleKit/Sources/ScheduleKit/Presentation/ScheduleStyle.swift`
(`subjectEmoji`).

**What.** The table of about 60 rules, roughly 180 string arrays, was built
inside the function. It runs for every class card on every list render, every
widget row, and every keystroke in the period-name editor. The matching rules
had no tests at all.

**Fix.** Build the table once as a `static let`. Characterization tests pin
the documented ordering ("Game Programming" before computer science, "Art
History" before history) together with prefix, abbreviation, phrase, and
fallback matching.

**Risk.** None to behavior. The table and the loop are unchanged.

### 6. Photo-store comment recommends moving the ID photo into the App Group — Low, Bug (documentation)

**Where.** `Packages/StudentIDKit/Sources/StudentIDKit/StudentIDPhotoStore.swift`.

**What.** The type's comment says the project has no App Group entitlement,
and that the photo should move into the group container "when widgets
arrive". Widgets and the entitlement both exist, and the privacy policy
(`docs/privacy-policy.md`) says ID details and photos are not provided to
widgets. A maintainer who followed the comment would break that promise.

**Fix.** Rewrite the comment to state the actual rule: the photo stays out of
the App Group on purpose.

### 7. "Rotation unverified — tap to fix" cannot be fixed in release builds — Medium, Bug (UX), documented

**Where.** `Stevenson Space/Features/Home/HomeHeaderView.swift` (the badge) and
`Stevenson Space/Features/Settings/OverrideEditorView.swift` (`Choice`, `prefill`).

**What.** The Early Dismissal and Summer override choices are DEBUG-only
(merged in pull request 43). In a release build, tapping the badge on an
uncertain finals day opens an editor with no Early Dismissal option. The
editor pre-selects nothing and suggests going back. A student cannot do what
the badge offers.

**When it happens.** A standalone finals date in the map, a third or later
weekday in a finals range, or a malformed range.

**Recommendation.** This is a product decision. Either make the release badge
non-interactive ("Rotation unverified"), or allow choosing a rotation when the
date already resolves to Early Dismissal. It is not implemented here because
the DEBUG restriction was deliberate.

### 8. Past overrides are never pruned — Low, documented

**Where.** `AppModel.setOverride` / `SharedStore.overrides`, listed in
`SettingsView.overrideSection`.

**What.** Overrides are keyed to a date and stop mattering once it passes,
but they stay in storage and in the Settings list indefinitely.

**Recommendation.** Drop overrides before today's date on launch, or hide
them in Settings. This is a visible behavior change, so it is left for the
maintainers.

### 9. The ID photo is rewritten on every launch — Low, documented

**Where.** `StudentIDPhotoStore.reapplyProtectionIfPresent()`, called from
`AppModel.init`.

**What.** It upgrades photos saved by older builds to complete file
protection by rewriting the file. That happens on every launch, synchronously
on the main thread.

**Recommendation.** Read `FileAttributeKey.protectionKey` and rewrite only
when the file is not already `.complete`. It is not implemented because file
protection can only be checked on a device.

### 10. ID import reads the whole picked file into memory before size checks — Low, Potential, documented

**Where.** `StudentIDView.load(_:)`:
`item.loadTransferable(type: Data.self)`.

**What.** The extractor rejects files over 40 MB and decodes through a bounded
thumbnail. However, the picker hands over the entire file first, so picking a
very large image (a long panorama, for example) briefly holds all of it in
memory.

**Recommendation.** Import through a `FileRepresentation` and check the file
size before reading it. This needs device testing, so it is not implemented
here.

### 11. Two copies of the bounded response-body reader — Low, documented

**Where.** `ScheduleSyncService.collectBody` (appends one byte at a time) and
`LunchMenuSyncService.collectBody` (16 KB chunks).

**Recommendation.** Share one chunked helper that takes the error to throw.
It is not done here, because a networking refactor should be checked by
running the suites (see *Verification*).

### 12. No CI runs the test suites — Low, documented

`swift test` only runs on macOS, and nothing runs it on pull requests. A
small workflow would catch regressions like the ones fixed here:

```yaml
# .github/workflows/tests.yml
name: Tests
on: [pull_request]
jobs:
  packages:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - run: swift test --package-path Packages/ScheduleKit
      - run: swift test --package-path Packages/StudentIDKit
```

## Reviewed with no issues found

- **Date and time.** All schedule math uses `SchoolTime.calendar` (Gregorian,
  `America/Chicago`) through wall-clock components. Day stepping uses
  calendar arithmetic, and bell instants are materialized per day, so DST
  transitions cannot shift bells. Intervals are half-open, and zero-length
  gaps produce no passing state.
- **Sync.** Payloads are parsed before they are committed (last-good cache).
  Bodies are size-bounded while streaming. ETag invalidation is
  generation-guarded. Throttling ignores attempts stamped in the future.
  Forced checks run in order.
- **Network security.** HTTPS only, a host allow-list that also applies to
  redirects, no embedded credentials, and no custom URL setter left.
- **Student ID.** The Keychain item is device-only and unavailable while
  locked. The migration deletes plaintext copies only after the Keychain
  write succeeds. Locked and missing reads are told apart, so the orphan
  cleanup cannot delete a locked photo. Stored cards are re-validated. Image
  decode is bounded by bytes, by pixels, and through the thumbnail path.
- **Notifications.** A pure planner with a 56 + 1 budget. Reschedule passes
  are serialized, and a plan-hash short-circuit avoids redundant work.
- **Widgets and intents.** A read-only snapshot with no migrations, no
  secrets, and no networking. Timelines are bounded with no per-second
  entries. A placeholder entry appears when the data is not ready.
- **Main thread.** The UI is driven by a 1 Hz state lookup that only writes
  on change. Vision work runs off the main actor.

## Verification

The original audit ran in a Linux container without Xcode, an iOS Simulator,
or a usable Swift toolchain. Nothing was compiled or run during that audit.
Every change was checked by reading the affected code paths and the existing
tests, and the new tests followed the suites' existing conventions.

These checks did run:

- The weekday of every date the new tests rely on was confirmed with `date`.
- Every new subject-emoji expectation was replayed through a Python copy of
  the matching loop that reads the rule table straight from
  `ScheduleStyle.swift`. All matched.
- The rule table parses to the same 60 rules before and after the move to a
  `static let`.
- Brackets, braces, and parentheses balance in every changed Swift file.

Follow-up validation on November 9, 2026: the app built successfully in Xcode
27.2 for the iPhone 18 Pro simulator, and all 293 ScheduleKit tests passed.
Every commit cited in this report was verified as an ancestor of the branch
head. The manual rollover check below was not performed in this follow-up.

Before merging, on a Mac:

1. `swift test --package-path Packages/ScheduleKit`. Expect the new tests in
   `ResolutionChainTests`, `ScheduleDatesParserTests`, `SyncServiceTests`,
   `TimeDisplayTests`, and `SubjectEmojiTests` to pass alongside the existing
   suite.
2. `swift test --package-path Packages/StudentIDKit`. That package only had a
   comment change.
3. `xcodebuild -scheme "Stevenson Space" -destination 'generic/platform=iOS Simulator' build`.
4. Manual regression check for finding 4: in a DEBUG build, open Lunch from
   its widget or select today in the week strip, then use time travel to
   jump across midnight. The "today" ring and preferred lunch day should
   advance. Repeat with a different date selected; that selection should
   stay unchanged. Also check foregrounding after a date change. (The
   original unobserved-clock issue only shows in Release builds.)
