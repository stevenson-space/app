# Shortcuts and Siri

## Implementation and Apple documentation

The app exposes eight `AppIntent` actions and eight ready-to-use App Shortcuts.
They live in the main app target's `Intents` directory; a separate extension
is unnecessary for these small read-only actions and foreground navigation.
The existing iOS 18 minimum stays unchanged.

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

Navigation uses the scene's actual `AppModel` through `@AppDependency`.
The root scene owns scanner presentation so a cold launch can present it even
when SwiftUI hasn't constructed the ID tab yet. Foreground execution uses
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
Unavailable shared storage produces an actionable error instead of silently
returning a default student configuration. Lunch uses the app's serving-day
and validity-window rules, rather than silently substituting the next menu day.

Current/next queries use the real invocation time, independent of DEBUG time
travel. All day selection and spoken bell times use **America/Chicago**. Manual
overrides, split classes, custom names, rooms, and finals ordering come from the
existing resolver. Current period uses physical blocks because the display can
merge multiple free periods into one span.

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

Example phrases using the current bundle name (the system substitutes the installed app's name):

- “Show my student ID in Stevenson Space Companion App.”
- “What's my current class in Stevenson Space Companion App?”
- “What period is it in Stevenson Space Companion App?”
- “Where is my next class in Stevenson Space Companion App?”
- “What's for lunch in Stevenson Space Companion App?”
- “Show my schedule in Stevenson Space Companion App.”
- “What's today's schedule type in Stevenson Space Companion App?”
- “Open Lunch in Stevenson Space Companion App.”

Actual Siri phrase recognition depends on device, OS, language, and system
configuration. Validate it on a device before release; successful compilation
and metadata extraction alone don't prove voice recognition.

## Validation

- `swift test --package-path Packages/ScheduleKit`: 242 tests pass, including six
  new inquiry tests covering bell boundaries, passing, lunch/class splits,
  personalization, merged free periods, finals ordering, no-school days, and
  manual overrides.
- Simulator app build with Xcode 27 succeeds, including metadata extraction and
  English phrase training for all eight shortcuts, with no app build warnings.
- The app installed and launched on an iOS 27 simulator. Xcode's code-snippet
  runner timed out, so foreground intent execution and end-to-end Shortcuts/Siri
  invocation remain manual verification items.

Before release, exercise these system-level flows on supported iOS versions:

1. Install and open the app once. Find all eight actions in Shortcuts. Run Get
   Schedule, select a result's Room/Start Time, and pass it to another action.
2. Run current class/period during class, lunch, passing, and free time. Run next
   class before school and after the final class. Check finals and overrides.
3. Query lunch on a serving day, weekend, no-school override, and date outside
   menu validity. Query schedule/type on asynchronous and outside-year dates.
4. Run Show Student ID with a saved ID from a terminated app and from another
   tab, dismiss it, and repeat. Verify missing-ID setup and locked-device
   authentication. Confirm brightness and auto-lock restoration.
5. Run Open Tab for all four choices, including while the scanner is open.
6. Ask Siri the example phrases and natural variations; check spoken answers
   using AirPods and compare standard Siri with Siri AI on supported devices.
