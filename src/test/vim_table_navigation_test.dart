import 'dart:convert';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cerebrum/ui/screens/editor/controllers/vim_move_controller.dart';
import 'package:cerebrum/ui/screens/editor/helpers/editor_commands.dart'
    as commands;

/// Regression guard for vim normal-mode navigation inside a table cell.
///
/// j/k/h/l used to be swallowed inside a table: the custom motion walks
/// `path.last ± 1`, but a caret inside a cell only ever has the cell's
/// single nested paragraph as its sibling, so every key was a no-op. The
/// fix routes normal-mode movement through the package's own cell-to-cell
/// commands (the same handlers the arrow keys run) whenever the caret is
/// inside a table.
///
/// Neither raw-key nor mapped shortcuts are covered in isolation here —
/// both call the same `_navInNormalMode` shared router, so exercising the
/// mapped (IME-attached) path is sufficient.

/// A 2x2 table with texts `c{col}r{row}`, as stored by the live editor.
Map<String, Object> _tableBlock() {
  final grid = [
    [for (var r = 0; r < 2; r++) 'c0r$r'],
    [for (var r = 0; r < 2; r++) 'c1r$r'],
  ];
  final block =
      jsonDecode(jsonEncode(TableNode.fromList(grid).node.toJson()))
          as Map<String, dynamic>;
  return Map<String, Object>.from(block);
}

/// Document: paragraph('above'), 2x2 table, paragraph('below').
EditorState _stateWithTable() {
  return EditorState(
    document: Document(
      root: Node(
        type: 'document',
        children: [
          paragraphNode(text: 'above'),
          Node.fromJson(_tableBlock()),
          paragraphNode(text: 'below'),
        ],
      ),
    ),
  );
}

/// Table children are cells in column-major order (col 0 rows 0..1, then
/// col 1 rows 0..1), each cell holding one paragraph.
const _cellPath = [
  [1, 0, 0], // col 0, row 0 -> 'c0r0'
  [1, 1, 0], // col 0, row 1 -> 'c0r1'
  [1, 2, 0], // col 1, row 0 -> 'c1r0'
  [1, 3, 0], // col 1, row 1 -> 'c1r1'
];

Future<void> _press(EditorState editorState, String key) async {
  final mode = VimModeController(); // defaults to normal mode
  final shortcuts = commands.VimCharacterShortcuts.getCharacterShortcuts(mode);
  final event = shortcuts.firstWhere((e) => e.character == key);
  await event.handler(editorState);
}

void main() {
  testWidgets('j/k move between rows at the same column', (_) async {
    final editorState = _stateWithTable();

    // From col 0, row 0: 'j' lands on col 0, row 1 at the same offset.
    editorState.selection = Selection.collapsed(
      Position(path: _cellPath[0], offset: 1),
    );
    await _press(editorState, 'j');
    expect(
      editorState.selection,
      Selection.collapsed(Position(path: _cellPath[1], offset: 1)),
      reason: "'j' moves to the cell below, same column and offset",
    );

    // 'k' returns up.
    await _press(editorState, 'k');
    expect(
      editorState.selection,
      Selection.collapsed(Position(path: _cellPath[0], offset: 1)),
      reason: "'k' moves to the cell above, same column and offset",
    );
  });

  testWidgets('l/h cross cell boundaries at a cell edge', (_) async {
    final editorState = _stateWithTable();

    // At the END of col 0, row 0: 'l' lands at the START of col 1, row 0.
    editorState.selection = Selection.collapsed(
      Position(path: _cellPath[0], offset: 'c0r0'.length),
    );
    await _press(editorState, 'l');
    expect(
      editorState.selection,
      Selection.collapsed(Position(path: _cellPath[2], offset: 0)),
      reason: "'l' at a cell's end moves into the cell to the right",
    );

    // At the START of col 1, row 0: 'h' lands at the END of col 0, row 0.
    editorState.selection = Selection.collapsed(
      Position(path: _cellPath[2], offset: 0),
    );
    await _press(editorState, 'h');
    expect(
      editorState.selection,
      Selection.collapsed(Position(path: _cellPath[0], offset: 'c0r0'.length)),
      reason: "'h' at a cell's start moves into the cell to the left",
    );
  });

  testWidgets('h/l still move by character mid-cell (no boundary in reach)', (_) async {
    final editorState = _stateWithTable();

    editorState.selection = Selection.collapsed(
      Position(path: _cellPath[0], offset: 1),
    );

    await _press(editorState, 'l');
    expect(
      editorState.selection,
      Selection.collapsed(Position(path: _cellPath[0], offset: 2)),
      reason: "'l' mid-cell advances one character inside the cell",
    );

    await _press(editorState, 'h');
    expect(
      editorState.selection,
      Selection.collapsed(Position(path: _cellPath[0], offset: 1)),
      reason: "'h' mid-cell retreats one character inside the cell",
    );
  });

  testWidgets('j/k at the first/last row are swallowed without escaping the table',
      (_) async {
    final editorState = _stateWithTable();

    // 'k' on the first row: the table's own edge behavior swallows it.
    editorState.selection = Selection.collapsed(
      Position(path: _cellPath[0], offset: 0),
    );
    await _press(editorState, 'k');
    expect(
      editorState.selection,
      Selection.collapsed(Position(path: _cellPath[0], offset: 0)),
      reason: "'k' on the first row must not leave the cell above the table",
    );

    // 'j' on the last row: swallowed too — must not jump onto 'below'.
    editorState.selection = Selection.collapsed(
      Position(path: _cellPath[3], offset: 0),
    );
    await _press(editorState, 'j');
    expect(
      editorState.selection,
      Selection.collapsed(Position(path: _cellPath[3], offset: 0)),
      reason: "'j' on the last row must not leave the cell below the table",
    );
  });
}