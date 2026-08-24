# One-and-a-half-period classes & unified period customization

**Date:** 2026-08-23 · **Status:** Implemented, then revised same day per user feedback (v2 below)

## v2 revision — card-based UI (user feedback: v1 editor "way too complex")

The engine (period-plan grid, resolver merge pass, migration) is unchanged.
The entire surface was rebuilt around one visual: a **card list of the day**
(emoji · name · time · room), shared by Home and the editor.

- **Home** renders blocks as cards; the current block carries a NOW chip, the
  next upcoming one a green "In 14h 9m" chip (per-minute TimelineView). Span
  info ("3–4A", "4B") lives in the subtitle, not a capsule.
- **The editor is the same card list** (`standardTemplate(config:catalog:)`,
  a new public ScheduleKit wrapper resolving the personalized standard day on
  a reference Monday). Tapping a card opens one compact sheet:
  - *Whole-period card*: segmented Class | Lunch | Free; class shows emoji +
    name + room fields and a single **Length** menu (`1 period`, `1½ — runs
    into (N+1)A`, `1½ — starts in (N−1)B`, options hidden/blocked when the
    claimed half holds lunch/advisory). The leftover half automatically
    becomes its own Free card.
  - *Half-period card*: one flat picker — **Lunch · Free** only (user
    decision). Class extensions are set exclusively from the class card's
    Length menu. A migrated advisory or dangling class-slot value shows as a
    read-only fallback row until changed.
  - *Advisory (freshmen)*: an **"I have Advisory" toggle on the lunch
    surfaces** (periods 4–6): the whole-period Lunch card's sheet (with an
    A/B advisory-half picker while on) and a lunch half card's sheet (offered
    when the other half is free). Advisory always pairs — it takes one half,
    lunch the other. Toggling off on the whole-period Lunch card restores the
    full-period lunch; toggling off on a lunch half card frees the advisory
    half and keeps the lunch wave.
    Moving lunch across a period's halves frees the vacated half (no phantom
    half class).
  - Split mode, per-half pickers-inside-period-screens, and the separate
    Settings "Lunch & Advisory" section are **gone**; lunch is set by tapping
    a card, waves by tapping the leftover half card.
- `PeriodCustomization` gains optional `emoji`; blank falls back to a
  role/subject default (⚛️ physics, 💻 CS, 🍔 lunch, 🥳 free, …).
- New model helpers: `setClassStartsEarly(anchor:_:)` (backward 1½, refuses
  to displace lunch/advisory, fully displaces a neighbor class and retracts
  its claims — no phantom or orphan halves) and `retractClassClaims(anchor:)`
  (used when a class card turns into lunch/free).
