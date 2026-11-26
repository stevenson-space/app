# Shortcuts, Siri, and controls

## Implementation and Apple documentation

The app exposes eight `AppIntent` actions and eight ready-to-use App Shortcuts.
They live in the main app target's `Intents` directory; a separate extension
is unnecessary for these small read-only actions and foreground navigation.
The existing iOS 18 minimum stays unchanged. Three [controls](#controls) reuse
the same navigation from Control Center, the Lock Screen, and the Action button.

Apple's [App Intents guide](https://developer.apple.com/documentation/appintents/creating-your-first-app-intent)
and [AppShortcutsProvider documentation](https://developer.apple.com/documentation/appintents/appshortcutsprovider)
describe this integration. Xcode extracts action metadata and trains shortcut
phrases at build time. The app registers its shared `AppModel` with
[`AppDependencyManager`](https://developer.apple.com/documentation/appintents/appdependencymanager)
and refreshes shortcut parameters during initialization.

### Student ID and navigation

**Show Student ID** opens the existing full-screen scanning presentation. That
screen supplies a sharp Code 39 barcode, the ID number, maximum brightness, and
an awake screen. Dismissing or backgrounding it restores display settings.
An inline Siri preview cannot provide the same controlled scanning experience.
With no saved ID, the action opens the ID tab and explains how to import one.

The action requires authentication, using
[`IntentAuthenticationPolicy`](https://developer.apple.com/documentation/appintents/intentauthenticationpolicy).
The ID stays in the existing protected storage; the intent doesn't return the
number, speak it, or index identity in Spotlight.

**Open Tab** takes an `AppEnum` (Home, Lunch, ID, Settings). It selects the existing
tab and resets Home/Lunch to today using the same behavior as widget navigation.
Opening the ID tab and opening the scanner remain separate useful actions.

Navigation uses the shared `AppModel` through `@AppDependency` to route each
request to one foreground window. Each root owns its `SceneNavigation` state,
including scanner presentation, dismissal, selected tab, and today requests.
Other windows' sheets don't block that window's scanner. A cold-launch request
waits for a foreground root to attach, even before the ID tab is constructed.
This follows Apple's [window state guidance](https://developer.apple.com/documentation/swiftui/windowgroup). Foreground execution uses
[`supportedModes`](https://developer.apple.com/documentation/appintents/appintent/supportedmodes)
on iOS 26+, with `openAppWhenRun` for iOS 18–25 compatibility.

### Information actions

| Action | Shortcuts output | Behavior |
| --- | --- | --- |
| Get Current Class | Optional Schedule Block | Academic class happening now; excludes lunch, free time, advisory, and events. |
| Get Current Period | Optional Schedule Block | Actual timed block, including lunch/advisory/free periods. No block during passing time. |
| Get Next Class | Optional Schedule Block | Next academic class starting **today**, skipping non-class blocks. No value after the last class. |
| Get Schedule | List of Schedule Blocks | All blocks for the supplied date, or today. Includes lunch, free time, and events. |
| Get Schedule Type | Text | Schedule label for the supplied date, or today, including non-school day labels. |
| Get Lunch Menu | Optional text | Six named stations for the supplied date, or today. No value when lunch isn't served or data is unavailable. |

Schedule Block exposes **Name, Period, Room, Start Time, End Time**. Room is absent
when none was entered. Period is text to preserve split/merged labels like `4B`
and `2–3A`. Dates are native Shortcuts date values. Use a result's Room field for
a room-only workflow, or repeat over Get Schedule to retrieve every class room.

These are [`TransientAppEntity`](https://developer.apple.com/documentation/appintents/transientappentity)
results: a snapshot of this invocation, not a persistent catalog of classes.
They avoid making yesterday's resolved schedule a searchable source of truth.
`ReturnsValue` supports subsequent Shortcuts actions, while `ProvidesDialog`
supplies spoken answers. Schedule and lunch also provide visual snippets.

All queries read the same saved inputs as widgets and call ScheduleKit's
`resolveDay` and `momentState`. Queries don't instantiate another UI model or
fetch network data. Open the app to refresh the calendar/menu; offline requests
use the last saved calendar, with the same bundled fallbacks as the app.
Unknown schedule types report that the schedule is unavailable; empty results
do not imply that classes or lunch are confirmed absent.
Unavailable shared storage produces an actionable error instead of silently
returning a default student configuration. Lunch uses the app's serving-day
rules and the menus the website has published, rather than silently substituting
the next menu day. It has no bundled fallback: before the first download, or for
a date outside the published window, the menu is reported as unavailable.

In DEBUG builds, current/next queries and queries with no supplied date use the
developer time-travel clock shared with widgets. Explicit dates are used as
supplied. Release builds always use the real invocation time and ignore saved
debug offsets. All day selection and spoken bell times use **America/Chicago**. Manual
overrides, split classes, custom names, rooms, and finals ordering come from the
existing resolver. Current period uses physical blocks because the display can
merge multiple free periods into one span.

## Controls

Three controls put the most common actions in Control Center, on the Lock
Screen, and on the Action button, so students don't have to build a shortcut:

| Control | Opens |
| --- | --- |
| Student ID | The full-screen scanner, or ID setup with no saved ID. Same route as Show Student ID. |
| Schedule | Home at today. Same route as Open Tab › Home. |
| Lunch Menu | Lunch at today. Same route as Open Tab › Lunch. |

Like Show Student ID, the Student ID control leaves an open sheet or picker in
place so unfinished edits survive. Siri and Shortcuts read out the intent's
“close the open sheet” error; the control shows the same message as an alert
over that sheet.

They appear under **SHS Space** in the controls gallery: in Control Center, tap
**+** and then **Add a Control**; on the Lock Screen, customize it and replace
one of the bottom controls; for the Action button, pick **Controls** in
Settings › Action Button.

Apple's [controls guide](https://developer.apple.com/documentation/widgetkit/creating-controls-to-perform-actions-across-the-system)
describes this setup. `ScheduleWidgets/StevensonControls.swift` declares each
control as a [`StaticControlConfiguration`](https://developer.apple.com/documentation/widgetkit/staticcontrolconfiguration)
with a [`ControlWidgetButton`](https://developer.apple.com/documentation/widgetkit/controlwidgetbutton).
The widget bundle lists them after the widgets; that order is also their order
in the gallery. They are stateless buttons, so they need no value provider and
never reload.

Each button runs `OpenControlScreenIntent`
(`Stevenson Space/Intents/ControlIntents.swift`), an
[`OpenIntent`](https://developer.apple.com/documentation/appintents/openintent).
The system brings the app forward and runs `perform()` there, which only works
when the intent belongs to both the app and the widget extension. The project
adds the file to the widget target with a membership exception on the
synchronized **Stevenson Space** folder. The widget target defines
`WIDGET_EXTENSION`, so the extension's copy compiles without `AppModel` and
never navigates.

- [`isDiscoverable`](https://developer.apple.com/documentation/appintents/appintent/isdiscoverable)
  is `false`, keeping the intent out of Shortcuts and Siri, which already offer
  Show Student ID and Open Tab.
- `authenticationPolicy` is `.requiresAuthentication`, as for Show Student ID.
- The Lock Screen shows only the symbol, so each one names its screen:
  `person.text.rectangle` (an ID card, as on the ID tab and the Show Student ID
  shortcut), `calendar.badge.clock` (a calendar with a clock, for the bell
  schedule), and `fork.knife` (as on the Lunch tab).
  `controlWidgetActionHint` supplies the Action button's hint, such as
  “Show Student ID”.

## Siri and Siri AI scope

Apple's [Siri AI guide](https://developer.apple.com/documentation/appintents/apple-intelligence-and-siri-ai)
describes App Intents, transferable content, schemas, indexing, and donations.
Its [verification guide](https://developer.apple.com/documentation/appintents/verifying-your-app-intents-implementation)
explicitly supports natural-language invocation through app schemas **or App
Shortcuts**. This implementation uses App Shortcuts for the school-specific
actions. It doesn't claim full personal-context search, onscreen understanding,
or arbitrary cross-app orchestration.

The [predefined schema domains](https://developer.apple.com/documentation/appintents/app-schema-domains)
don't clearly describe student barcode presentation or a personalized bell
schedule. A bell schedule should not pretend to be an editable Calendar event
database solely to attach a schema. Future schema adoption should follow an
actual matching capability. No Foundation Models integration or legacy SiriKit
intent-definition file is needed for this action surface.

The full app name is **Stevenson Space**. The installed display name is
**SHS Space**, which appears under the Home Screen icon. The
`\(.applicationName)` phrase token matches the display name and any app name
synonyms, so `Config/AppInfo.plist` lists **Stevenson Space** under
`INAlternativeAppNames` and either name works in a phrase.
[Bundle display name](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundledisplayname),
[App name synonyms](https://developer.apple.com/documentation/sirikit/specifying-synonyms-for-your-app-name).

Example phrases using the installed app's display name (each also works with
“Stevenson Space”):

- “Show my student ID in SHS Space.”
- “What's my current class in SHS Space?”
- “What period is it in SHS Space?”
- “Where is my next class in SHS Space?”
- “What's for lunch in SHS Space?”
- “Show my schedule in SHS Space.”
- “What's today's schedule type in SHS Space?”
- “Open Lunch in SHS Space.”

Actual Siri phrase recognition depends on device, OS, language, and system
configuration. The maintainer previously confirmed these actions work on a real
device; repeat the checks below with both **SHS Space** and **Stevenson Space**.

## Validation

- The existing 242-test ScheduleKit suite passes. All seven inquiry tests also
  pass after adding coverage for unknown schedules with empty class/lunch results.
  Inquiry coverage includes bell boundaries, passing, lunch/class splits,
  personalization, merged free periods, finals ordering, no-school days, and
  manual overrides.
- Simulator app build with Xcode 27 succeeds, including metadata extraction and
  English phrase training for all eight shortcuts, with no app build warnings.
- The app installed and launched on an iOS 27 simulator.
- Real-device testing is complete and works, as confirmed by the maintainer.
- Controls, on the iOS 27.2 simulator: all three appear under SHS Space in the
  Control Center gallery and open their screens both from a terminated app and
  from another tab. Student ID opened ID setup with no saved ID, and the scanner
  once a test ID was imported; Schedule closed an open scanner and went to Home.
  With Home's calendar sheet open, Student ID showed the “close the open sheet”
  alert over it and left the sheet in place. Running it again with that alert
  up added no second alert; after OK, the next run showed it again.
- Controls, on a device, as confirmed by the maintainer: they work from the
  Lock Screen and the Action button, and a locked device asks to unlock first.

Use these system-level flows for future regression checks on supported iOS versions:

1. Install and open the app once. Find all eight actions in Shortcuts. Run Get
   Schedule, select a result's Room/Start Time, and pass it to another action.
2. Run current class/period during class, lunch, passing, and free time. Run next
   class before school and after the final class. Check finals and overrides.
   In DEBUG, use developer time travel and confirm these answers and undated
   schedule/type/lunch queries match the simulated clock. Explicit dates should
   remain unchanged. Reset time travel and verify queries return to real time;
   verify Release ignores any persisted debug offset.
3. Query lunch on a serving day, weekend, no-school override, and date outside
   menu validity. Query schedule/type on asynchronous and outside-year dates.
   For an unrecognized calendar entry, verify next class, schedule, and lunch
   report unavailable data rather than confirmed absence.
4. Run Show Student ID with a saved ID from a terminated app and from another
   tab, dismiss it, and repeat. Verify missing-ID setup and locked-device
   authentication. Confirm brightness and auto-lock restoration.
   Repeat with two iPad windows: only the target window should present or dismiss
   its scanner, and a sheet in the other window should not block it.
5. Run Open Tab for all four choices, including while the scanner is open.
6. Ask Siri the example phrases and natural variations, once with “SHS Space”
   and once with “Stevenson Space”; check spoken answers
   using AirPods and compare standard Siri with Siri AI on supported devices.
7. Add all three controls to Control Center, the Lock Screen, and the Action
   button. Run each one from a terminated app, from another tab, and on a
   locked device, which should ask to unlock first. Run Student ID with and
   without a saved ID, and with a sheet open, which should show an alert over
   that sheet. Run it again with the alert still up: it should stay one alert.
   Confirm the controls don't appear as Shortcuts actions.
   In the Simulator, the gallery lists newly installed controls only after the
   simulator reboots.
