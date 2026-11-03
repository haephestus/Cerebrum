import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cerebrum/ui/screens/editor/helpers/page_ink_surface.dart';
import 'package:cerebrum/ui/screens/editor/helpers/page_ink_store.dart';
import 'package:cerebrum/ui/screens/editor/widgets/drawing_layer.dart';
import 'package:cerebrum/ui/screens/editor/widgets/page_block_component.dart'
    as cerebrum_page;

/// The per-sheet ink overlay: renders a drawing layer keyed by each run's
/// pageId, seeded from the ink store, with pointer routing gated on
/// drawingEnabled.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const sheetWidth = 320.0;
  const sheetHeight = 210.0;
  const drawnSketch = {
    'lines': [
      {
        'points': [
          {'x': 10.0, 'y': 20.0},
          {'x': 60.0, 'y': 80.0},
        ],
        'color': 0xFF000000,
        'width': 3.0,
      },
    ],
  };

  Node para(String id, String text, String pageId) {
    final n = paragraphNode(text: text, attributes: {'pageId': pageId});
    n.id = id;
    return n;
  }

  EditorState doc() => EditorState(
        document: Document(
          root: Node(
            type: PageBlockKeys.type,
            children: [
              para('b0', 't0', 'p1'),
              para('b1', 't1', 'p2'),
            ],
          ),
        ),
      );

  testWidgets('ink overlay renders per sheet and seeds from the store',
      (tester) async {
    final store = PageInkStore();
    store.setInk('p2', [drawnSketch]);
    final surface = PageInkSurface(store: store);
    final state = doc();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppFlowyEditor(
            editorState: state,
            blockComponentBuilders: {
              ...standardBlockComponentBuilderMap,
              PageBlockKeys.type: cerebrum_page.PageBlockComponentBuilder(
                sheetWidth: sheetWidth,
                sheetHeight: sheetHeight,
                inkSurface: surface,
              ),
            },
            editorScrollController:
                EditorScrollController(editorState: state, shrinkWrap: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Two sheets (p1 [b0], p2 [b1]) each get one ink layer.
    expect(find.byType(NoteDrawingLayer), findsNWidgets(2));

    // The p2 sheet's notifier must be seeded with the stored stroke.
    final notifier = surface.notifierFor('p2');
    expect(notifier.currentSketch.lines, hasLength(1));

    // p1 has no stored ink → empty sketch.
    final notifier1 = surface.notifierFor('p1');
    expect(notifier1.currentSketch.lines, isEmpty);

    // Text layer absorbs pointers only in drawing mode — checked per sheet.
    bool sheetAbsorbs(String sheetKey) => tester.widget<AbsorbPointer>(
          find.descendant(
            of: find.byKey(ValueKey('cerebrum-sheet-$sheetKey')),
            matching: find.byType(AbsorbPointer),
          ),
        ).absorbing;
    expect(sheetAbsorbs('b0'), isFalse);
    expect(sheetAbsorbs('b1'), isFalse);

    surface.setDrawingEnabled(true);
    await tester.pumpAndSettle();
    expect(sheetAbsorbs('b0'), isTrue);
    expect(sheetAbsorbs('b1'), isTrue);
    surface.dispose();
  });
}
