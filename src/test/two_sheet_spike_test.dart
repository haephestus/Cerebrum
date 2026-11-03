import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cerebrum/ui/screens/editor/controllers/vim_move_controller.dart';
import 'package:cerebrum/ui/screens/editor/helpers/editor_commands.dart';
import 'package:cerebrum/ui/screens/editor/widgets/page_space.dart';

import 'spike/two_sheet_page_block.dart';

/// SPIKE — five acceptance questions for a single-document, two-sheet page
/// block (see spike/two_sheet_page_block.dart). Every failure here that
/// cannot be fixed at this layer is the documented trigger to re-evaluate
/// Strategy B (plan §8), not a reason to patch the app harder.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final sheetHeight = 210.0;

  /// Small sheets (320x210) keep BOTH sheets inside the default 800x600 test
  /// viewport without touching the test view's metrics — a metrics reset
  /// after dispose trips a debounce bug in the package's
  /// desktop_selection_service (its timer fires on a disposed state).
  Map<String, BlockComponentBuilder> builders() => {
        ...standardBlockComponentBuilderMap,
        PageBlockKeys.type:
            SpikeTwoSheetPageBuilder(sheetWidth: 320, sheetHeight: 210),
      };

  /// Stock blocks plus the spike page block REPLACING the stock page one.
  Node para(String id, String text, String pageId) {
    final n = paragraphNode(text: text, attributes: {'pageId': pageId});
    n.id = id;
    return n;
  }

  /// 5 blocks: p0–p2 on sheet 1, p3–p4 on sheet 2.
  EditorState twoSheets() => EditorState(
        document: Document(
          root: Node(
            type: PageBlockKeys.type,
            children: [
              para('p0', 't0', 'sheet-1'),
              para('p1', 't1', 'sheet-1'),
              para('p2', 't2', 'sheet-1'),
              para('p3', 't3', 'sheet-2'),
              para('p4', 't4', 'sheet-2'),
            ],
          ),
        ),
      );

  Future<void> pumpEditor(WidgetTester tester, EditorState state) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppFlowyEditor(
            editorState: state,
            blockComponentBuilders: builders(),
            editorScrollController: EditorScrollController(
              editorState: state,
              shrinkWrap: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// AppFlowy paragraphs render as plain Flutter RichText (TextSpan only pairs
  /// awkwardly with find.text's findRichText matcher, so match by plain text
  /// directly).
  Finder textF(String t) => find.byWidgetPredicate(
        (w) => w is RichText && (w.text as TextSpan).toPlainText() == t,
      );

  Finder sheetOf(String firstBlockId) =>
      find.byKey(ValueKey('spike-$firstBlockId'));

  /// Spike serialization identical in shape to the app's
  /// `_nodeToJsonWithId`: toJson plus a restored `id` at every level.
  Map<String, dynamic> nodeWithId(Node node) {
    final map = Map<String, dynamic>.from(node.toJson());
    map['id'] = node.id;
    final kids = node.children;
    if (kids.isNotEmpty) {
      map['children'] =
          kids.map(nodeWithId).toList(growable: false);
    }
    return map;
  }

  List<Node> walkNodes(Node node, {List<Node>? out}) {
    out ??= <Node>[];
    if (node.type != 'page') out.add(node);
    for (final child in node.children) {
      walkNodes(child, out: out);
    }
    return out;
  }

  /// Mirrors the app's _restoreNodeIds: json ids copied back onto nodes.
  void restoreIds(List<dynamic> jsonNodes, List<Node> nodes) {
    for (var i = 0; i < jsonNodes.length && i < nodes.length; i++) {
      final j = jsonNodes[i];
      if (j is! Map) continue;
      if (j['id'] is String) nodes[i].id = j['id'] as String;
      final childJson = j['children'];
      if (childJson is List) restoreIds(childJson, nodes[i].children);
    }
  }

  testWidgets('1. mouse drag-select crosses the sheet boundary',
      (tester) async {
    final state = twoSheets();
    await pumpEditor(tester, state);

    final firstSheetTop = tester.getTopLeft(sheetOf('p0')).dy;
    final secondSheetTop = tester.getTopLeft(sheetOf('p3')).dy;
    expect(secondSheetTop - firstSheetTop, closeTo(sheetHeight + 24, 1.0),
        reason: 'two stacked fixed sheets with the spike vertical gap');

    // Mouse drag from the middle of the LAST sheet-1 row into the first
    // sheet-2 row. Claim under test: the selection spans nodes on both
    // sides of the custom page block's internal boundary. Stepped motion so
    // the gesture is tracked as a drag (not a tap) by the selection service.
    final from = tester.getCenter(textF('t2'));
    final to = tester.getCenter(textF('t3'));
    final gesture =
        await tester.startGesture(from, kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 60));
    final steps = 12;
    final delta = (to - from) / 12.0;
    for (var i = 1; i <= steps; i++) {
      await gesture.moveBy(delta);
      await tester.pump(const Duration(milliseconds: 40));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    final sel = state.selection;
    expect(sel, isNotNull, reason: 'the drag must produce a selection');
    expect(sel!.isCollapsed, isFalse);
    expect(sel.start.path.first, 2, reason: 'anchor on sheet 1 (p2)');
    expect(sel.end.path.first, 3, reason: 'extent on sheet 2 (p3)');
  });

  testWidgets('2. seam splice re-groups; caret and caret-rect follow',
      (tester) async {
    final state = twoSheets();
    await pumpEditor(tester, state);

    // Caret collapsed at the END of p2 — the last block of sheet 1. This is
    // the state right before "one more word would spill".
    state.updateSelectionWithReason(
      Selection.collapsed(Position(path: [2], offset: 2)),
      reason: SelectionUpdateReason.uiEvent,
    );
    await tester.pumpAndSettle();

    // THE SPIKE EXECUTOR SHAPE (plan §4, applied to a single document):
    // insert-then-delete in ONE synchronous block, same id travels,
    // caret follows its block, undo recording suppressed.
    final tx = state.transaction;
    final clone = para('p2', 't2', 'sheet-2');
    // deepCopy:false — insertNodes deep-copies by default and Node.copyWith
    // MINTS A NEW nanoid, killing the 'p2' id (re-prooves the plan's §0
    // identity finding: only construct-with-id or JSON-restore keeps
    // identity through an insert).
    tx.insertNodes([3], [clone], deepCopy: false); // immediately before p3
    tx.deleteNode(state.document.root.children[2]); // the original p2
    tx.afterSelection = Selection.collapsed(Position(path: [2], offset: 2));
    await state.apply(tx, options: const ApplyOptions(recordUndo: false));
    await tester.pumpAndSettle();

    // Document shape: [p0, p1, p2(clone, sheet-2), p3, p4], id preserved.
    final ids = walkNodes(state.document.root).map((n) => n.id).toList();
    expect(ids, ['p0', 'p1', 'p2', 'p3', 'p4']);

    // Grouping: the clone's pageId puts it at the head of sheet 2, so the
    // SECOND sheet's key is now 'spike-p2' and sheet 1 lost its last block.
    expect(textF('t2'), findsOneWidget);
    final cloneRect = tester.getRect(textF('t2'));
    final sheet2Rect = tester.getRect(sheetOf('p2'));
    final sheet1Rect = tester.getRect(sheetOf('p0'));
    expect(sheet2Rect.contains(cloneRect.center), isTrue,
        reason: 'the spilled block must render inside sheet 2');
    expect(sheet1Rect.contains(cloneRect.center), isFalse);

    // The caret followed its block and the RECT resolves in sheet-2's
    // global space — the precondition for j/k visual follow across sheets.
    expect(state.selection!.start.path, [2]);
    expect(state.selection!.start.offset, 2);
    final rects = state.selectionRects();
    expect(rects, isNotEmpty);
    final caretRect = rects.first;
    expect(sheet2Rect.contains(caretRect.center), isTrue,
        reason:
            'caret rect (global) must sit inside sheet 2, not stale sheet-1 space');
    expect(sheet1Rect.contains(caretRect.center), isFalse);
    expect(state.undoManager.undoStack.isEmpty, isTrue,
        reason: 'flow splices are suppressed from undo (plan §4)');
  });

  testWidgets('3. raw-key j crosses the boundary; caret rect is sheet-2',
      (tester) async {
    final state = twoSheets();
    await pumpEditor(tester, state);

    // Normal mode, caret mid-row on p2 (last row of sheet 1).
    state.updateSelectionWithReason(
      Selection.collapsed(Position(path: [2], offset: 1)),
      reason: SelectionUpdateReason.uiEvent,
    );
    await tester.pumpAndSettle();

    final mode = VimModeController();
    final shortcut = [
      ...EditorShortcuts.getCustomShortcuts(mode),
      ...VimCharacterShortcuts.getRawKeyVimShortcuts(mode),
    ].singleWhere((e) => e.command == 'j' && e.key.contains('raw-key'));

    final handled = await shortcut.execute(state);
    expect(handled, KeyEventResult.handled);
    await tester.pumpAndSettle();

    expect(state.selection!.start.path, [3],
        reason: "j must land the caret on sheet 2's first row");
    final rects = state.selectionRects();
    expect(rects, isNotEmpty);
    final caretRect = rects.first;
    final sheet2Rect = tester.getRect(sheetOf('p3'));
    expect(sheet2Rect.contains(caretRect.center), isTrue,
        reason: 'the caret rect must resolve against sheet-2 geometry');
  });

  testWidgets('4. tapping a block in the second sheet selects that block',
      (tester) async {
    final state = twoSheets();
    await pumpEditor(tester, state);

    await tester.tap(textF('t4'));
    await tester.pumpAndSettle();

    final sel = state.selection;
    expect(sel, isNotNull);
    expect(sel!.start.path, [4],
        reason: 'tap on sheet-2 block must route to that block node');
  });

  testWidgets('5. ids and interactions survive a save/reload round trip',
      (tester) async {
    final state = twoSheets();
    await pumpEditor(tester, state);

    // "Save": spike serialization (ids on every level like the app's
    // documentJson getter), then rebuild the EditorState from that JSON.
    final json = nodeWithId(state.document.root);

    final reloaded =
        EditorState(document: Document.fromJson({'document': json}));
    restoreIds(json['children'], reloaded.document.root.children);
    await pumpEditor(tester, reloaded);

    // Ids stable across the round trip, pageId attributes carried through.
    final ids = walkNodes(reloaded.document.root)
        .map((n) => n.id)
        .toList();
    expect(ids, ['p0', 'p1', 'p2', 'p3', 'p4']);
    expect(
      reloaded.document.root.children
          .map((n) => n.attributes['pageId'])
          .toList(),
      ['sheet-1', 'sheet-1', 'sheet-1', 'sheet-2', 'sheet-2'],
    );

    // Sheets still group correctly and tap-selection still works on page 2.
    expect(sheetOf('p0'), findsOneWidget);
    expect(sheetOf('p3'), findsOneWidget);
    await tester.tap(textF('t4'));
    await tester.pumpAndSettle();
    expect(reloaded.selection!.start.path, [4]);
  });
}
