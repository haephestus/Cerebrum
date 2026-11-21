# Vim in-block navigation — phased build plan

## Goal

Make `j`/`k` (and visual-mode extension) move **within** a wrapped
paragraph block by display (visual) line before crossing to the next
block. Today vim navigation jumps block-to-block only: pressing `j`
on line 1 of a 3-row wrapped paragraph lands on the next paragraph,
skipping rows 2–3 of the current block. `h`/`l` already step one
character inside the current block (see current state below) — the
gap is vertical, and it is the whole of `hjkl`'s in-block story for
multi-line blocks.

## Current state (verified)

* All vim motions live in
  `src/lib/ui/screens/editor/helpers/editor_commands.dart`,
  entry points `VimCharacterShortcuts.getCharacterShortcuts`
  (IME-attached path) and `VimCharacterShortcuts.getRawKeyVimShortcuts`
  (IME-less command path). Both delegate to the same routers
  `_navHorizontal` / `_navVertical` → `_navInNormalMode`.
  Changing the router changes both paths identically — there is no
  second copy to keep in sync.
* `j`/`k` in normal mode call `_moveToSiblingLine` /
  `_siblingTarget`: `path => [...path[0..n-1], path.last ± 1]`,
  offset = same offset clamped to the target node's delta length.
  One sibling == one block (paragraphs are top-level children of the
  `page` root under Strategy B). There is no concept of a wrapped row
  inside a node. This is why `j` "only skips to the next block".
* `h`/`l` in normal mode call `_moveCharacter` /
  `_characterTarget`: offset ± 1 inside the same path, wrapping to
  the far edge of the adjacent sibling at a node boundary. In-block
  character motion for `h`/`l` already exists and is tested
  headlessly (`src/test/vim_visual_test.dart`,
  `src/test/vim_table_navigation_test.dart`).
* Native arrow keys (`ArrowUp`/`ArrowDown`) already have in-block
  behaviour: they call `Position.moveVertical(editorState)` from
  `appflowy_editor-6.0.0` (`position_extension.dart`), which scans
  vertically in pixel space and returns the position on the next
  display row inside the same node before falling back to the
  neighbour block. Vim `j`/`k` bypass this entirely.
  `SelectionMoveRange.line` (the stock "line" enum in
  `selection_commands.dart`) is **not** vertical motion — it sets
  offset to 0 / `delta.length` on the same node. The stale comment
  on `_moveToSiblingLine` blames `SelectionMoveRange.line` for being
  "inconsistent"; the right comparison is with `moveVertical`, which
  is the function arrows use and it is not mentioned anywhere in the
  codebase.
* Visual mode `v` extends via `_extendByMotion`, which reuses the
  same `_siblingTarget` / `_characterTarget` math against the head.
  So `v`+`j` has the same block-skip defect as normal `j`.
* `0` / `$` set offset `0` / `delta.length` of the caret node —
  logical-line start/end, not display-line start/end. On a wrapped
  paragraph, `$` jumps to the end of the whole paragraph, not the
  end of the screen row. This is arguably correct for logical `$`
  but wrong if `j`/`k` become display-line motions (see Phase 2).
* Analysis mode (`n` review) intentionally stays block-granular
  (`_moveBlockInAnalysis`, whole-block `selectable` highlight).
  In-block caret motion must not leak into it.
* Table cells: caret sits on the nested paragraph inside a
  `table/cell`. `_navInNormalMode` first routes through
  `_moveInTableCell` (cell-to-cell), which swallows at table edges.
  This containment must be preserved verbatim in every later phase.
* Document shape under Strategy B (`kUseSingleDocumentPagination =
  true` in `flow_executor.dart`): one `EditorState`, root type
  `page`, children are the blocks (paragraph / heading / table …)
  each stamped with `pageId`. Sheets are runs of same-`pageId`
  children. Path `[i]` therefore means "i-th top-level block".
* Layout: canonical width `kDocSheetWidth = 700`, body 7pt,
  horizontal padding 40 (`page_space.dart`). The editor lives in a
  fixed `SizedBox` inside the zoomable canvas, so wrap points are
  stable document units; zoom only applies a paint transform.
  `RenderParagraph.getOffsetForCaret` / `getPositionForOffset`
  (used by `paged_fork/paged_rich_text.dart`) are the local
  APIs `moveVertical` drives through the widget tree.
