import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cerebrum/ui/screens/editor/controllers/vim_move_controller.dart';
import 'package:cerebrum/ui/screens/editor/helpers/editor_commands.dart'
    as commands;

/// Temporary regression test for the `dd` null-selection bug.
///
/// AppFlowy 6.0's `deleteNode` transaction leaves `editorState.selection ==
/// null` (it does not reposition the caret), and every vim motion guards on
/// `selection == null`, so after `dd` the note felt "unfocused" — no caret, no
/// j/k — until a click. These tests pin the fix in `_handleDeleteLine` that
/// restores a collapsed caret on the surviving block.
///
/// NOTE: whole-block selection setup (`node.selectable`) is NOT available in a
/// headless EditorState — `selectable` is null without a render tree — so the
/// tests drive dd through a collapsed caret, which is the realistic in-app
/// shape anyway.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  EditorState stateWith(int n) {
    return EditorState(
      document: Document(
        root: Node(
          type: 'document',
          children: [
            for (var i = 0; i < n; i++) paragraphNode(text: 'line$i'),
          ],
        ),
      ),
    );
  }

  Future<void> pressD(
    EditorState editorState,
    VimModeController mode,
  ) async {
    final shortcuts = commands.VimCharacterShortcuts.getCharacterShortcuts(
      mode,
    );
    final d = shortcuts.firstWhere((s) => s.character == 'd');
    final handled = await d.handler(editorState);
    expect(handled, isTrue);
  }

  Future<VimModeController> pressDD(EditorState es) async {
    final mode = VimModeController(); // normal mode, SHARED across both d's
    await pressD(es, mode); // first d: swallowed (pending operator)
    await pressD(es, mode); // second d: delete
    return mode;
  }

  test('dd on the middle block restores the caret on the block that moves up',
      () async {
    final es = stateWith(3);
    es.updateSelectionWithReason(
      Selection.collapsed(Position(path: [1], offset: 2)),
      reason: SelectionUpdateReason.uiEvent,
    );

    await pressDD(es);

    expect(es.document.root.children.length, 2);
    expect(es.selection, isNotNull,
        reason: 'after dd the selection must be valid for j/k to work');
    expect(es.selection!.isCollapsed, isTrue,
        reason: 'the restored caret must be collapsed, not a whole-block range');
    expect(es.selection!.end.path.first, 1,
        reason: 'caret must rest on the block that shifts into the deleted '
            'block\'s index');
  });

  test('dd on the last block leaves a valid selection', () async {
    final es = stateWith(3);
    es.updateSelectionWithReason(
      Selection.collapsed(Position(path: [2], offset: 2)),
      reason: SelectionUpdateReason.uiEvent,
    );

    await pressDD(es);

    expect(es.document.root.children.length, 2);
    expect(es.selection, isNotNull,
        reason: 'deleting the last block must not null the selection');
    expect(es.selection!.end.path.first, 1,
        reason: 'last-block delete must clamp onto the new last survivor');
  });

  test('dd on the only block leaves the caret valid', () async {
    final es = stateWith(1);
    es.updateSelectionWithReason(
      Selection.collapsed(Position(path: [0], offset: 2)),
      reason: SelectionUpdateReason.uiEvent,
    );

    await pressDD(es);

    expect(es.document.root.children.length, 1,
        reason: 'AppFlowy must leave an empty paragraph behind');
    expect(es.selection, isNotNull,
        reason: 'deleting the only block must not null the selection');
    expect(es.selection!.end.path.first, 0);
  });
}

// Legacy note kept for history: the earlier version of this file set up
// whole-block selections via `node.selectable!` — that crashes headlessly
// because `selectable` exists only once a render tree is attached. The
// collapsed-caret path exercises the same _handleDeleteLine code.