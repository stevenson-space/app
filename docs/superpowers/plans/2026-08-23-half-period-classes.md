# One-and-a-half-period classes Implementation Plan

> **Status: executed 2026-08-23** (inline, same session). All tasks complete: 142/142 package tests pass, app builds, feature verified end-to-end in the iPhone 17 simulator (editor flow → merged Home timeline). Per the session rule the work was left uncommitted for review; it was later committed as c97849c.
>
> **v2 same day:** per user feedback the UI tasks (4–6) were superseded by the card-based redesign in the spec's v2 section — shared `ScheduleCardRow`, editor-as-card-list with tap sheets, Settings midday section removed, emoji support. Engine tasks (1–3) unchanged; suite now 153 tests, all green; re-verified visually in the simulator. Tasks 4–6 below are annotated accordingly: their v1 steps were executed, then their output was replaced, so their descriptions no longer match shipped code.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Model 1½-period classes and half-period lunch/advisory/free through a per-period plan grid in `UserConfig`, merge contiguous class slots in the resolver, and redesign the period editor so all of a student's day is configured in one place.

**Architecture:** `UserConfig` gains `periodPlans: [Int: PeriodPlan]` (each period = two `HalfSlotAssignment` half-slots; class slots carry an anchor period) as the single source of truth; `lunch`/`advisory`/`freePeriods` become derived computed properties that read/write the grid so every existing call site and test keeps working. `personalizedBlocks` resolves half-slots and merges adjacent same-anchor class slots into single `ResolvedBlock`s (with a new `spanLabel`); non-splittable schedules keep today's one-block-per-period precedence. The app's period editor is rebuilt around layout (full/split) + per-half content.

**Tech Stack:** Swift 6 / SwiftUI / Swift Testing (`@Suite`/`@Test`/`#expect`), SPM package `ScheduleKit`.

## Global Constraints

