/// Pure, deterministic table splitting for the paged editor.
///
/// When a table grows (a row's content gets taller, or rows are added) past the
/// bottom of its sheet, the page can't scroll internally — so the table is
/// split at a row boundary: the head stays on the current page and the tail
/// flows onto the next page. [splitTableAtHeight] is the measurement-free core
/// of that: given the table block JSON and a pixel budget, it emits two
/// STANDALONE valid AppFlowy tables.
///
/// Unlike the deleted continuous paginator (which estimated LINE budgets and
/// reflowed the whole document on every edit), this runs ONLY when PageSurface
/// has measured a rendered overflow, and it spends REAL pixel row heights from
/// the cells' stored `height` attributes. It never estimates a character count.
///
/// ### Why the grid invariants matter (the "vanishing table")
/// AppFlowy's `TableNode` is strict: it rejects a table (renders NOTHING) unless
///   * `children.length == colsLen * rowsLen`, and
///   * every cell carries `rowPosition` + `colPosition`, and
///   * every (col, row) coordinate in range is covered by exactly one cell.
/// The first split-table attempt re-indexed cells into a shape TableNode
/// rejected and the table silently vanished. So this splitter mirrors the
/// recovered `_splitTable` from git history (page_paginator.dart, deleted in
/// 53d53fb): the head keeps rows `[0, headRows)` verbatim (already valid), the
/// tail takes rows `[headRows, rowsLen)` with every cell's `rowPosition`
/// shifted down by `headRows` (0-based again), `colsLen`/`colPosition` and
/// per-cell width/height are untouched, and both halves are validated against
/// the grid before returning. `colsHeight` (a CACHED total pixel height of the
/// whole table) is dropped from both so each recomputes its own.
///
/// This file is intentionally free of Flutter / appflowy_editor node classes —
/// it operates on JSON-safe block maps so it is trivially unit-testable and
/// can never corrupt a live `EditorState`. The tests reconstruct every emitted
/// table through the REAL `TableNode` and assert it's accepted.
library;

typedef Block = Map<String, dynamic>;

/// Row / padding chrome around the rendered table rows inside the table block:
/// `TableCellBlockComponent` builds `Padding(top:10, left:10, bottom:4)` around
/// the scroll view, and `TableView` stacks the rows then a 28px add-row button.
/// The block's total height ≈ `colsHeight` (rows + borders) + this chrome, so
/// the splitter must reserve it from the pixel budget. Slightly conservative is
/// fine — the overflow cascade re-measures the head next frame and re-splits.
const double kTableBlockChrome = 10 + 28 + 4;

/// Split [tableBlock] so the head table fits within [availableHeight] pixels
/// (the measured space between the table's top and the sheet's bottom).
///
/// Returns `(head, tail)` — both complete, valid, standalone table block maps —
/// or null when the table can't usefully split:
///   * not a table, or has ≤ 1 row / no columns (nothing to divide);
///   * even the first row won't fit the budget (a pathological giant row —
///     leave the table whole and let the page overflow rather than loop);
///   * the whole table already fits (nothing needs to move);
///   * the children don't form a full `colsLen × rowsLen` grid (a merged/ragged
///     table we don't model — keep it atomic rather than emit an invalid table).
///
/// Row heights come from the cells' stored `height` attributes (col 0 of each
/// row — the same source `TableNode.getRowHeight` reads); a row with no stored
/// height falls back to the table's `rowDefaultHeight`.
(Block, Block)? splitTableAtHeight(Block tableBlock, double availableHeight) {
  final data = _data(tableBlock);
  final rows = _int(data['rowsLen']);
  final cols = _int(data['colsLen']);
  if (rows == null || cols == null || rows <= 1 || cols < 1) return null;
  if (availableHeight <= 0) return null;

  final rowDefaultHeight =
      double.tryParse((data['rowDefaultHeight'] ?? 40).toString()) ?? 40;
  final borderWidth =
      double.tryParse((data['borderWidth'] ?? 2).toString()) ?? 2;

  final children = (tableBlock['children'] as List?) ?? const <dynamic>[];

  // Per-row height (stored on the col-0 cell, else the default).
  double rowHeight(int row) {
    for (final cell in children) {
      if (cell is! Map) continue;
      final cd = _data(cell as Map<String, dynamic>);
      if (_int(cd['colPosition']) == 0 && _int(cd['rowPosition']) == row) {
        final h = double.tryParse((cd['height'] ?? '').toString());
        if (h != null && h > 0) return h;
      }
    }
    return rowDefaultHeight;
  }

  // Fill the budget top-down: chrome first, then whole rows (height + border).
  var used = kTableBlockChrome;
  var headRows = 0;
  for (var r = 0; r < rows; r++) {
    used += rowHeight(r) + borderWidth;
    if (used > availableHeight) break;
    headRows++;
  }
  if (headRows >= rows) return null; // fits entirely — nothing to split
  if (headRows == 0) return null; // even one row won't fit — leave it whole

  final headCells = <dynamic>[];
  final tailCells = <dynamic>[];
  for (final cell in children) {
    final rp = _int(_data(cell as Map<String, dynamic>)['rowPosition']);
    if (rp == null) return null; // malformed cell — don't risk a broken split
    if (rp < headRows) {
      headCells.add(_deep(cell));
    } else {
      final moved = _deep(cell) as Map<String, dynamic>;
      (moved['data'] as Map)['rowPosition'] = rp - headRows;
      tailCells.add(moved);
    }
  }

  // Guard the invariant explicitly: if the cell count doesn't match a full
  // cols×rows grid on either side, the source table was already irregular —
  // keep it atomic rather than emit a table AppFlowy would drop.
  if (headCells.length != cols * headRows ||
      tailCells.length != cols * (rows - headRows)) {
    return null;
  }

  final head = _deep(tableBlock) as Map<String, dynamic>;
  (head['data'] as Map)
    ..['rowsLen'] = headRows
    ..remove('colsHeight');
  head['children'] = headCells;

  final tail = _deep(tableBlock) as Map<String, dynamic>;
  (tail['data'] as Map)
    ..['rowsLen'] = rows - headRows
    ..remove('colsHeight');
  tail['children'] = tailCells;

  return (head, tail);
}

Map<String, dynamic> _data(Block block) {
  final d = block['data'];
  return d is Map<String, dynamic> ? d : <String, dynamic>{};
}

int? _int(Object? v) => v is num ? v.toInt() : (v is String ? int.tryParse(v) : null);

/// Deep clone via JSON-safe structures (blocks are plain maps/lists/scalars).
Object? _deep(Object? v) {
  if (v is Map) {
    return <String, dynamic>{
      for (final e in v.entries) e.key.toString(): _deep(e.value),
    };
  }
  if (v is List) return [for (final e in v) _deep(e)];
  return v;
}