* Tests today: headless `EditorState` only
  (`vim_visual_test.dart`, `vim_table_navigation_test.dart`,
  `vim_open_line_test.dart`, `tmp_dd_focus_test.dart`). None of them
  pump a rendering tree, so `node.renderBox == null`,
  `node.selectable == null`, and `moveVertical` returns `this`.
  Any plan that only reuses upstream vertical motion will regress
  silently in those tests unless a headless fallback is kept.

## Edge cases, failure modes, and unstated assumptions

State these plainly; each one is a real risk, not a hypothetical.

1. **Wrapped vs. logical lines.** A paragraph node has one delta,
   but the sheet renders it as N display rows. Any motion that
   thinks in `(path, offset)` alone cannot distinguish row 1 from
   row 2 of the same paragraph. `moveVertical` solves this in
   pixel space; sibling-path math cannot, by construction.
2. **`moveVertical` is widget-backed.** It needs
   `node.renderBox`, `node.selectable`, `editorState.selectionRects()`,
   `selectionService.getPositionInOffset`, and
   `rendererService.blockComponentBuilder(node.type)?.configuration`
   for padding. Headless, unmounted, unfocused, or pre-first-frame
   editors return `this` or `null`. Treating `this` as "in-block
   stay" without falling back produces a dead key. Treating it as
   "fall through to sibling math" is the only safe default, but that
   fallback then silently wins in every headless test — a test that
   only exercises the fallback proves nothing about the live path.
3. **Column retention.** Current `_siblingTarget` preserves character
   offset, clamped. `moveVertical` preserves screen x: it translates
   the caret offset by `(0, ±y)` and maps back with
   `getPositionForOffset`, so a short target row lands at its end.
   Neither remembers a "desired column" across a short row the way
   vim does (j over 1-char line, then j again, returns to the
   original column). Users will notice this the first time they hold
   `j` across mixed-length paragraphs. It is a follow-on, not a
   blocker — see Open Decisions.
4. **Headings, lists, code blocks.** Same wrap problem, different
   geometry: heading font sizes are body-relative multiples
   (`kHeadingFontSizeScale`), line boxes are taller, lists carry an
   icon column (`PagedListIcons`), code blocks delegate to a
   paragraph inside `CodeBlockComponentBuilder`. `moveVertical`
   reads per-node `configuration.padding`, so it adapts; offset
   clamping does not (a col-10 caret landing in an H1 wraps
   differently than in body text).
5. **Non-text blocks.** Image, equation (`kEquationBlockType`),
   and AI (`kAiBlockType`) blocks have no delta. `_siblingTarget`
   lands at offset 0 on them; `_characterTarget` at 0 / 0.
   `moveVertical` may return the neighbour `selectable` start/end
   instead. Landing a collapsed caret on an image block is the
   current behaviour; whether `j` should *skip* non-text blocks
   or *land* on them is unspecified today and must be decided, not
   discovered mid-implementation.
6. **Nested paths.** Caret inside a list child, table cell, or
   page-block nesting does not have shape `[i]`. `_siblingTarget`
   mutates only `path.last`, i.e. next sibling *within the same
   parent*, never the next top-level block. `moveVertical`'s
   fallback walks `nodePath.previous` / `next` at document level.
   These two "next" definitions diverge for nested content; the
   visual path must define cross-boundary behaviour explicitly.
7. **Zoom / transform.** `PageSurface` under Strategy B wraps the
   editor in a `Transform` (canvas matrix). `moveVertical` mixes
   `selectionRects()` (screen space) with
   `selectionService.getPositionInOffset` (also transformed). It is
   the same pair arrows already use, so it should behave identically
   under zoom — but that has only ever been proven for arrows.
   A vim-harness test must pump with a non-identity transform to
   cover it, or the plan ships a regression only visible when zoomed.
8. **RTL.** `PagedRichText.getCursorRectInPosition` and
   `getOffsetForCaret` branch on `textDirection()`. Pixel-space
   vertical scans preserve x, but offset mapping in RTL mirrors.
   No existing vim test covers RTL; without an explicit test the
   first RTL user is the test.
9. **`0`/`$` vs. display lines.** If `j`/`k` become display-line,
   users will expect `0`/`$` to go to display-line start/end
   (`TextPainter.getLineBoundary`) rather than node start/end.
   Shipping `j`/`k` display-line without touching `0`/`$` leaves
   two contradictory models in one modal (horizontal still logical,
   vertical now visual).
