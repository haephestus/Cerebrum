import 'dart:convert';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cerebrum/ui/screens/editor/helpers/table_splitter.dart' as ts;

/// Regression guard for table splitting in the paged editor. The first attempt
/// at splitting tables re-indexed cells into a shape AppFlowy's `TableNode`
/// rejects — it renders nothing (the "vanishing table"). These tests
/// reconstruct every table the splitter emits through the REAL `TableNode` and
/// assert it's accepted, plus that no rows/columns/text are lost across the
/// split, plus that the head actually fits its pixel budget.

/// True when `TableNode` accepted the table: on rejection it clears its internal
/// cell grid, so colsLen/rowsLen come back 0.
bool _accepted(Map<String, dynamic> block) {
  final tn = TableNode(node: Node.fromJson(Map<String, Object>.from(block)));
  return tn.colsLen > 0 && tn.rowsLen > 0;
}

/// Every cell's text in a table (unordered) — a row-split re-partitions the
/// grid, so conservation is checked as a multiset, not a fixed sequence.
List<String> _cellTexts(Map<String, dynamic> block) {
  final tn = TableNode(node: Node.fromJson(Map<String, Object>.from(block)));
  return [
    for (var c = 0; c < tn.colsLen; c++)
      for (var r = 0; r < tn.rowsLen; r++)
        tn.getCell(c, r).children.first.delta?.toPlainText() ?? '',
  ];
}

/// A valid table block with `rows` rows of the given pixel height and
/// `cols` columns, texts `c{col}r{row}`. Emits via the real `TableNode` so the
/// data shape is exactly what the live editor stores.
Map<String, dynamic> makeTable(
  int cols,
  int rows, {
  double rowHeight = 40,
  double borderWidth = 2,
}) {
  final grid = [
    for (var c = 0; c < cols; c++)
      [for (var r = 0; r < rows; r++) 'c${c}r$r'],
  ];
  final block =
      jsonDecode(jsonEncode(TableNode.fromList(grid).node.toJson()))
          as Map<String, dynamic>;
  final data = block['data'] as Map<String, dynamic>;
  data['rowDefaultHeight'] = rowHeight;
  data['borderWidth'] = borderWidth;
  // Give every cell its real stored height so the splitter reads pixel heights.
  final children = block['children'] as List;
  for (final cell in children) {
    (cell as Map<String, dynamic>)['data'] = {
      ...(cell['data'] as Map<String, dynamic>),
      'height': rowHeight,
    };
  }
  return block;
}

