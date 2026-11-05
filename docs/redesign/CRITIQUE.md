# Critique

Scored by the designer against `critique.md`, harder than felt fair; no
separate critic agent was spawned for this job.

## Round 1 (`shots/r1`)

Scan: 10 FAILs. Contrast (the Now label 1.45:1 on chenille, the Today label
2.98:1 on gold), emoji in five screens, 10.5pt type on the card, 10pt type in
the circular widget.

| # | Line | Score | Evidence |
|---|---|---|---|
| 1 | Concept on the pixel | 4 | Home in class, passing and the widgets are unmistakably a letter jacket; Lunch and My Schedule could be any tidy app |
| 2 | Not the category average | 4 | No ring, no card stack, no class rainbow; the ground itself carries the state |
| 3 | Not this skill's average | 3 | Home is rich, but Lunch is type on a pale ground with rules: the "rich hero bolted onto a list" trap |
| 4 | Hierarchy | 4 | The countdown lands first on Home; after school the 10:30 lands first, which is right |
| 5 | Typography | 4 | Expanded Heavy against 15pt regular is real contrast; 18 sizes app-wide is too many |
| 6 | Colour | 4 | Green, gold, chenille, each with a job; dark mode deepens the field instead of greying it |
| 7 | Richness | 3 | The field and twill carry Home; the lining screens have only stitches |
| 8 | Rhythm and space | 4 | Tight hero group, a 44pt break before the day; Lunch stations are evenly spaced |
| 9 | Craft details | 3 | The now row is clipped by its list (no inset, no stitch), two contrast misses |
| 10 | Native fluency | 4 | Glass tab bar and toolbar pair, large titles, detented sheets assumed |
| 11 | Signature | 4 | The bell storyboard is clear and born from the concept |
| 12 | The feature test | 4 | "A school schedule that wears its colours" is a headline |
| 13 | Fidelity | 3 | The compact pinned countdown, the update reminder and the override badges are not shown |

**Five changes for round 2**
1. The now row: un-clip it from the list so it insets 12pt past the margins
   with its 16pt radius and the inner running stitch visible; Now label in
   field green.
2. Lining screens speak the voice: every Expanded title gets the twill edge
   (2×2.5pt), the selected Lunch day becomes a sewn patch (inner stitch), the
   lead dishes move to 22pt.
3. Contrast: labels on gold use `#3F3413`; card school line to 11.5pt;
   widget labels to 11pt.
4. Design the scrolled Home: the countdown collapses into a pinned glass
   strip over the field while the day scrolls under it.
5. Merge type sizes: period numbers 16→17, Lunch items 20→22, storyboard
   title 30→34.

**Emoji FAIL, answered.** The emoji are the student's own content (a shipped
personalization feature with its own picker and App Store screenshot), not
icons the design chose. They stay inline at 15pt with no chip. Removing them is
the maintainer's decision #5 in DIRECTION.md; the scan FAIL is knowingly left.

## Round 2 (`shots/r2`)

Scan: the only FAILs left are the answered emoji. Warns answered: My Schedule
has three sizes because it is a dense editing list under a 34pt title
(`data-dense`); the app-wide size count includes the printed ID card's own
proportional type and the widget sizes, which follow WidgetKit metrics.

| # | Line | R1 | R2 | Evidence |
|---|---|---|---|---|
| 1 | Concept on the pixel | 4 | 4 | Lunch, ID and My Schedule now carry the twill title and stitched rules; still quieter than Home by design |
| 2 | Not the category average | 4 | 4 | Unchanged |
| 3 | Not this skill's average | 3 | 4 | The lining screens speak the direction's type, stitch and patch instead of a generic list |
| 4 | Hierarchy | 4 | 4 | The scrolled Home keeps the countdown first in a 56pt pinned strip |
| 5 | Typography | 4 | 4 | Period numbers and dishes moved onto the scale; Expanded Heavy owns every numeral |
| 6 | Colour | 4 | 4 | Labels on gold now `#3F3413`; nothing below 4.5:1 for text |
| 7 | Richness | 3 | 4 | The sewn day patch and twill titles bring material to the lining; Lunch is still the plainest screen |
| 8 | Rhythm and space | 4 | 4 | Unchanged |
| 9 | Craft details | 3 | 4 | The now row insets past the margin with its inner stitch; contrast clean |
| 10 | Native fluency | 4 | 4 | Pinned strip is glass over the field, toolbar pair and tab bar glass |
| 11 | Signature | 4 | 4 | Unchanged |
| 12 | The feature test | 4 | 4 | Unchanged |
| 13 | Fidelity | 3 | 4 | Scrolled countdown and the update reminder are designed; special days shown through the patch |

**Landed:** all five round-1 asks.

**Stop rule:** done (no line below 3, 13 of 13 at 4). Iteration stops here;
the build is judged against these frames in the Simulator.

Not verified by a mockup: motion timing, the haptic, and how the gold field
reads in direct sunlight.
