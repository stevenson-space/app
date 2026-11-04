# Stevenson Space redesign: direction

## Brief (self-authored)

The maintainer asked for a full redesign and to proceed without a check-in,
so this brief is self-authored from the README, `launch/BRIEF.md`,
`launch/positioning.md` and the code. Nothing here spends paid credits: no image
generation was used.

1. **The app:** Stevenson Space, the bell schedule for Adlai E. Stevenson High
   School students. It shows today's period, how long until the bell, and
   what's next, including on Late Arrival, finals and assembly days. It also
   has the lunch menu, a student ID rebuilt from a screenshot, and widgets.
2. **The core action:** in the hallway or under the desk, open the app and
   know in two seconds whether to sit down or keep walking, how long is left,
   and where to go next.
3. **Three words:** spirited, exact, unfussy. References from outside apps:
   a varsity letter jacket (green melton wool, gold chenille, tackle-twill
   numbers), the gym scoreboard's period clock, and the hallway between bells.
4. **What exists:** the name (Stevenson Space, Home Screen name SHS Space),
   the Patriot crest (rights still unconfirmed), the crest's green `#1F5D39`
   and gold `#C99A2C`, system fonts, and a working SwiftUI codebase with
   shared presentation helpers in ScheduleKit.
5. **What's needed:** a redesign of every screen and widget, built in SwiftUI.
6. **Image generation:** not used.

## Current app

Captured in the iPhone 17 Pro Simulator on the 1.1.0 build, Monday Sep 14 at
10:46 with a demo schedule (`before/`).

**Which face it hits.** Neither named slop face exactly; it is the third
default, *the SwiftUI sample*: system grouped grey, a stack of white rounded
cards, an SF Rounded countdown inside a progress ring, rainbow role tints
(indigo classes, green lunch, cyan advisory, brown homeroom), rainbow lunch
station icon chips (orange, green, yellow, red, blue, purple), five more
rainbow family colours for special days, emoji per row, and a pill "NOW". The
tells it hits: everything is a card, icon chips, too many hues doing equal
work, the ring hero every timer app ships, and no richness source beyond emoji.
What is good and stays: the hierarchy is right (countdown first, then next,
then the day), passing gets its own layout, the copy is plain, and the
accessibility work (contrast-picked labels, Dynamic Type reflow, VoiceOver
summaries) is careful.

**History row for the current look:** `none · light · rounded · blue · none`.

### Keep list (a contract)

Home
- [ ] Day picker: previous/next day, tap the date for a calendar of any day in
      the catalog's school years, a way back to Today, a "preview" cue off today
- [ ] Schedule label: quiet on Standard, loud on any special day, with its
      icon; the day note; Manual override and Rotation unverified (tap to fix)
      badges; "Special schedules not synced yet"
- [ ] Overdue update reminder with Check for Updates
- [ ] Hero for every state: before school, in a block (class, lunch, advisory,
      free until, last block), passing vs switching halves, after school with
      the next school day
- [ ] Compact pinned countdown when the day scrolls
- [ ] The day's list: period label (1, 3–4A, 4B), class emoji, name, time,
      room; past dimmed, now highlighted, an "in 12m" cue on the next block
- [ ] Full-screen states: weekend, winter/spring/other break, no school,
      e-learning day, summer with "school starts in N days", unknown day
      type, override note, next school day
- [ ] DEBUG time-travel banner

Lunch
- [ ] Mon–Fri week strip, previous/next week, month label, today marker,
      no-menu days dimmed
- [ ] Date header, bundled-menu note, six stations with their items, the two
      empty states, Today / Next Lunch button, overdue update reminder

ID
- [ ] The printed card (does not follow dark mode, barcode black on white),
      tap or Show for Scanning for the full-screen barcode, earlier-year note,
      options menu (hide photo, replace screenshot, remove), empty state with
      three steps, Choose Screenshot, the on-device privacy line, import sheet

Settings
- [ ] My Schedule editor (rows like Home, edit sheet, Reset Schedule),
      notifications (end-of-period lead time, morning alert time, denied
      note), schedule overrides, appearance, time format, About links,
      version, independence disclaimer, DEBUG developer tools

Widgets
- [ ] Small, medium, large schedule; circular and rectangular Lock Screen;
      small and large Lunch; tinted and clear rendering modes

### Decisions for the maintainer

1. **Home's ground changes with the state** (green while a block is on, gold
   between bells, plain after school). This is the redesign's main idea.
2. **Special days lose their five rainbow colours.** Late Arrival, Odyssey,
   Activity Period, PM Assembly and Early Dismissal all get the same gold
   stitched patch; the name and icon tell them apart.
3. **Per-role tints in the list are gone** (indigo classes, green lunch, cyan
   advisory). The current block is shown by inverting its row.
4. **Lunch stations lose their rainbow icon chips.** Station names lead.
5. **Class emoji stay** as the student's own content, inline, with no chip.
   The default emoji for lunch, free, advisory and other non-class blocks go:
   those rows are named plainly.
6. **The app icon is not changed.** The Patriot crest's rights are still
   unconfirmed; a crest-free icon is proposed in the mockups only.

