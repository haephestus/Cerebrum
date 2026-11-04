import 'dart:convert' show jsonDecode, jsonEncode;

import 'package:flutter_test/flutter_test.dart';
import 'package:cerebrum/ui/screens/editor/controllers/paged_note_controller.dart';
import 'package:cerebrum/ui/screens/editor/helpers/strategy_b_notes.dart';

/// Headless smoke for the production path the flag flip makes real: a
/// legacy note loads through [PagedNoteController.fromNote] (which migrates
/// to B), the save side emits a B-shape pages list, and that list decodes
/// back to the same blocks. The JSON-compare-through-encode is deliberate —
/// [fromPages] normalizes containers, so identity/typed equality lies.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('legacy note -> fromNote -> toPagesJson -> fromPages round trip', () {
    final legacyChildren = [
      {
        'type': 'paragraph',
        'data': {
          'delta': [
            {'insert': 'chapter body'},
          ],
        },
      },
      {
        'type': 'heading',
        'data': {'delta': [{'insert': 'Title'}], 'level': 2},
      },
    ];
    final legacy = [
      {
        'page_id': 'p1',
        'page_index': 0,
        'document': {
          'type': 'page',
          'children': legacyChildren,
        },
        'ink': [],
      },
    ];
    final controller = PagedNoteController.fromNote(pages: legacy);
    expect(controller.pages.length, 1, reason: 'one document under B');

    final out = controller.toPagesJson();
    expect(isBShape(out), true, reason: 'the flip saves B shape');
    expect(out, hasLength(1));
    expect((out[0]['ink'] as Map).values, everyElement(isList));

    final decoded = fromPages(out);
    // Load mints block ids (Node.fromJson) and stamps pageIds — compare the
    // shape without them; those two are invariants guaranteed elsewhere
    // (stampPageIds tests, executor tests).
    String shapeOf(List<dynamic> children) => jsonEncode([
          for (final child in children)
            (jsonDecode(jsonEncode(child)) as Map<String, dynamic>)..remove('id'),
        ]);
    expect(
      shapeOf(decoded.document['children'] as List),
      shapeOf([
        for (final child in legacyChildren)
          {
            ...child,
            'data': {
              ...child['data'] as Map,
              'pageId': 'p1',
            },
          },
      ]),
      reason: 'blocks survive load -> save -> decode unchanged',
    );
    controller.dispose();
  });
}
