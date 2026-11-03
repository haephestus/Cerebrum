import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cerebrum/ui/screens/editor/controllers/appflowy_text_driver.dart';

/// Regression tests for the analysis-highlight stopgap (§7.1(b)).
///
/// `setChunkHighlight` writes the analysis chunk's view tint into the live
/// document as the `bgColor` node attribute. Two invariants must hold:
///
/// 1. The tint must stay OUT of the undo stack (highlighting a chunk and
///    leaving analysis mode are not user edits — ctrl+z after a highlight
///    spell used to spend steps re-tinting chunks instead of undoing typing).
/// 2. The tint must stay OUT of the persisted JSON (`documentJson`), or a
///    save taken mid-analysis baked an analysis artifact into the note for
///    good — including on blocks whose highlight set was tracked per page
///    driver and no longer matches after a flow moved the blocks.
///
/// The in-memory nodes KEEP the attribute (that is what renders the tint);
/// only history and persistence are clean.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Map<String, dynamic> docJson() => {
    'id': 'note-root',
    'type': 'page',
    'children': [
      {
        'id': 'p1',
        'type': 'paragraph',
        'data': {'delta': [{'insert': 'top'}]},
      },
      {
        'id': 'list1',
        'type': 'bulleted_list',
        'data': {'delta': [{'insert': 'outer'}]},
        'children': [
          {
            'id': 'p2',
            'type': 'paragraph',
            'data': {'delta': [{'insert': 'nested'}]},
          },
        ],
      },
    ],
  };

  /// True when [key] appears on [node] or anywhere in its children subtree.
  bool jsonCarries(Map<String, dynamic> node, String key) {
    if (node.containsKey(key)) return true;
    final kids = node['children'];
    if (kids is! List) return false;
    for (final kid in kids) {
      if (kid is Map<String, dynamic> && jsonCarries(kid, key)) return true;
    }
    return false;
  }

  test('highlight tints live nodes but never reaches persisted JSON', () {
    final driver = AppFlowyTextDriver(initialDocumentJson: docJson());
    final state = driver.editorState;

    driver.setChunkHighlight(['p1', 'p2'], '0x40224200');

    // Live: the tint renders (top-level block AND nested table-cell-style
    // node — setChunkHighlight searches all levels).
    final top = state.document.root.children[0];
    final nested = state.document.root.children[1].children.first;
    expect(top.attributes[blockComponentBackgroundColor], '0x40224200');
    expect(nested.attributes[blockComponentBackgroundColor], '0x40224200');

    // Persisted: bgcolor scrubbed at every level, identity and content kept.
    final json = driver.documentJson;
    expect(jsonCarries(json, blockComponentBackgroundColor), isFalse);
    expect(json['children'][0]['id'], 'p1');
    expect(
      json['children'][0]['data']['delta'][0]['insert'],
      'top',
    );
    expect(json['children'][1]['children'][0]['id'], 'p2');
    expect(
      json['children'][1]['children'][0]['data']['delta'][0]['insert'],
      'nested',
    );
  });

  test('highlight transactions never enter the undo stack', () {
    final driver = AppFlowyTextDriver(initialDocumentJson: docJson());
    final state = driver.editorState;

    driver.setChunkHighlight(['p1'], '0x40224200');
    final undo = state.undoManager.undoStack;
    expect(undo.isEmpty, isTrue);

    // Sanity: a REAL editing transaction still records history — proving
    // the empty stack above is the recordUndo:false option at work, not the
    // undo manager being inert in tests.
    final tx = state.transaction;
    tx.updateNode(state.document.root.children[0], {'textAlign': 'center'});
    state.apply(tx);
    expect(undo.isNonEmpty, isTrue);
  });

  test('clearing a highlight also leaves no history entry', () {
    final driver = AppFlowyTextDriver(initialDocumentJson: docJson());
    final state = driver.editorState;

    driver.setChunkHighlight(['p1'], '0x40224200');
    driver.setChunkHighlight(['p1'], null);

    expect(state.document.root.children[0]
        .attributes[blockComponentBackgroundColor], isNull);
    expect(state.undoManager.undoStack.isEmpty, isTrue);
  });
}