- Session rule: **no git commits** (user hasn't asked); leave the working tree for review. Plan tasks therefore end at "tests pass", not "commit".
- Entire existing ScheduleKit test suite must pass **unmodified** (parity gate).
- All date/time math stays in `America/Chicago` via `SchoolTime.calendar`; no `+24h` arithmetic.
- Public API changes must keep existing call sites compiling (`config.lunch`, `config.lunch?.choice = …`, `config.advisory = nil`, `config.freePeriods.contains/insert/remove`, `setPairedAdvisory`, `clearAdvisory`, memberwise `UserConfig(lunch:advisory:freePeriods:customizations:hideFreePeriods:timeFormat:appearance:)`).
- Stored blobs written by the current release must decode losslessly (legacy fields → grid); new blobs must keep writing the legacy fields alongside `periodPlans` for downgrade tolerance.
- Tests: `swift test --package-path Packages/ScheduleKit`. App build: `xcodebuild -scheme "Stevenson Space Companion App" -destination 'generic/platform=iOS Simulator' build`.

---

### Task 1: `HalfSlotAssignment` + `PeriodPlan` model

**Files:**
- Create: `Packages/ScheduleKit/Sources/ScheduleKit/Models/PeriodPlan.swift`
- Test: `Packages/ScheduleKit/Tests/ScheduleKitTests/PeriodPlanTests.swift`

**Interfaces:**
- Produces:
  - `enum HalfSlotAssignment: Equatable, Hashable, Codable, Sendable { case classSlot(anchor: Int), lunch, advisory, free }` with `var classAnchor: Int?`; encodes as single string `"class:2"`, `"lunch"`, `"advisory"`, `"free"`; unknown strings **throw** on decode (UserConfig catches and falls back to legacy fields).
  - `struct PeriodPlan: Equatable, Hashable, Codable, Sendable { var a, b: HalfSlotAssignment }` with `static func standardClass(_ n: Int) -> PeriodPlan`, `var isUniform: Bool`, `func slot(_ half: Half) -> HalfSlotAssignment`, `mutating func setSlot(_ half: Half, _ new: HalfSlotAssignment)`, `func isStandardClass(for n: Int) -> Bool`.

- [x] **Step 1: Write failing tests** — codable round-trip for every case, string forms, unknown-string decode throws, `standardClass`/`isUniform`/`isStandardClass` behavior.
- [x] **Step 2: Run to verify failure** (`swift test --package-path Packages/ScheduleKit --filter PeriodPlanTests`) — compile error: types not defined.
- [x] **Step 3: Implement `PeriodPlan.swift`.**
- [x] **Step 4: Run to verify pass.**

### Task 2: `UserConfig` grid storage, migration, derived accessors

**Files:**
- Modify: `Packages/ScheduleKit/Sources/ScheduleKit/Models/UserConfig.swift`
- Test: `Packages/ScheduleKit/Tests/ScheduleKitTests/PeriodPlanTests.swift` (extend)

**Interfaces:**
- Consumes: Task 1 types.
- Produces (all on `UserConfig`):
  - `var periodPlans: [Int: PeriodPlan]` (sparse storage) and `func plan(for n: Int) -> PeriodPlan` (Friday-agnostic, defaulting to `.standardClass(n)`).
  - `var lunch: SplitAssignment? { get set }` — derived: scan periods 1–8; both halves `.lunch` ⇒ `.full`; single half ⇒ `.a`/`.b`; setter clears every existing `.lunch` slot (reverting each to `.classSlot(anchor: period)`) then paints the new assignment (`.full` ⇒ both halves).
  - `var advisory: SplitAssignment? { get set }` — same pattern for `.advisory` slots (setter used by `clearAdvisory` and migration; `.full` advisory paints both halves).
  - `var freePeriods: Set<Int> { get set }` — derived: periods whose plan is uniform `.free`; setter diff-applies (insert ⇒ uniform free; remove ⇒ `.standardClass`).
  - `mutating func setSlot(period: Int, half: Half, to: HalfSlotAssignment)` — primitive painter.
  - `mutating func setClassExtended(anchor: Int, _ extended: Bool)` — `extended` ⇒ `plans[anchor+1].a = .classSlot(anchor: anchor)`; retract ⇒ restore `.classSlot(anchor: anchor+1)` only if currently pointing at `anchor`. Guard `1...7`.
  - `func classSpan(anchor: Int) -> (start: (period: Int, half: Half), end: (period: Int, half: Half))?` — nil when the anchor period doesn't hold its own class; else walks `anchor-1`’s B and `anchor+1`’s A for matching anchors (used by editor + row summaries). *(Later removed in review cleanup: the v2 card editor uses `classLength(anchor:)` instead, leaving `classSpan` with no production caller.)*
  - `setPairedAdvisory` / `clearAdvisory` keep exact signatures/semantics, rewritten over the grid.
  - Memberwise init keeps its signature, building the grid (order: freePeriods → advisory → lunch, so lunch wins legacy same-half conflicts).
  - Codable: decode `periodPlans` when present & parseable (per spec: on *any* failure fall back to legacy-field derivation); encode `periodPlans` **and** derived `lunch`/`advisory`/`freePeriods`.

- [x] **Step 1: Write failing tests** — legacy-blob JSON decodes to expected grid (lunch A / advisory pair / freePeriods / full lunch / same-half conflict); encode writes both representations (decode encoded blob with legacy-only reader); derived accessor get/set behaviors incl. lunch move clearing old slots; `setClassExtended` paint/retract; ~~`classSpan` forward/backward/none~~ *(written as planned, then removed with `classSpan` in review cleanup)*; paired-advisory invariants already covered by existing suite.
- [x] **Step 2: Verify failure.**
- [x] **Step 3: Implement.**
- [x] **Step 4: Run `PeriodPlanTests` + `AdvisoryPairingTests` + `StorageAndSyncTests` — all pass.**

### Task 3: Resolver merge pass + `spanLabel`

**Files:**
- Modify: `Packages/ScheduleKit/Sources/ScheduleKit/Models/DayTimeline.swift` (add `ResolvedBlock.spanLabel: String?`, default nil in init)
- Modify: `Packages/ScheduleKit/Sources/ScheduleKit/Resolution/DayResolver.swift` (rewrite `personalizedBlocks`, `fridayAdvisoryAdjusted` → grid; delete `halfRole`/`HalfChoice.matches`)
- Test: `Packages/ScheduleKit/Tests/ScheduleKitTests/ContinuationTests.swift` (new)

**Interfaces:**
- Consumes: `config.plan(for:)`, `HalfSlotAssignment`.
- Produces: `ResolvedBlock.spanLabel` — nil for plain full periods, `"4A"` for half blocks, `"2–3A"` (en dash) for merged spans; merged block: `id` = constituent ids joined `"+"` (`"2+3A"`), `periodID` = anchor, `half` = nil, name/room from anchor customization.

Resolution algorithm (splittable schedules): per numbered period emit either one full-period entry (uniform plan) or two half entries (mixed), tagging each with `(role, anchor?)`; Friday maps `.advisory` slots → `.lunch` first. Then merge consecutive `role == .classPeriod` entries with equal anchors. Non-splittable schedules: one block per period, precedence `lunch > advisory > class > free`, class name from the first class slot's anchor, **no merging**.

- [x] **Step 1: Write failing tests** — forward merge times/id/label/name/room; backward merge (`3B+4` anchored 4); leftover-half lunch and free both orders; back-to-back 1½ classes; Late Arrival & Early Dismissal fallbacks (no merge, anchored names); Friday grid advisory; `momentState` inside merged class at internal bell = `.inBlock`; NotificationPlanner emits single end alert for merged class.
- [x] **Step 2: Verify failure.**
- [x] **Step 3: Implement.**
- [x] **Step 4: Full package suite passes (parity gate).**

### Task 4: Timeline row uses `spanLabel` *(superseded by v2)*

> **Superseded by v2:** executed as written, then replaced the same day — `DayTimelineListView` was rebuilt on the shared `ScheduleCardRow` (`Features/Home/ScheduleCardRow.swift`), which renders `spanLabel` on each card. The v1 description below no longer matches shipped code.

**Files:**
- Modify: `Stevenson Space Companion App/Features/Home/DayTimelineListView.swift:69-76`

`BlockRow` capsule condition becomes `if let label = block.spanLabel` rendering `Text(label)` (was `block.periodID.storageKey + half.rawValue`).

- [x] **Step 1: Edit view.** *(v1; output replaced by v2 card row)*
- [x] **Step 2: App builds** (`xcodebuild … build`).

### Task 5: Period editor redesign *(superseded by v2)*

> **Superseded by v2:** the layout/split editor below shipped in v1, then was replaced the same day by the card-based editor — `PeriodEditorView` is now a card list of `ScheduleCardRow`s with tap-to-edit sheets (Class/Lunch/Free, name/room/emoji fields, Length menu incl. 1½ periods in either direction; freshman advisory rides the lunch sheet as a paired toggle). See the spec's v2 section for the shipped design.

**Files:**
- Rewrite: `Stevenson Space Companion App/Features/Settings/PeriodEditorView.swift`

**Interfaces:**
- Consumes: `plan(for:)`, `setSlot`, `setClassExtended`, `classSpan`, `customizations`, `setPairedAdvisory`, derived `lunch`.

Design (per spec):
- `PeriodEditorListView` rows: period ordinal + primary line (class name / "Lunch" / "Free Period" / "Not named") + detail line built from the plan (e.g. `Runs into 3A`, `A: Lunch · B: 4th Period class starts`, `A: continues 2nd Period class · B: Free`), FREE capsule for uniform-free periods.
- `PeriodDetailView(number:)`:
  - Layout picker: Full period | Split A/B (segmented). Split is derived (`!plan.isUniform` or explicit); switching to Full sets uniform own-class (content picker then adjusts); switching to Split seeds `(a: own-class→shown as invalid? no — seeds (a: .lunch, b: .classSlot(own))`? — **Decision:** seed split as `(a: .free, b: .free)` only when coming from Free, else `(a: .lunch, b: .classSlot(own))` is presumptuous; simplest neutral seed: keep both halves' current uniform value, which the pickers then edit (uniform class shows both halves as "…" needing choice — but uniform class in split view is a hidden own-class pair, immediately re-rendered as Full). Final rule: Layout picker selection is **stored UI state initialized from the plan**; Split view shows per-half pickers whose current values map from the plan, with `classSlot(own)` rendered as a disabled "(period's own class — choose what happens here)" row that must be changed; leaving the screen normalizes: if both halves ended up `classSlot(own)`, collapse to Full.
  - Full period content picker: My class | Lunch | Free. Class shows name/room `TextField`s (save-on-disappear like today) + length picker (periods 1–7): `1 period` | `1½ periods (into (N+1)A)`; 1½ disabled with footnote when `(N+1)A` is `.lunch`/`.advisory`; choosing 1½ paints via `setClassExtended` and reveals leftover picker for `(N+1)B`: Free (default) | Lunch | Start of period (N+2) class (only when `plan(N+2)` starts with own class).
  - Split per-half pickers: Half A → [Continues (N−1) class (iff `plan(N−1).b == .classSlot(N−1)`)] | Lunch | Advisory (periods 4–6) | Free. Half B → [Start of (N+1) class (iff `plan(N+1).a == .classSlot(N+1)`)] | Lunch | Advisory (4–6) | Free. Advisory selection auto-sets other half to Lunch (and clears lunch elsewhere) via `setPairedAdvisory`.
  - Name/room fields always visible when any half of this period or its span belongs to a class anchored here.