## Step 1: traps

Read slop.md in full. The history file was empty, so this app writes the
first row.

## Step 2: three directions

Imagery honestly available: the crest, the real data, nothing photographic.
So every direction has to draw its own richness.

1. **The gym scoreboard** (object). "Stevenson Space is the scoreboard in
   the main gym." Dark ground, SF Pro Compressed Heavy clock, scoreboard
   red, a bulb-dot shape language. PERIOD and TIME are already a
   scoreboard's words.
2. **The letter jacket** (object/material). "Stevenson Space is a varsity
   letter jacket." The ground is a colour field of green melton that turns
   gold between bells; cream chenille type with a gold twill edge in SF Pro
   Expanded Heavy; stitched seams for rules and progress.
3. **Sun across the commons** (nature). "Stevenson Space is the light moving
   across the commons skylight." A pale ground that warms through the day,
   New York serif display, sky blue, an arc of the day's periods with the
   sun at now.

Rendered in `explore.html` → `shots/explore/sheet.png`.

**Winner: the letter jacket.** It is the only one of the three that is
Stevenson's and nobody else's: the school's own green and gold, a countdown
set like a varsity number, and a ground whose colour *says* something (green:
sit down, a block is on; gold: keep walking). Cover the name and you still
know whose app it is.

- *Scoreboard lost* because it is a sports-broadcast costume: it works only
  dark, its red reads as an alarm all day, and it could be any school's app.
  Taken from it: the scoreboard's vocabulary in the eyebrow (PERIOD, ROOM).
- *Sun across the commons lost* because it is the editorial default (New York
  on pale blue) and its arc repeats what the countdown already says. Taken
  from it: nothing.

Fixes carried from the shoot: past rows failed contrast at 3.24:1 (now ink-2
on the field, never ink-3 for text); "3–4A" wrapped in its column (now 60pt,
no wrap).

**History check.** History was empty. Against the current look
(`none · light · rounded · blue · none`) it differs on all five columns.
Row to append: `object · colour-field · expanded · green · colour-material`.

## The category default refused

Saturn, Periodic, Bell Schedule and Class Timetable share: a white or system
grey list of rounded cards, a progress ring around the countdown, a rainbow of
per-class colours with icon chips, and stock emoji as decoration. The
category's colour cliché is the class-colour rainbow (and school-bus yellow).
Refused here: **no ring**, **no per-class colours**, **no card stack**, **no
icon chips**, **no rainbow special-day badges**. Green and gold are not a
cliché picked for "school": they are this school's colours, sampled from its
crest.

## Tokens

### Grounds (the colour field is a system)

| Ground | Means | Light | Dark | Ink on it |
|---|---|---|---|---|
| `field` (green melton) | a block is on: class, lunch, advisory, free | `#1D5A36` | `#0E2F1D` | chenille |
| `gold` (gold leather) | between bells: passing, switching halves, before the first bell | `#D3A33A` | `#5C4413` | `#13241A` light / chenille dark |
| `lining` | no school right now, and every other tab | `#EEF0EA` | `#0B120E` | `ink` |

### Roles

| Token | Light | Dark | Role |
|---|---|---|---|
| `chenille` | `#F3EAD2` | `#F3EAD2` | ink on the field |
| `chenille-2` | `#B9CDBB` | `#A9C0AD` | secondary ink on the field (4.8:1) |
| `twill` | `#C99A2C` | `#B58A27` | the varsity number's gold edge, elapsed stitches. Material, not text |
| `gold-ink` | `#E5C063` | `#E0BB5C` | the one live cue on the field (now, in 45m) |
| `ink` | `#13241A` | `#ECEFE8` | text on the lining |
| `ink-2` | `#4D5E52` | `#A3B0A6` | secondary text on the lining |
| `ink-3` | `#7C8A80` | `#6E7B72` | placeholders and glyphs only, never body text |
| `raised` | `#FFFFFF` | `#152019` | grouped rows and sheets on the lining |
| `rule` | ink at 12% | ink at 14% | hairlines; on the field a 1.5pt dashed stitch at chenille 16% |
| `accent` | `#1D6B3F` | `#7CC293` | on the lining: selection, today, the primary action. System tint |
| `on-accent` | `#FFFFFF` | `#0B120E` | |

The accent is green and its role is **action and selection** on the lining,
so the system tint is the accent. On the field the one live cue is
`gold-ink` (now, next-up), and the gold field itself is the state.

### Type

SF Pro only, two widths. **Expanded Heavy** is the varsity number: every
numeral that identifies something (the countdown, period numbers, day
numbers, the screen titles). Default-width SF Pro for everything that is read.

| Step | Size / weight / tracking | Use |
|---|---|---|
| Hero | 96 Expanded Heavy, −3.5%, tabular, twill shadow 3×4 | the countdown |
| Display | 34 Expanded Heavy, −1% | screen titles, the passing destination |
| Lead | 22 Semibold, −1% | the line under the hero, lunch dishes |
| Body | 17 Semibold / Regular | row titles, body |
| Secondary | 15 Regular | times, rooms, notes |
| Label | 12 Expanded Bold caps, +10% | eyebrows and section labels |

