# Schedule widgets

One iOS 18+ WidgetKit extension supports small and medium Home Screen widgets and
an accessory rectangular Lock Screen widget. Tap any family to select Home and
reset its date to today. Live Activities and Dynamic Island are deferred.

## Data and timing

Both targets use `group.shankar.Stevenson-Space-Companion-App`. Only the app writes
shared preferences, migrates old data, and fetches the remote calendar. On upgrade,
the app imports both the old private suite preferences file and standard defaults,
without replacing newer shared values. A separate readiness key prevents an
uninitialized or inaccessible suite from silently showing a new user's schedule.
Missing configuration and missing remote cache *after initialization* use the same
UserConfig and bundled-calendar fallback as Home. Malformed shared data asks the
user to open the app; unknown schedule names remain unavailable.

The extension calls the static, read-only `SharedStore.readScheduleData()` path.
It reads only readiness, configuration, overrides, and cached calendar keys. It
never constructs `SharedStore`, initializes a SecretStore, reads student ID keys,
or runs migration. It has no StudentIDKit dependency or Keychain sharing entitlement.

`WidgetTimelinePlanner` calls `resolveDay(..., freePeriodGrouping: .separate)` and
`momentState`, preserving split classes and extended classes while retaining each
free period and its passing gap. Existing callers default to `.combined`.

Entries cover the current instant and boundaries across today plus six more
Chicago calendar dates: midnight, 15 minutes before the actual first bell, every
period start/end, dismissal, and five minutes after dismissal. The refresh policy
requests the next Chicago midnight; later entries remain available if iOS delays
that refresh. Next-school-day lookup skips days without bells (including async)
and searches up to 450 dates, matching the app's search bound. All stepping uses
calendar dates, including across DST.

`Text(timerInterval:countsDown:)` renders countdowns, bounded to zero. There is no
widget timer loop, TimelineView, or per-second reload. The app requests reloads
after configuration/override mutations, successful schedule refreshes, and first
publication after migration/unlock. Widgets respect system appearance/tint and
contrast; schedule colors, emoji, and 12/24-hour formatting share the app's helpers.

Apple controls update cadence and can delay both rendering and timeline switches.
A cache only changes when the main app refreshes it. No widget networking or new
backend is introduced.

The off-day Patriot image is prepared once as a thumbnail bounded to 330 × 330
before being passed to SwiftUI (110 points at 3×). Using only `.resizable()` and
`.frame` would leave the original 1307 × 1687 bitmap in the widget archive,
risking an archival failure that keeps the previous timeline visible. Shared
schedule read failures are logged in the extension's `Timeline` category before
returning the existing open-app fallback and 15-minute retry.

## Validation

### Debug time travel

In Debug builds, Settings → Developer — Time Travel and Developer — Scenarios
also update widgets. The simulated clock offset is shared through the App Group,
and each clock change requests a widget reload. Schedule labels and bell times
use the simulated date; timeline delivery dates, reload requests, and countdown
intervals are translated back to real time so transitions continue while the
app is suspended. iOS still controls when a requested reload is delivered.

“Back to real time,” tapping a widget, or relaunching the app resets both clocks.
Scenario overrides remain until “Clear demo overrides” removes them, matching
the existing app behavior. Release builds neither read nor apply the debug clock.

### Checks

Automated coverage lives in `WidgetTimelineTests`, `WidgetDebugClockTests`, and `WidgetStorageTests`, alongside
existing resolver, notification, personalization, storage, and sync tests:

```sh
swift test --package-path Packages/ScheduleKit
xcodebuild -project 'Stevenson Space Companion App.xcodeproj' \
  -scheme 'Stevenson Space Companion App' \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

The widget view provides previews for all three families, lead-in, passing,
completion, long names, missing rooms, custom emoji, and larger text. In Xcode,
use appearance, text size, and widget rendering variants to inspect light, dark,
accented, and vibrant modes.

Implementation validation (September 18, 2026):

- 218 ScheduleKit tests pass, including all pre-existing tests.
- The app and embedded extension build for the iOS Simulator and signed Debug
  and Release iOS device destinations. Both signed targets carry the existing App Group entitlement.
- The app launches on the iOS 18.6 simulator. Opening the widget URL selects Home
  from Settings and resets a previously selected tomorrow date to today.
- Xcode preview rendering timed out on iOS 27 and iOS 18.6 destinations. The iOS
  18.6 simulator's widget gallery was blank, including system widgets. Layouts,
  tinted variants, and actual widget rendering therefore remain unverified.
- The physical iPhone listed as a build destination was not available to the
  device interaction service. Actual seconds rendering and transitions while
  suspended still require a device session outside the debugger; build/test
  success does not establish that behavior.

Before release, validate on a signed device **without the debugger attached**:

- Upgrade an existing install; verify names, rooms, emoji, 12/24-hour preference,
  overrides, cached calendar, and student ID still work. Open the app once.
- Add small, medium, and rectangular widgets. Test light/dark/tinted appearance,
  increased contrast, large text, and VoiceOver. Check long names and absent rooms.
- Leave the app suspended across a period end, passing, and the next period start;
  confirm timer text counts down and stops at zero if a transition is delayed.
- Check the real first bell minus 15 minutes, dismissal, and five minutes later.
  Observe a late-arrival or other special day, consecutive free periods, and a
  zero-gap finals/makeup transition when available.
- Edit configuration/overrides and refresh the calendar in the app; verify widgets
  pick up the data. Test taps from every family while Home is showing another date
  and while a different tab is selected.
- Check Lock Screen behavior after a restart, before and after first unlock, and
  check date rollover while traveling outside the school time zone.

Refresh and debug-clock validation (September 19, 2026): all 223 Debug ScheduleKit
tests pass, and the app plus embedded widget extension build in both Debug and
Release for the simulator. On-device refresh remains unverified: the connected iPhone was
locked and Xcode's widget preview timed out. For the rendering regression, check
both small and medium widgets on a weekend, then set and remove a bell-schedule
override for today; verify the off-day logo and schedule replace each other.

## Deferred Live Activity requirements

Future work must retain app-open initiation, the actual first bell's 15-minute
lead-in, separate free periods, no activity on days without school, and a five-minute
finished state. Resolve automatic transitions while the app is suspended before
planning implementation. No ActivityKit or Dynamic Island UI ships in this version.

## Apple references

- [Keeping a widget up to date](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date)
- [Creating a widget extension](https://developer.apple.com/documentation/widgetkit/creating-a-widget-extension)
- [Bounded timer text](https://developer.apple.com/documentation/swiftui/text/init(timerinterval:pausetime:countsdown:showshours:))
- [Configuring App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups)
- [Preparing image thumbnails](https://developer.apple.com/documentation/uikit/uiimage/preparingthumbnail(of:))