10. **Visual-mode head derivation.** `_extendByMotion` collapses
    the selection onto the head *before* computing the motion
    (because `moveCursorForward` collapses first). Any helper that
    needs the live selection (including `moveVertical`, which reads
    `editorState.selection` and `selectionRects()` internally) must
    run *after* that collapse, or it will compute the target from
    the anchor end of the range. The ordering is load-bearing and
    easy to invert.
11. **Analysis mode must not gain a caret.** `_navVertical` /
    `_navHorizontal` dispatch on `mode.isAnalysis` before anything
    else. Inserting display-line logic above that dispatch would
    collapse the whole-block highlight into a typing caret.
    The new helper must sit *below* the analysis branch.
12. **No count prefixes.** Vim counts (`2j`, `5l`) are not
    implemented; `VimModeController.matchSequence` only handles
    `dd`/`gg` with a 600ms window. A user who expects `j` to accept
    a count will report this plan as incomplete. Counts are not in
    this plan's scope (see Open Decisions) — but the per-key-stem
    shape (`_navVertical` steps exactly once per press) must not be
    written in a way that makes counts impossible later (e.g. no
    one-shot "jump to paragraph end" side effects baked in).
13. **Focus loss nulls the selection.** AppFlowy nulls
    `editorState.selection` on focus loss (`AppFlowyTextDriver`
    `_onFocusNodeChanged` revives it). `moveVertical` bails to
    `null` when `selectionRects()` is empty. Every vim motion
    already guards on `selection == null`; the new path must too,
    or `j` after refocus silently no-ops where sibling math would
    have recovered.
14. **First-frame / empty delta.** `_renderParagraph` may be null
    before mount; `paged_fork/paged_rich_text.dart`
    `confirmContextEnabled` loops post-frame until the keys exist.
    A `j` pressed in that window must swallow (return handled) and
    do nothing, not throw or fall through to typing `j` into the
    document.
15. **Sheet-width coupling.** Wrap points depend on the canonical
    700-wide sheet minus twice 40 padding. A widget test that
    sizes its editor differently will see different row counts and
    flake on column assertions. Tests must either pin `sheetWidth`
    (the `PageBlockComponentBuilder` test seam) or assert
    "same node, different offset" rather than exact offsets.
16. **Editor settings.** `EditorSettingsStore` persists wheel /
    pen preferences as JSON under `<appSupport>/cerebrum/editor/`.
    There is no vim-motion preference persisted anywhere. Adding a
    toggle later ("display-line j/k" vs "logical j/k") would need a
    new setting key, a migration-free default, and a read on every
    keypress — cheap if designed for now, a migration if not.

## The obvious approaches and what they cost

### A. Re-try `SelectionMoveRange.line` (looks like the "line motion")

Cost: silent name-collision trap. The enum moves to the *start or
end of the logical node* (`offset = 0` / `delta.length`), not one
row down. Wiring `j` to `moveCursorBackward/Forward(line)` would
make `j` jump to paragraph end and `k` to paragraph start —
dramatically wrong, and it would compile and mostly "work" on
single-line paragraphs, so the bug would ship.

### B. Keep sibling math but step by estimated characters-per-line

E.g. estimate `charsPerLine ≈ usableWidth / avgCharWidth` and set
`offset += charsPerLine` clamped to delta length, staying in the
same path until the paragraph end.

Cost: brittle coupling to font metrics, zoom, list indents, heading
sizes, and `kLineHeight`. Every tuning-constant change in
`page_space.dart` silently shifts motion. It also double-implements
what the paragraph already knows (its own layout) and will fight
the paged fork's `RenderParagraph` for column truth. Rejected
except as a test-simulation fallback where no layout exists
(it is then only used headlessly and never shown to users).

### C. Call `Position.moveVertical` directly and delete `_siblingTarget`

Cost: hidden coupling to the widget tree. Headless tests,
standalone drivers (`AppFlowyTextDriver` with injected vim in unit
tests), and any future non-AppFlowy `TextEditingDriver`
(`TextEditingDriver` interface explicitly abstracts the engine)
break or silently no-op. `moveVertical` also returns `this` in
some "stay" cases and a neighbour position in others, depending on
padding and `remainingMultilineHeight`; deleting the sibling
fallback loses the deterministic "next block at same offset"
contract that `vim_visual_test.dart` pins.