Six steps. Hero to label is 8×.

### Space and shape

Side margin 20. Spacing 4, 8, 12, 16, 24, 32, 44, 64. Radius family: 12 for
chips and the week-strip day, 16 for the inverted now row, 26 for grouped
lists and sheets (system), capsule for buttons. Hairlines, not cards; the only
objects that get a container are the ID card and the current block.

### Richness: green melton, gold twill, chenille, stitching

One hand: everything is something you could sew onto a jacket.
- The ground is a flat field of the school's green, or gold between bells.
- The countdown is set like tackle-twill lettering: chenille face, a hard gold
  edge offset 3×4pt (no blur, no glow).
- Rules are running stitches (1.5pt dashes); progress is a seam whose
  stitches turn gold as the block elapses.
- Special days get a stitched gold patch with the day's name and SF Symbol.
- No textures, no photos of felt. Colour and stitch only.

## The signature: the bell turns the jacket

The moment a block ends with Home on screen.

1. **0 ms** — the countdown reaches 0:00; the seam's last stitch turns gold.
2. **0–80 ms** — a heavy impact haptic: the bell.
3. **80–620 ms** — the gold field rises from the bottom edge over the green
   (spring, 0.55 s, no bounce), like the jacket turned to its gold side. Ink
   changes from chenille to dark green as the field passes under it.
4. **200–520 ms** — the hero rolls to the passing countdown
   (`numericText(countsDown:)`) and the line under it becomes
   "Walk to Precalculus Honors · Room 1311".
5. Five minutes later the green rises back the same way: sit down.

Reduced motion: the field cross-fades in 0.25 s and nothing moves; the haptic
stays. It is one second long, happens at most a few times a day, and tells the
student something true: the bell just rang.

## Content

The demo student is a junior with a 1½-period physics class and 4B lunch.
Monday, September 14, 2026, Standard schedule.

| Period | Block | Time | Room |
|---|---|---|---|
| 1 | AP English Language | 8:30 – 9:21 | 2108 |
| 2 | Precalculus Honors | 9:26 – 10:13 | 1311 |
| 3–4A | AP Physics C | 10:18 – 11:30 | 1616 |
| 4B | Lunch | 11:37 – 11:57 | |
| 5 | AP US History | 12:02 – 12:49 | 2215 |
| 6 | Spanish 4 | 12:54 – 1:41 | 1034 |
| 7 | Free | 1:46 – 2:33 | |
| 8 | AP Computer Science A | 2:38 – 3:25 | 3012 |

- **Home, in class (10:52):** "Mon, Sep 14", "Standard schedule", eyebrow
  "PERIOD 3–4A · ROOM 1616", hero "37:41", "left in AP Physics C", seam 47%
  sewn, "Ends 11:30", "Next: Lunch at 11:37", the list with Now and "in 45m".
- **Home, passing (9:23:10):** gold field, eyebrow "PASSING · 1 → 2", hero
  "2:50", "Walk to Precalculus Honors", "Room 1311 · starts 9:26".
- **Home, after school (Friday 4:12 PM):** lining, "Done for today", "Monday"
  with a gold patch "Late Arrival", hero "10:30" first bell.
- **Lunch (Mon Sep 14):** Comfort Food: Cheese Tortellini. Mindful: Lemon
  Garlic Baked Chicken. Sides: Roasted Carrots, Roasted Red Potatoes. Soup:
  Smoky Poblano, Chicken Noodle. International: Asian Bowl. Special: Sushi.
- **ID:** a fictional student, Priya Raman, Grade 11, 26–27, ID 512837.
- **My Schedule:** the eight blocks above with chevrons, Reset Schedule.

## Build

Built in SwiftUI on `feature/app-redesign` and checked in the iPhone 17 Pro
Simulator (iOS 27.2) in light, dark and the largest accessibility text size.
After-screens are in `after/`, the comparison in `before-after.png`.

- **Tokens** live in ScheduleKit (`Presentation/Jacket.swift`) so the app and
  the widgets share them; `JacketContrastTests` checks every ink against its
  ground in both appearances.
- **Chrome over the field.** Light-mode Liquid Glass over the green washes out
  to mint, so while Home is on the field its toolbar and tab bar take the dark
  appearance; the field colour itself stays the light-mode green.
- **Navigation titles** use the varsity face and twill edge through the
  navigation bar appearance, so the native large titles keep their behaviour.
- **Widgets** wear the same grounds in full colour; tinted and clear modes
  drop the background and keep system inks.

Differences from the mockups, on purpose: the passing screen puts the seam
under the destination (one hero structure for every state, so the countdown
rolls across a bell instead of being swapped); after school the list below is
still today's (stepping to tomorrow is one tap). Not built: the proposed
crest-free icon (decision 6).

Not verified: haptics and the signature's feel on a real device, Home Screen
widgets in place (the Simulator served a cached render, so widgets were checked
with an offscreen renderer), iOS 18 (the deployment target) on a device or
simulator.
