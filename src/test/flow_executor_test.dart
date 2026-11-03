import 'dart:convert' show jsonDecode, jsonEncode;

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cerebrum/ui/screens/editor/helpers/flow_executor.dart';
import 'package:cerebrum/ui/screens/editor/widgets/page_block_component.dart'
    // Prefixed: appflowy_editor exports a same-named stock builder.
    as cerebrum_page;

/// Strategy B executor tests — the single-document flow executor against
/// the REAL page block component (one EditorState, `'page'` root, blocks
/// tagged with pageId). Sheets are small (320x210) so two fit the default
/// 800x600 test viewport without touching test metrics.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const sheetWidth = 320.0;
  const sheetHeight = 210.0;

  // ---- construction helpers ----------------------------------------------

  Node para(String id, String text, String pageId) {
    final n = paragraphNode(text: text, attributes: {'pageId': pageId});
    n.id = id;
    return n;
  }

  /// A valid table block subtree with `rows` rows of the given pixel height
  /// and `cols` columns, texts `c{col}r{row}`, id [id]. Emits via the REAL
  /// TableNode so the shape is exactly what the live editor stores, then
  /// materializes node-by-node (cells keep their paragraph children).
  Node table(String id, int cols, int rows, String pageId,
      {double rowHeight = 40}) {
    final grid = [
      for (var c = 0; c < cols; c++)
        [for (var r = 0; r < rows; r++) 'c${c}r$r'],
    ];
    final block =
        jsonDecode(jsonEncode(TableNode.fromList(grid).node.toJson()))
            as Map<String, dynamic>;
    final data = block['data'] as Map<String, dynamic>;
    data['rowDefaultHeight'] = rowHeight;
    data['borderWidth'] = 2.0;
    for (final cell in block['children'] as List) {
      (cell as Map<String, dynamic>)['data'] = {
        ...(cell['data'] as Map<String, dynamic>),
        'height': rowHeight,
      };
    }
    data['pageId'] = pageId;

    Node build(Map<String, dynamic> j) => Node(
          type: j['type'] as String,
          id: j['id'] is String ? j['id'] as String : null,
          attributes: (j['data'] as Map?)?.cast<String, dynamic>() ?? {},
          children: [
            if (j['children'] is List)
              for (final c in j['children'] as List)
                if (c is Map<String, dynamic>) build(c),
          ],
        );
    block['id'] = id;
    return build(block);
  }

  EditorState doc(List<Node> children) => EditorState(
        document: Document(
          root: Node(type: PageBlockKeys.type, children: children),
        ),
      );

  List<Node> blocks(EditorState state) => state.document.root.children.toList();

  List<String> ids(EditorState state) =>
      [for (final n in blocks(state)) n.id];

  List<String> pageIds(EditorState state) =>
      [for (final n in blocks(state)) n.attributes['pageId'] as String];

  FlowTransactionExecutor makeExecutor(
    EditorState state, {
    Set<String> inkPages = const {},
  }) {
    final ex = FlowTransactionExecutor(
      editorState: state,
      pageHasInk: inkPages.contains,
      settle: Duration.zero,
    );
    ex.debugDisableSweeps(disable: true);
    return ex;
  }

  Widget harness(EditorState state, cerebrum_page.PageBlockComponentBuilder builder,
      {bool scrollable = false}) {
    final editor = AppFlowyEditor(
      editorState: state,
      blockComponentBuilders: {
        ...standardBlockComponentBuilderMap,
        // Override the stock page entry — the paginating component.
        PageBlockKeys.type: builder,
      },
      editorScrollController:
          EditorScrollController(editorState: state, shrinkWrap: true),
    );
    return MaterialApp(
      home: Scaffold(
        body: scrollable ? SingleChildScrollView(child: editor) : editor,
      ),
    );
  }

  Finder sheetOf(String firstBlockId) =>
      find.byKey(ValueKey('cerebrum-sheet-$firstBlockId'));

  testWidgets(
      'forward push: whole move keeps ids, relabels pageId, caret follows, '
      'no undo record', (tester) async {
    // One sheet ('p1'): b0, b1, b2. Push the last block out.
    final state = doc([
      para('b0', 't0', 'p1'),
      para('b1', 't1', 'p1'),
      para('b2', 't2', 'p1'),
    ]);
    final executor = makeExecutor(state);
    await tester.pumpWidget(
      harness(
        state,
        cerebrum_page.PageBlockComponentBuilder(
          sheetWidth: sheetWidth,
          sheetHeight: sheetHeight,
          onOverflow: executor.onOverflow,
        ),
      ),
    );
    await tester.pumpAndSettle();

    state.updateSelectionWithReason(
      Selection.collapsed(Position(path: [2], offset: 2)),
      reason: SelectionUpdateReason.uiEvent,
    );
    await tester.pumpAndSettle();

    executor.onOverflow('p1', 2);
    await tester.pumpAndSettle();
    final sheetCount = tester.widgetList(
        find.byWidgetPredicate((w) =>
            w.key is ValueKey && (w.key as ValueKey).value is String &&
            RegExp(r'^cerebrum-sheet-').hasMatch((w.key as ValueKey).value as String))).length;

    expect(ids(state), ['b0', 'b1', 'b2']);
    expect(pageIds(state), ['p1', 'p1', 'p2'], reason: 'b2 relabeled p2');
    expect(sheetCount, 2, reason: 'exactly two sheets');
    expect(sheetOf('b0'), findsOneWidget);
    expect(sheetOf('b2'), findsOneWidget,
        reason: 'b2 now heads the second sheet');
    expect(state.selection!.start.path, [2], reason: 'caret followed its block');
    expect(state.selection!.start.offset, 2);
    expect(state.undoManager.undoStack.isEmpty, isTrue,
        reason: 'flow splices suppressed from undo');
  });

  testWidgets(
      'forward push: table split pre-splits, head keeps id, tail gets a '
      'fresh id on the next page', (tester) async {
    // budget: chrome (10+28+4≈42) + one 40px row fits in ~90; two rows don't.
    const budget = 90.0;
    // 12px rows keep the INITIAL layout (para + full table + para) inside
    // one 210px sheet so only the MANUAL overflow report below drives the
    // split.
    final state = doc([
      para('b0', 't0', 'p1'),
      table('T', 2, 3, 'p1', rowHeight: 12),
      para('after', 'tail text', 'p1'),
    ]);
    final executor = makeExecutor(state);
    await tester.pumpWidget(harness(
      state,
      cerebrum_page.PageBlockComponentBuilder(
        sheetWidth: sheetWidth,
        sheetHeight: sheetHeight,
        onOverflow: executor.onOverflow,
      ),
    ));
    await tester.pumpAndSettle();

    executor.onOverflow('p1', 1, tableAvailableHeight: budget);
    await tester.pumpAndSettle();

    // Shapes: [b0, headT, tailT, after].
    final children = blocks(state);
    expect(children.length, 4, reason: 'table split into two standalone rows');
    expect(children[1].type, 'table');
    expect(children[2].type, 'table');
    expect(children[1].id, 'T', reason: 'head half KEEPS the source id');
    expect(children[2].id, isNot('T'), reason: 'tail half gets a fresh id');
    expect(children[3].id, 'after');
    expect((children[1].attributes['rowsLen'] as int), 1,
        reason: 'head keeps row 0');
    expect((children[2].attributes['rowsLen'] as int), 2,
        reason: 'tail carries rows 1-2');
    expect(children[1].attributes['pageId'], 'p1');
    expect(children[2].attributes['pageId'], 'p2',
        reason: 'tail travels to the target page');
    expect(state.selection, isNull,
        reason: 'caret was not in the table; input left untouched');
  });

  testWidgets(
      'backward pull: stats pair drives the head up, filler dropped, '
      'caret follows', (tester) async {
    // Receiver 'p1' holds ONLY the trailing filler; donor 'p2': b1, b2.
    final state = doc([
      para('b0', 't0', 'p1'),
      para('b1', 't1', 'p2'),
      para('b2', 't2', 'p2'),
    ]);
    final executor = makeExecutor(state);
    await tester.pumpWidget(harness(state,
        cerebrum_page.PageBlockComponentBuilder(
          sheetWidth: sheetWidth,
          sheetHeight: sheetHeight,
          onOverflow: executor.onOverflow,
          onUnderfill: executor.onUnderfill,
        )));
    await tester.pumpAndSettle();

    state.updateSelectionWithReason(
      Selection.collapsed(Position(path: [1], offset: 2)),
      reason: SelectionUpdateReason.uiEvent,
    );
    await tester.pumpAndSettle();

    executor.onUnderfill('p1', 150.0, null);
    executor.onUnderfill('p2', 0.0, 30.0);
    executor.debugSweep();
    await tester.pumpAndSettle();

    // The filler-drop rule only fires when the trailing filler does NOT
    // exhaust the receiver — a 1-block page keeps its filler (Strategy A
    // parity), so b0 stays and b1 lands AFTER it.
    expect(ids(state), ['b0', 'b1', 'b2'], reason: 'b1 pulled up to receiver');
    expect(pageIds(state), ['p1', 'p1', 'p2'],
        reason: 'b1 relabeled to the receiver page');
    expect(sheetOf('b0'), findsOneWidget);
    expect(sheetOf('b2'), findsOneWidget, reason: 'donor sheet keeps b2');
    expect(state.selection!.start.path, [1], reason: 'caret followed b1 up');
    expect(state.selection!.start.offset, 2);
  });

  testWidgets(
      'backward pull: inked single-block donor regenerates a tagged empty '
      'paragraph; inked blank donor triggers no pull', (tester) async {
    // (a) Receiver 'p1' has slack; DONOR 'p2' is an inked page whose only
    // text block holds text. The pull moves the head up; the inked donor
    // survives with a fresh empty paragraph tagged on its OWN pageId.
    final state = doc([
      para('b0', 't0', 'p1'),
      para('b1', 't1', 'p2'),
    ]);
    final executor = makeExecutor(state, inkPages: {'p2'});
    await tester.pumpWidget(harness(
      state,
      cerebrum_page.PageBlockComponentBuilder(
        sheetWidth: sheetWidth,
        sheetHeight: sheetHeight,
        onOverflow: executor.onOverflow,
        onUnderfill: executor.onUnderfill,
      ),
    ));
    await tester.pumpAndSettle();

    executor.onUnderfill('p1', 150.0, null);
    executor.onUnderfill('p2', 0.0, 30.0);
    executor.debugSweep();
    await tester.pumpAndSettle();

    final pageIdsNow = pageIds(state);
    expect(pageIdsNow.toSet(), equals({'p1', 'p2'}),
        reason: 'inked donor keeps its own pageId');
    expect(pageIdsNow.where((e) => e == 'p2').length, 1,
        reason: 'exactly one (fresh, empty) para holds the donor page');
    final freshPara =
        blocks(state).firstWhere((n) => n.attributes['pageId'] == 'p2');
    expect(freshPara.id, isNot('b1'), reason: 'the para is freshly minted');
    final blankIds = List<String>.from(ids(state));

    // (b) An inked BLANK donor (only an empty paragraph) must never be
    // pulled — the pull would regenerate the filler forever. Sweep again:
    // the document holds still.
    executor.onUnderfill(
        pageIdsNow.first, 150.0, 30.0); // stats re-pair (simulated re-measure)
    executor.onUnderfill(pageIdsNow.last, 100.0, 30.0);
    executor.debugSweep();
    await tester.pumpAndSettle();
    expect(ids(state), blankIds, reason: 'inked-blank donor pair is a no-op');
  });

  testWidgets(
      'backward pull: table donor head never travels; sweep is a no-op',
      (tester) async {
    final state = doc([
      para('b0', 't0', 'p1'),
      table('T', 2, 2, 'p2'),
      para('b2', 't2', 'p2'),
    ]);
    final executor = makeExecutor(state);
    await tester.pumpWidget(harness(state,
        cerebrum_page.PageBlockComponentBuilder(
          sheetWidth: sheetWidth,
          sheetHeight: sheetHeight,
          onOverflow: executor.onOverflow,
          onUnderfill: executor.onUnderfill,
        )));
    await tester.pumpAndSettle();

    executor.onUnderfill('p1', 150.0, null);
    executor.onUnderfill('p2', 100.0, 80.0);
    executor.debugSweep();
    await tester.pumpAndSettle();

    expect(ids(state), ['b0', 'T', 'b2'],
        reason: 'a table donor head never pulls backward');
    expect(pageIds(state), ['p1', 'p2', 'p2']);
  });
}
