# Cerebrum table fork

The stock `appflowy_editor` table block grows without bound: every `+` click
adds a default-width column/row defined against a 160px cell, regardless of the
page it's rendered on. On a bounded sheet (Xournal-style page) an oversized
table stops paginating gracefully — the stock builder's only answer is a
horizontally scrolling table that still overflows vertically.

This directory forks the stock table block (`table_block_component.dart`,
`table_view.dart`, `table_action_menu.dart`, `table_col_border.dart`,
`table_cell_builder.dart`) and adds two boundaries the stock block doesn't
have:

## 1. Growth caps (table stays inside its sheet)

The table reads its page's sheet geometry from `PagedTableBounds`
(`table_page_bounds.dart`), which `PageSurface` provides around the editor
stack. With the sheet bounds in hand:

- **Columns / width.** A column is only added if *all* existing columns fit
  (`colFitsInWidth`) — adding the default 160px column is the last-resort
  action, but only after trying `TableDirection.row` + wider columns. Column
  resize is clamped to `SheetWidth - sum(other columns)`. The table therefore
  never exceeds `sheetWidth - MarginH`; wide text that can't fit forces the
  ascent direction instead of growing the table (see `table_view.dart`).
- **Rows / height.** A row is only added if the current row count fits the
  *remaining* sheet height (`rowFitsInHeight` — head square ≤ pageBottom −
  tableTop − `MarginV`); otherwise the row action is a no-op and the physical
  row-growth is left to the page-boundary overflow split below.

Existing (already too large) tables still render inside the block's own
horizontal `SingleChildScrollView` as a safety net — legacy content never
breaks, it just can't be made worse.

## 2. Row-level page split (overflow)

When a table is too tall for a page, `PageSurface` reports overflow with a
measured height budget (`tableAvailableHeight = pageBottom − tableTop`);
`PagedNoteController.pushOverflow` dispatches to
`helpers/table_splitter.dart` (`splitTableAtHeight`), which cuts the table at
the last row that fits and flows the tail (`rowsLen`/cells trimmed) onto the
next page as a fresh table. The split is pure document-JSON: `TableNode =>
splitTableAtHeight({head, tail}) => TableNode` — the byte-identical row-split
machinery that `page_paginator.dart` used to have (removed with the continuous
paging build; revived here because the bounded sheet needs it again).

Caret handling: a caret inside a split table is reseated onto the head table
(cell-level re-seeding across a rebuild isn't supported by the driver), and a
caret below the split travels with `moved` to the next page.

## Why a fork instead of config?

The stock builder hardcodes defaults (160px cells) and its grow actions aren't
pluggable; the guard needs page geometry no stock hook provides. The fork keeps
the public names (`standardBlockComponentBuilderMap` spread still resolves the
stock `'table'`) and is registered later in the map, so the override is
literally `'table': CerebrumTableBlockComponentBuilder()` in
`appflowy_text_driver.dart`.

Files:

- `table_keys.dart` — forked node/attribute keys + `CellNodeHelpers` wrappers
  for inserting columns/rows (the stock classes aren't exported).
- `table_block_component.dart` — builder + widget (forks `TableBlockKeys` /
  `TableStyle` / `TableDefaults` into Cerebrum-prefixed names).
- `table_view.dart` / `table_action_menu.dart` / `table_col_border.dart` /
  `table_cell_builder.dart` — the stock interaction layer, with the guards and
  the `tableAnchorKey` / `snapshotTablePageBounds` plumbing added.
- `table_page_bounds.dart` — `PagedTableBounds` inherited widget providing the
  sheet key + snapshot helper the guards use.

Not forked (still the package's, nothing to change): cell editing via
`TableCellBlockComponentBuilder`.