Alternative (chosen): a **dual-path helper**. Try layout-backed
vertical resolution first; on any layout-unavailable / same-position
/ null result, fall back to the existing sibling math. The fallback
keeps headless determinism and first-frame safety; the primary path
delivers true in-block motion live. Cost of the alternative is one
extra indirection and one explicit ordering rule (collapse before
resolve, analysis before visual). That is cheap compared to the
C-coupled breakage.

### D. Fork `Position.moveVertical` into `editor_commands.dart`

Cost: copies upstream's pixel-scan loop (~80 lines, including
`minFontSize = 1.0` scan and padding-skip maths) into the repo and
pins it to appflowy 6.0.0. Every package upgrade then requires a
manual re-diff (same burden the paged fork already carries for
`paged_rich_text.dart`). Rejected: call the upstream function,
document *why* its fallbacks were rejected, keep the repo's own
code to a thin resolver + fallback.

### E. Add `gj`/`gk` as separate keys, leave `j`/`k` logical (vim-purist)

Cost: `g` is already a pending-sequence key (`gg` via
`matchSequence` with 600ms window). `gj` requires disambiguating
"second `g` = `gg`" from "g then `j` = `gj`" within the timeout,
in both the character-shortcut and raw-key paths, plus
`_alreadyMapped` / catch-all bookkeeping so `j`/`k` are not
double-registered. Users who requested "fix `j` to stay in block"
get a new key to learn instead of the fix. Deferred: implement
`j`/`k` as display-line now; add `gj`/`gk` as a later alias only
if a user asks for logical-vs-display distinction.

## Assumptions the request did not state (defaults used in this plan)

* Each "block" is one AppFlowy node; wrapped rows inside it are
  presentation, not `\n` in the delta. Soft line breaks do not
  exist in the document model; long text wraps at sheet width.
* Scope is normal + visual modes only. Analysis review keeps
  block-granular navigation by design.
* One keypress == one step. No counts, no operators (`d` + motion),
  no `g`+motion sequences in this plan.
* `h`/`l` stay character-wise; no change to word motions `w`/`b`.
  The `h`/`l` audit in Phase 3 only checks rune-boundary correctness
  (see failure mode 10 below) — it does not redesign them.
* The canonical 700-wide sheet is authoritative for wrap.
  Tests pin it or assert "same node" rather than exact offsets.
* Desired-column memory across short rows is deferred (Open
  Decision 1). First ship preserves screen x per step (upstream
  behaviour), accepts the short-row forgetting.
* Non-text blocks are *landable* (current sibling behaviour),
  not skipped. A later decision can flip to skip without
  restructuring the helper.

## Phases

Each phase leaves the editor in a working, shippable state. No
phase requires the next to be safe to land, though later phases
build on earlier helpers.

### Phase 0 — Reproduction harness (no behaviour change)

Purpose: prove the defect exists and capture the one test harness
that later phases reuse. Nothing under `lib/` changes.

* New widget test (suggested
  `src/test/vim_wrap_navigation_test.dart`):
  pump `MaterialApp > AppFlowyEditor` with a document containing one
  long paragraph (delta long enough to wrap into ≥3 rows at the
  pinned sheet width) plus a following paragraph. Pin layout by
  using the `PageBlockComponentBuilder(sheetWidth: …)` test seam or
  a fixed 700-wide `SizedBox` with `kBaseFontSize` /
  `kBaseHorizontalPadding` from `page_space.dart`.
* Set a collapsed caret mid-first-row of the long paragraph
  (offset inside first display row), let it settle
  (`pumpAndSettle`), then invoke the *real* `j` handler obtained
  from `VimCharacterShortcuts.getCharacterShortcuts(mode)` and,
  separately, the raw-key `CommandShortcutEvent('j')` from
  `getRawKeyVimShortcuts` — exactly as `vim_visual_test.dart`
  does — and record the landing `(path, offset)`.
* Assert the *current* (defective) behaviour as the golden:
  `j` lands in the next block, `ArrowDown` (stock
  `moveCursorDownCommand`) lands in the same block at a later
  offset. This documents the divergence.
* Assert the two dispatch paths agree today (char path vs raw-key
  path land identically).

Done when: the widget test runs green on master, names the defect
nobody can miss, and needs no manual run (`flutter test
src/test/vim_wrap_navigation_test.dart`). It must also cover the
edge where the caret is on the *last* display row of the wrapped
paragraph (already at the block boundary — `j` should cross).

