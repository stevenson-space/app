# Lunch Home Screen widgets

**Lunch Category** is a configurable small widget. Long-press it, choose Edit
Widget, and select Comfort Food, Mindful, Sides, Soup, International, or Special.
**Today’s Lunch** uses the large family: six categories with multi-item sides and
soups need more vertical space than medium provides at readable text sizes.

Both widgets use the standard system background, semantic text, and green
accent-aware category labels. Each menu option starts on its own line, without
inline bullets; the small widget shows a remaining-option count if the full list
does not fit. The large menu reads in
three paired rows. Menu options wrap at their natural size rather than shrinking.
Unusually long future menus or larger accessibility text fall back to the
category list with an explicit link to the full menu. Small widgets similarly
signal when more text is available in the app. VoiceOver retains the entire
selected category’s menu, including visually truncated text.

## Data and updates

- `LunchMenuLoader` is shared by the app and widgets. It prefers a valid cache,
  falls back to the bundled rotation, and uses the existing school calendar to
  exclude weekends, breaks, asynchronous days, and Summer schedules.
- Widgets read the existing App Group cache without initializing `SharedStore`,
  running migrations, or accessing student identity data. They do not fetch a
  second copy of the menu. The app’s existing `LunchMenuSyncService` owns live
  refreshes and retains the last good cache after a failed fetch.
- The app reloads both lunch widgets when lunch data or calendar inputs change.
  Widgets request hourly refreshes and publish seven days of Chicago-midnight
  entries. A final empty entry prevents the last menu from lingering indefinitely.
  Actual refresh delivery remains controlled by iOS.
- In DEBUG builds, lunch widgets follow the same shared time-travel clock and
  scenario overrides as the schedule widget. Menus and date labels use the
  simulated school date; midnight entries are translated back to real time so
  transitions still occur while the app is suspended. Changing the clock or
  scenarios requests a reload of both lunch widgets. Release builds use real
  time and ignore saved debug offsets. Tapping opens `stevenson-space://lunch`, resets time travel,
  selects Lunch, and resets a previously selected menu date to today.
- Before shared data is prepared, widgets invite the user to open the app.
  Off days show “No lunch today”; missing or expired menus on serving days show
  “Menu unavailable.” The date remains visible in every state.

## Validation

`LunchWidgetTests` covers valid/invalid/expired caches, calendar exclusions,
menu expiry, the terminal empty entry, DST rollover, and read-only storage.
Run `swift test --package-path Packages/ScheduleKit` and build the app scheme
for iOS Simulator to compile both the app and widget extension.

Apple references:

- [Making a configurable widget](https://developer.apple.com/documentation/widgetkit/making-a-configurable-widget)
- [App Intent timeline provider](https://developer.apple.com/documentation/widgetkit/appintenttimelineprovider)
- [Keeping a widget up to date](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date)

Implementation validation (September 21, 2026):

- All 230 ScheduleKit tests pass; app and embedded extension build for iOS
  Simulator in Debug and Release.
- A temporary iOS 18.6 SwiftUI ImageRenderer harness rendered the bundled rotation
  at 329×345 and 292×311 large bounds, plus all small categories at 155×155 and
  141×141. Representative longest dish names, sides, soups, light/dark, initial
  empty state, and accessibility layouts were visually inspected and refined.
  The harness passes widget family explicitly because WidgetKit owns that
  read-only environment value; these are view renders, not Home Screen captures.
- Text growth is bounded to Large in small and XXX Large in large widgets, as
  these fixed surfaces cannot scroll. Larger menu fallback labels retain the
  dishes in their VoiceOver text. Compact large widgets try independent columns
  before falling back to a category list or an explicit full-menu prompt.
- The installed app opens the Lunch tab on today through the lunch widget URL.
- Xcode’s widget preview service reported no available schemes. Actual Home
  Screen gallery configuration, system-tinted rendering, VoiceOver interaction,
  and OS-delivered refresh timing still require validation on a device.

Time-travel follow-up: all 232 ScheduleKit tests pass, including simulated lunch
selection, midnight translation, scenario overrides, and returning to real time.
The app and widget extension build in both Debug and Release for iOS Simulator.

Style follow-up: removed the green background wash in favor of the system
background. Options now use separate text rows with a small inter-option gap;
wrapped lines remain grouped as one dish. Small widgets prefer readable list
text for multiple options and report the remaining count when space runs out.
The simulator build passes. View renders were checked against the September 22
sides/soup example in dark mode and a dense menu at compact large-widget bounds.

Day-off styling: lunch widgets now reuse the schedule widget’s resting gradient
(primary at 2% to green at 14%, over the system background) when the resolved day
is not a serving day. Menu days, missing categories, and unavailable/loading data
keep the system background. This follows the existing simulated-day resolution.
The simulator build passes; light and dark day-off view renders and a neutral
menu-day render were visually checked.

Category palette follow-up: the lunch header now uses the schedule class-period
indigo accent. Category labels and icons share the app’s orange, green, yellow,
red, blue, and purple mapping through LunchMenuStation.color in ScheduleKit.
Small widgets and the large category fallback use the same mapping. Increased
contrast and non-full-color rendering retain the primary-color fallback and
widgetAccentable grouping. The simulator build passes; dark full-menu and light
small-category renders were visually checked.