- **Free periods are always anonymous** (user decision, revising v1): every
  free block displays "Free Period" — no label field, and a stored
  name/emoji (which belongs to the period's class, kept for when it returns)
  never leaks onto free, lunch, or advisory cards.

Original v1 spec follows; its engine sections still describe the shipped code.

## Problem

Stevenson runs some classes — notably science classes — across one and a half
periods (a full period plus the adjacent half of the next, e.g. periods 2
through 3A, or 3B through 4). The app can only model full-period classes, and
lunch/advisory live in a separate Settings section as exception overlays on top
of the period list. Consequences:

- A student with chemistry 2–3A and lunch 3B cannot express the class at all;
  setting lunch 3B leaves a phantom 20-minute "3rd Period" block in 3A.
- The half that remains next to a lunch wave is ambiguous: it may be the tail
  of the previous class, the start of the next one, advisory, or free — none
  of which the current model can say.
- Lunch-as-separate-setting means the period editor and the lunch section can
  fight over the same half-period.

## Design decision: a per-period plan grid

`UserConfig` gains a single source of truth for what the student does all day:

```swift
/// One half of a period in the student's week.
public enum HalfSlotAssignment: Equatable, Hashable, Codable, Sendable {
    /// Part of the class anchored at `anchor`. For a normal class the anchor is
    /// the period itself; for a 1½-period class the spilled half points at the
    /// adjacent anchor period (the period fully contained in the class).
    case classSlot(anchor: Int)
    case lunch
    case advisory
    case free
}

/// A period's plan: what each half holds. Missing entry ⇒ the default,
/// a full-period class anchored at the period itself.
public struct PeriodPlan: Equatable, Hashable, Codable, Sendable {
    public var a: HalfSlotAssignment
    public var b: HalfSlotAssignment
}

public struct UserConfig {
    public var periodPlans: [Int: PeriodPlan]   // sparse, periods 1–8
    public var customizations: [String: PeriodCustomization] // unchanged, keyed by anchor
    // lunch / advisory / freePeriods become DERIVED accessors (see Migration)
}
```

Why this shape wins:

- **Conflicts are unrepresentable.** Each half-slot holds exactly one thing.
  Today's "lunch wins any misconfigured tie" backstop survives only for legacy
  blobs and non-splittable days.
- **1½-period classes are just contiguous slots with a shared anchor.**
  Chemistry 2–3A ⇒ `plans[3].a = .classSlot(anchor: 2)`. Physics 3B–4 ⇒
  `plans[3].b = .classSlot(anchor: 4)`. The anchor is always the period fully
  contained in the class, so names/rooms stay keyed by the period students
  associate with the class, and **existing `customizations` keys stay valid**.
- **Identity survives finals reordering** exactly as before — anchors are
  period numbers, and Early Dismissal days (no A/B tables) resolve per period.
- The model tolerates longer chains (a future 2-period class) without new code;
  the UI simply doesn't offer them.

### Anchor rules

- Valid anchors for period N's halves: N−1 (half A only, "class continues from
  the previous period"), N (own class), N+1 (half B only, "next period's class
  starts early"). Mutating helpers only produce these; the resolver renders
  stray anchors defensively (as a class block named by that anchor) and merges
  only *adjacent* equal-anchor slots, so bad data can't crash or corrupt.
- A class anchored at N always occupies both halves of N (no half-period
  classes — school reality). The editor cannot construct `classSlot(own)` on
  one half of a mixed period; the one legacy exception is migrated half-lunch
  data (see Migration), which continues to render as it does today.

## Resolver changes (`personalizedBlocks`)

1. **Friday advisory rule, grid form:** on Fridays, every `.advisory` slot
   becomes `.lunch` before resolution. (Paired advisory+lunch ⇒ uniform lunch
   ⇒ one full-period lunch block — identical to today's behavior.)
2. **Splittable schedules** (Standard, Activity Period, PM Assembly): for each
   numbered period, a *uniform* plan (both halves equal) emits one full-period
   entry; a mixed plan emits its two half entries. Then a **merge pass** joins
   consecutive class entries with the same anchor into one `ResolvedBlock`:
   - Chemistry 2–3A ⇒ one block 9:26–10:38, spanning the 2→3 passing period
     (the student stays in the room; the countdown and the end-of-period
     notification treat it as one class).
   - Block `id` = constituent ids joined with `+` (`"2+3A"`, `"3B+4"`), so ids
     for un-merged configurations are byte-identical to today's, and
     notification identifiers stay stable.
   - `periodID` = anchor; `half` = nil for merged blocks.
   - New `ResolvedBlock.spanLabel: String?` drives the capsule in the UI:
     `nil` for plain full periods, `"4A"` for half blocks (as today), `"2–3A"`
     for merged spans.
3. **Non-splittable schedules** (Late Arrival, Odyssey, Early Dismissal,
   Summer): each period resolves to ONE block by the safe-direction precedence
   `lunch > advisory > class > free` (matches today's fallback exactly — a
   lunch half still claims the whole period on Late Arrival). Class names
   follow the class slot's anchor. **No cross-period merging** here: on a
   finals day the app cannot know which slot hosts a 1½-period class's final,
   so periods stay separate and honestly labeled.
4. `buildMoments`, `momentState`, and `NotificationPlanner` are untouched —
   merged blocks arrive pre-merged, free-run merging still applies, and a
   merged class no longer emits a phantom passing state at the internal bell.

## Migration & compatibility

- `UserConfig` decoding: if `periodPlans` is present, use it. Otherwise derive
  it from the legacy fields in this order — `freePeriods` (uniform free), then
  `advisory`, then `lunch` (last, so lunch wins a legacy same-half conflict,
  matching the old resolver backstop).
- Encoding writes `periodPlans` **and** the derived legacy `lunch`/`advisory`/
  `freePeriods` fields, so a downgraded build still reads a sensible config.
- `lunch`/`advisory` remain in the public API as derived accessors returning
  `SplitAssignment?` (scan periods 1–8; both halves ⇒ `.full`); the Home lunch
  prompt and Settings summary keep working unchanged.
- The legacy memberwise initializer `UserConfig(lunch:advisory:freePeriods:…)`
  survives and builds the grid internally — the entire existing
  Personalization/AdvisoryPairing test suites must pass **unmodified** (parity
  proof).
- `setPairedAdvisory` / `clearAdvisory` keep their signatures and semantics
  (advisory 4–6 only, lunch auto-takes the other half, clearing advisory keeps
  the lunch half), now writing to the grid.

## UI redesign

### Periods & Classes (the one place your day is defined)

- **List rows** get a computed summary: class name/room, `2–3A` span capsule
  for extended classes, per-half lines like `A · Lunch  ·  B · start of 4th
  Period class`, and the FREE capsule for fully free periods.
- **Period detail** (redesigned):
  - Layout control: **Full period** vs **Split A/B**.
  - Full period → content: **My class** (name + room fields, as today) /
    **Lunch** / **Free**. When content is a class and the period < 8, a
    **length control**: `1 period` or `1½ periods (runs into (N+1)A)`.
    Choosing 1½ paints `(N+1).a = classSlot(N)` and reveals an inline picker
    for the leftover `(N+1)B`: **Lunch** / **Free** / **Start of period
    (N+2)'s class** (back-to-back 1½-period classes; offered only when N+2
    exists and currently begins with its own class). Default is Free — the
    app never silently moves an existing lunch. The 1½ option is disabled
    with an explanation if `(N+1)A` currently holds lunch or advisory.
  - Split A/B → one picker per half, contextually built:
    - Half A: *Continuation of period N−1's class* (only when N−1 ends with
      its own class) / Lunch / Advisory (periods 4–6) / Free.
    - Half B: *Start of period N+1's class* (only when N+1 begins with its own
      class; makes that class 1½ periods anchored at N+1) / Lunch / Advisory
      (4–6) / Free.
    - Choosing Advisory auto-sets the other half to Lunch (paired, like
      today); a legacy migrated `classSlot(own)` half renders as a labeled
      fallback row until the user picks something valid.