### Phase 1 — Display-line `j`/`k` in normal mode (the fix)

Purpose: make `j`/`k` move by display row within the current block,
crossing to the sibling block only at the first/last display row.
Normal mode only; visual mode still uses sibling math this phase.

1. Add a pure resolver in `editor_commands.dart`, e.g.
   `static ({List<int> path, int offset})? _visualLineTarget(
     EditorState editorState, {required int delta})`.
   * `delta > 0` is `j`, `< 0` is `k`.
   * Build the collapsed caret `Position(path: selection.end.path,
     offset: selection.end.offset)` and call
     `caret.moveVertical(editorState, upwards: delta < 0)`
     (import is already available via `appflowy_editor`).
   * If the result is non-null, not equal to the input position,
     and its node exists, return it. Otherwise return `null`.
   * When it returns `null`, the caller falls back to the existing
     `_siblingTarget(editorState, fromPath: …, fromOffset: …,
     delta: delta)` — unchanged code, unchanged headless semantics.
2. Rewire `_navInNormalMode` (and only its vertical branch): try
   the visual resolver first, apply a collapsed
   `Selection.collapsed` via `updateSelectionWithReason` on success,
   else call the existing `_moveToSiblingLine`. Keep the
   table-cell short-circuit (`_selectionIsInTableCell` →
   `_moveInTableCell`) strictly first.
3. Guard the whole vertical path with the existing
   `selection == null` early return and swallow semantics:
   at the first/last position with no fallback target, return
   handled (key eaten, caret unmoved) — never fall through to
   typing `j`.
4. Do not touch `_navHorizontal`, `_navVertical`'s analysis branch,
   `_moveBlockInAnalysis`, or any analysis key handlers.
5. Update the now-stale doc comment on `_moveToSiblingLine`
   (it claims `SelectionMoveRange.line` was unreliable; the real
   story is `moveVertical` is the display-line API and sibling
   math is its headless fallback).

Testability / Done when:

* Existing headless suites stay green without modification:
  `flutter test src/test/vim_visual_test.dart
  src/test/vim_table_navigation_test.dart
  src/test/vim_open_line_test.dart src/test/tmp_dd_focus_test.dart`.
  Headless, `moveVertical` is layout-less, so every `j`/`k`
  assertion there now documents the fallback path.
* A new widget test (extend the Phase 0 harness) asserts:
  (a) `j` from row 1 of a wrapped paragraph stays in the same node
  at a strictly greater offset; (b) repeated `j` walks every row
  then crosses to the next block; (c) `k` is the mirror (walks up,
  crosses at row 1); (d) `j` on the last row of the last block is
  a swallowed no-op; (e) both the character-shortcut and raw-key
  `j` handlers produce (a)–(d) identically; (f) a single-line
  paragraph behaves exactly like today (one `j` == one block).
* Explicitly verify the collapsed-before-resolve ordering is n/a
  here (normal mode is always collapsed) and write it as a comment
  so Phase 2 does not regress it.

Risks: `moveVertical`'s scan loop steps `y` by 1.0px up to
`remainingMultilineHeight`. On a very tall paragraph (e.g. a
whole-page code block) this is a linear scan per keypress —
acceptable for one step, but do not loop it (no
"move 5 rows" helper built on repeated calls without a cap).

### Phase 2 — Visual-mode extension follows display lines

Purpose: `v` + `j`/`k` must extend by display row, not by block,
or the visual selection will jump whole blocks while the normal
caret crawls rows — the two modes would teach different motion.

1. In `_extendByMotion` (`editor_commands.dart`), for the vertical
   branch, compute the head target with the same visual resolver
   used in Phase 1: collapse to `(head.path, head.offset)` *first*
   (the existing `updateSelectionWithReason` collapse stays, and
   must stay before any `moveVertical` call — see failure mode
   10), then try the visual target from the collapsed caret,
   falling back to `_siblingTarget` from `(head.path, head.offset)`
   when layout is unavailable.
2. Keep the table-cell carve-out order: head-in-cell → collapse +
   `_navInNormalMode`, never an in-cell visual scan that escapes
   the cell. Cells keep row-hopping (failure mode 6); an in-cell
   display-line refinement is Phase 4, not here.