void main() {
  test('a too-tall table splits into valid, accepted tables', () {
    final block = makeTable(2, 5);
    // Budget fits chrome + 3 rows ⇒ head 3, tail 2.
    final split = ts.splitTableAtHeight(
      block,
      ts.kTableBlockChrome + 3 * (40 + 2),
    );

    expect(split, isNotNull, reason: 'the table should split');
    final (head, tail) = split!;
    expect(_accepted(head), isTrue,
        reason: 'every split half must be a valid AppFlowy table');
    expect(_accepted(tail), isTrue);

    final tn = TableNode(node: Node.fromJson(Map<String, Object>.from(head)));
    expect(tn.colsLen, 2, reason: 'column count is preserved in the head');
    expect(tn.rowsLen, 3);
    expect((head['children'] as List).length, tn.colsLen * tn.rowsLen,
        reason: 'children == colsLen * rowsLen (TableNode invariant)');
    final tt = TableNode(node: Node.fromJson(Map<String, Object>.from(tail)));
    expect(tt.rowsLen, 2);
    expect((tail['children'] as List).length, tt.colsLen * tt.rowsLen);
    expect(tn.rowsLen + tt.rowsLen, 5, reason: 'no rows lost across the split');
  });

  test('head fits the pixel budget; tail is surjective on row positions', () {
    final block = makeTable(2, 8, rowHeight: 60, borderWidth: 2);
    const budget = ts.kTableBlockChrome + 2 * (60 + 2); // holds 2 rows
    final split = ts.splitTableAtHeight(block, budget)!;
    final (head, tail) = split;

    final headTn =
        TableNode(node: Node.fromJson(Map<String, Object>.from(head)));
    expect(headTn.rowsLen, 2);
    // Every cell keeps its original stored height (pixels are not re-estimated).
    for (var r = 0; r < headTn.rowsLen; r++) {
      expect(headTn.getRowHeight(r), 60);
    }

    // Tail rows are re-indexed 0-based and every position is covered exactly once.
    final tailTn =
        TableNode(node: Node.fromJson(Map<String, Object>.from(tail)));
    expect(tailTn.rowsLen, 6);
    final seen = <(int, int)>{};
    for (final c in tail['children'] as List) {
      final cd = (c as Map)['data'] as Map;
      final col = (cd['colPosition'] as num).toInt();
      final row = (cd['rowPosition'] as num).toInt();
      expect(seen.add((col, row)), isTrue,
          reason: 'no duplicate (col,row) in the tail');
      expect(col, inInclusiveRange(0, 1));
      expect(row, inInclusiveRange(0, 5));
    }
    expect(seen.length, 12, reason: 'every tail cell covered exactly once');
  });

  test('split conserves every cell\'s text (no loss/duplication)', () {
    final block = makeTable(3, 6);
    final before = _cellTexts(block)..sort();
    final split = ts.splitTableAtHeight(
      block,
      ts.kTableBlockChrome + 2 * (40 + 2),
    );
    expect(split, isNotNull);
    final (head, tail) = split!;
    final after = [..._cellTexts(head), ..._cellTexts(tail)]..sort();
    expect(after, before, reason: 'every cell survives the split exactly once');
  });

  test('a single-row table is never split (stays atomic)', () {
    final block = makeTable(3, 1);
    expect(
      ts.splitTableAtHeight(block, ts.kTableBlockChrome),
      isNull,
      reason: 'nothing to split',
    );
  });

  test('a table whose first row alone exceeds the budget is left whole', () {
    final block = makeTable(2, 4, rowHeight: 300);
    expect(ts.splitTableAtHeight(block, 10), isNull,
        reason: 'splitting would emit a head that still cannot fit → loop');
  });

  test('a table splitting repeatedly stays valid at every step', () {
    var block = makeTable(2, 12);
    const budget = ts.kTableBlockChrome + 2 * (40 + 2); // ~2 rows/page

    var totalRows = 0;
    var pieces = 0;
    while (true) {
      final split = ts.splitTableAtHeight(block, budget);
      if (split == null) {
        totalRows += (block['data'] as Map)['rowsLen'] as int;
        pieces++;
        break;
      }
      final (head, tail) = split;
      expect(_accepted(head), isTrue);
      final headTn =
          TableNode(node: Node.fromJson(Map<String, Object>.from(head)));
      totalRows += headTn.rowsLen;
      pieces++;
      expect(pieces, lessThan(20), reason: 'must terminate');
      block = tail;
    }
    expect(totalRows, 12, reason: 'all rows survive repeated splitting');
  });

  test('a table with no stored heights falls back to rowDefaultHeight', () {
    final block = makeTable(2, 5);
    final data = block['data'] as Map<String, dynamic>;
    data['rowDefaultHeight'] = 20; // smaller default, cells have no real height
    // makeTable stores a real `height` on every cell — strip them so the
    // rowDefaultHeight fallback is actually what gets exercised.
    for (final cell in block['children'] as List) {
      ((cell as Map<String, dynamic>)['data'] as Map).remove('height');
    }
    final split = ts.splitTableAtHeight(
      block,
      ts.kTableBlockChrome + 3 * (20 + 2),
    );
    expect(split, isNotNull);
    final (head, _) = split!;
    expect(
      TableNode(node: Node.fromJson(Map<String, Object>.from(head))).rowsLen,
      3,
    );
  });
}