- **Settings "Lunch & Advisory" section** stays as the fast path for the
  common cases (full-period lunch, simple wave, freshman advisory pairing) but
  becomes a *view over the grid* — its pickers call the new grid helpers, and
  a footer points to Periods & Classes for 1½-period classes. No second source
  of truth.
- `DayTimelineListView` capsule switches from `half` to `spanLabel`.

## Error handling

- Resolver never trusts the grid: unknown anchors render defensively, chains
  merge only when adjacent, and a school day with zero blocks still degrades
  to the existing honest fallbacks.
- Decoding tolerates missing/unknown keys exactly as before (tolerant
  `decodeIfPresent` style); an unknown `HalfSlotAssignment` kind (written by a
  future version) fails the grid decode as a whole, falling back to the legacy
  lunch/advisory/free mirror fields every version keeps writing — a coherent
  approximation instead of a per-slot guess.

## Testing

- New `PeriodPlanTests`: codable round-trip, legacy-blob migration (each
  legacy shape), legacy-field write-back, derived lunch/advisory accessors,
  helper invariants (setLunch clears old slots; advisory pairing; extend/
  retract class length).
- New `ContinuationTests`: forward merge (times, id `2+3A`, spanLabel, name
  and room from anchor), backward merge (`3B+4` anchored 4), leftover-half
  lunch and free in both orders, two adjacent 1½ classes, non-split fallback
  on Late Arrival and Early Dismissal (no cross-period merge; names follow
  anchors), Friday advisory on the grid, moment/state-machine behavior inside
  a merged class at the internal bell (inBlock, not passing), single end
  notification at the merged end.
- Entire existing suite passes unmodified (parity gate).

## Out of scope

Widgets/Live Activity (unchanged contract via ScheduleKit), onboarding flow,
schedule sharing, 2-period classes in the UI, remote bell-table changes.