3. For the `0`/`$` inconsistency (failure mode 9): decide in this
   phase. Recommended default — make `0`/`$` display-line aware
   via the laid-out text painter (`getLineBoundary`-equivalent
   through the crate's `RenderParagraph`) when the caret node is a
   laid-out wrapped paragraph, else fall back to node start/end.
   If that API is unavailable or unstable on the paged fork,
   ship Phase 2 without the `0`/`$` change and file it as a dated
   TODO with the exact reproduction; do not block the `j`/`k`
   fix on it. Whichever way, document the chosen semantics in the
   `_handleLineStart` / `_handleLineEnd` doc comments.
4. `_extendByWord` (`w`/`b`) is untouched — it already collapses
   then steps via `moveCursorForward/Backward(word)`.

Done when: headless visual tests stay green (fallback path), plus
a widget test asserts `v`→`j` extends the selection within the
same wrapped node (start anchored, end on a later offset, same
path) and that `v`→`j` repeated crosses the block boundary only
after the last display row, with `d`/`x` deleting the extended
range without the caret-nulling bug that `dd` documents.

### Phase 3 — `h`/`l` audit (verify, don't redesign)

Purpose: the request names all of `hjkl`. `h`/`l` are already
in-block, but there is a real rune-boundary question worth closing
while the motion code is open.

1. Audit `_characterTarget` against
   `Position.moveHorizontal` (upstream, which uses
   `delta.prevRunePosition` / `nextRunePosition`). Current code
   does raw `offset ± 1`, which splits multi-unit graphemes
   (emoji, CJK combining marks, surrogate pairs). `delta.length`
   in AppFlowy is in runes — stepping ±1 rune may still land
   mid-grapheme on complex clusters, but it never lands mid-rune.
   Compare and, if `moveHorizontal` is strictly better and layout
   available, route `h`/`l` through the same dual-path pattern
   (try `moveHorizontal`, fallback to offset math). If not, keep
   the offset math and document why.
2. Add headless tests for `h`/`l` at 0, at `delta.length`, on an
   empty paragraph, on a non-text (no-delta) node, and at a block
   boundary (forward wrap to next block, backward wrap to previous
   block's end). These pin the edge contract Phase 1 left implicit.
3. No change to `w`/`b` or catch-all typing behaviour.

Done when: `flutter test` covers `h`/`l` boundaries and the
chosen implementation is documented as one sentence in the
`_characterTarget` doc comment (why offset math vs. upstream).

### Phase 4 — Hardening: non-text blocks, zoom, RTL, tables

Purpose: each item is a separate, independently revertible commit
with its own test. Land in this order; any can be deferred without
invalidating Phases 1–2.

1. **Non-text blocks.** On a wrapped paragraph adjacent to an
   image/equation/AI block, assert `j`/`k` never lands a collapsed
   caret at an unrenderable `(path, offset)` and never throws when
   `node.delta == null`. Decide land-vs-skip (default: land, as
   today) and add the widget test. If skip wins, implement the
   skip inside `_visualLineTarget`'s fallback (walk
   `previousNodeWhere` / `next` for a selectable text node) —
   do not scatter skipping logic across callers.
2. **Zoomed canvas.** Pump the editor under a non-identity
   `Transform` (or the real `_ZoomableCanvas` matrix at scale
   ≠ 1) and assert `j` still advances within the same wrapped node
   at the same visual column. `moveVertical` reads
   `selectionRects()` in the local coordinate space; if the
   harness exposes a transform mismatch, assert the actual
   behaviour (correct vs. off-by-scale) and fix in one place.
3. **RTL.** Pump with `TextDirection.rtl` (the `PagedParagraph`
   already branches on direction) and assert `j`/`k` stay
   in-block and `h`/`l` mirror as today. `moveVertical` preserves
   x; in RTL the meaning of "same x" flips — record the expected
   landing offset explicitly so the semantics are pinned.
4. **In-cell wrapped paragraphs.** Inside a table cell with a long
   cell paragraph, decide: does `j` first step to the next display
   row inside the cell, or hop to the next row immediately
   (current `_moveInTableCell`)? Vim has no precedent; the
   conservative default keeps row-hopping and documents the gap.
   Implementing in-cell display lines later means a second visual
   attempt inside `_moveInTableCell` before the row hop — write
   that branch point now (a named helper) even if it is initially
   disabled, so the decision is visible.
5. **Focus / first-frame.** Assert `j` with `selection == null`
   and with an unmounted paragraph swallows without throwing,
   before and after the change.

Done when: each sub-item has one widget test asserting the chosen
behaviour. A sub-item may end with "documented as not-fixed" only
if it has a dated TODO and a reproduction; silent drops are not
accepted.

### Phase 5 — Help surface, docs, cleanup

Purpose: close the loops Phases 1–4 created.

1. `editor_scaffold.dart` vim-mode badge / shortcuts explainer:
   update any copy that says `j`/`k` move "between blocks" to
   "between display lines, crossing blocks at a paragraph edge".
   If a modal help (`_showVimHelp` in `reader.dart` has its own
   keys — do not conflate the two vim systems) lists `j`/`k`,
   update it in the same pass.
2. `editor_commands.dart` header comments: rewrite the
   `SelectionMoveRange.line` rationale — the current stale
   justification for sibling math must describe the dual-path
   design so the next contributor does not "simplify" it back.
3. `TODO.md` / `changelog/`: one entry describing the new motion
   model, the headless-fallback contract, and the explicit
   deferred items (desired-column memory, `gj`/`gk`, counts,
   in-cell display lines if deferred). `docs/cross-repo-contracts.md`
   is unaffected — this is a client-side navigation change, no
   wire contract moves.

Done when: a reviewer reading only the diff can state, without
running the app, which motions are display-line, which are logical,
and where the fallback lives.

## Open decisions (defaults assumed; flag if you want otherwise)

1. **Desired-column memory across short rows.** Vim remembers the
   column you left on; neither current sibling math nor
   `moveVertical` does. Default for this plan: defer (ship
   per-step x preservation). Cost to add later: store a
   preferred column `(dx or offset)` on `VimModeController`,
   clear it on explicit `h`/`l`/`0`/`$`/insert mode, re-apply on
   `j`/`k`. One controller field + two call sites. Cheap now,
   but writing it into the Phase 1 helper signature without the
   state machine would be dead code — ratify the deferral
   explicitly rather than letting it be implicit.
2. **`gj`/`gk` aliases.** Default: do not add. `j`/`k` *become*
   display-line motions (VS Code / `set wrap` semantics). Add
   `gj`/`gk` only on request; the pending-sequence disambiguation
   against `gg` is the real cost (see Approach E).
3. **`0`/`$` semantics.** Default: display-line boundaries when
   laid out, logical boundaries as fallback (Phase 2). If the
   fork cannot expose `getLineBoundary` cleanly, ship without
   them and TODO it — do not leave them silently logical with no
   note.
4. **Non-text block behaviour.** Default: land (today's behaviour).
   Skipping is a one-branch change in the fallback, but it changes
   muscle memory on image-heavy notes — decide once, test it,
   move on.
5. **Table-cell display lines.** Default: keep row-hopping (Phase
   4). In-cell wrapping already renders; whether vim should crawl
   it row-by-row before hopping is a taste call with no vim
   precedent worth emulating.

## Files expected to change

* `src/lib/ui/screens/editor/helpers/editor_commands.dart` —
  phases 1–4. The only production file that should need a logic
  change. If the plan needs a second production file, that is a
  smell — surface it in review.
* `src/lib/ui/screens/editor/controllers/vim_move_controller.dart`
  — only if Open Decision 1 is pulled forward (desired column).
  Otherwise untouched.
* `src/lib/ui/screens/editor/editor_scaffold.dart` — copy only,
  Phase 5.
* Tests: new `src/test/vim_wrap_navigation_test.dart` (Phase 0
  harness, extended in Phases 1–4); narrow additions to existing
  vim suites only for fallback-pin assertions.

## Verification (every phase)

```
flutter test src/test/vim_wrap_navigation_test.dart
flutter test src/test/vim_visual_test.dart src/test/vim_table_navigation_test.dart src/test/vim_open_line_test.dart src/test/tmp_dd_focus_test.dart
flutter analyze
```

Live manual check (once, after Phase 1): open a note containing a
paragraph long enough to wrap over ≥3 rows at the default 700-wide
sheet, enter normal mode, place the caret on display row 1
(straddling a wrap point, not at offset 0), press `j` repeatedly —
caret must walk row 2, row 3, then row 1 of the next paragraph at
roughly the same screen x, never skipping a wrapped row. Repeat
with `k` upward, with `v`+`j` (selection extends row-by-row),
with a single-line paragraph (one `j` == one block), and zoomed
(`Ctrl`+wheel) — in-block motion must hold at every zoom.