- [x] **Step 1: Rewrite editor.** *(v1; output replaced by v2 card editor)*
- [x] **Step 2: App builds; manual reasoning pass over each state transition.**

### Task 6: Settings midday section as a grid view + footer *(superseded by v2)*

> **Superseded by v2:** rather than reworking the midday section, v2 removed it from Settings entirely — the card editor (grid) is the single source of truth, and Settings keeps only a pointer line to Periods & Classes.

**Files:**
- Modify: `Stevenson Space Companion App/Features/Settings/SettingsView.swift:40-133`

Pickers already write through `config.lunch` / `setPairedAdvisory` — they now hit the derived setters (verify semantics: changing lunch period keeps wave; clearing sets nil). Add footer: "Have a class that runs 1½ periods? Set its length in Periods & Classes — lunch and the leftover half live there too." Show a read-only line when lunch was set from the grid into a shape the quick pickers can't express (defensive: pickers cover all `SplitAssignment` shapes, so only needed if advisory unpaired — skip).

- [x] **Step 1: Edit section + footer.** *(v1; section removed outright in v2)*
- [x] **Step 2: App builds.**

### Task 7: Verification gate

- [x] `swift test --package-path Packages/ScheduleKit` — all green (153 at v2; suite has since grown).
- [x] `xcodebuild -scheme "Stevenson Space Companion App" -destination 'generic/platform=iOS Simulator' build` — succeeds.
- [x] Re-read spec; confirm each requirement maps to shipped code; update spec if implementation diverged (spec's v2 section documents the shipped UI).
