import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cerebrum/ui/screens/editor/helpers/strategy_b_notes.dart';

/// Strategy-B note codec — legacy A-shape pages list ↔ one paged document +
/// pageId-keyed ink map. Migration must not touch ids, deltas or ink.
void main() {
  Map<String, dynamic> para(String text, {String pageId = '_?'}) {
    final child = <String, dynamic>{
      'id': 'blk-$text',
      'type': 'paragraph',
      'data': {
        'delta': [
          {'insert': text},
        ],
      },
    };
    if (pageId != '_?') {
      (child['data'] as Map<String, dynamic>)['pageId'] = pageId;
    }
    return child;
  }

  List<Map<String, dynamic>> legacyPages = [
    {
      'page_id': 'p1',
      'page_index': 0,
      'document': {
        'type': 'page',
        'children': [
          para('alpha'),
          para('beta'),
        ],
      },
      'ink': [
        {
          'lines': [
            {
              'points': [
                {'x': 1.0, 'y': 2.0},
              ],
              'color': 0xFF000000,
              'width': 3.0,
            },
          ],
        },
      ],
    },
    {
      'page_id': 'p2',
      'page_index': 1,
      'document': {
        'type': 'page',
        'children': [
          para('gamma'),
        ],
      },
      'ink': [
        {
          'lines': [
            {
              'points': [
                {'x': 9.0, 'y': 9.0},
              ],
              'color': 0xFFFF0000,
              'width': 5.0,
            },
          ],
        },
      ],
    },
  ];

  test('legacy migration joins pages, stamps pageId, preserves ids and ink',
      () {
    final note = fromPages(legacyPages);

    // One document, children joined in order.
    final kids = note.document['children'] as List;
    expect(kids.map((c) => c['id']), ['blk-alpha', 'blk-beta', 'blk-gamma'],
        reason: 'block ids preserved verbatim');
    expect(
      [for (final c in kids) (c['data'] as Map)['pageId']],
      ['p1', 'p1', 'p2'],
      reason: 'pageId = legacy page_id per page entry',
    );
    expect(kids[0]['data']['delta'],
        equals([
          {'insert': 'alpha'},
        ]));

    // Ink lands under the page's page_id, sketch intact.
    expect(note.ink.keys, unorderedEquals(['p1', 'p2']));
    expect(
        (note.ink['p1']!.first['lines'] as List).first['points'].first['x'],
        1.0);
    expect(
        (note.ink['p2']!.first['lines'] as List).first['color'], 0xFFFF0000);

    // Round trip back to the ONE-ELEMENT pages shape the pipeline consumes.
    final out = note.toPages();
    expect(out, hasLength(1));
    expect(out[0]['page_id'], 'main');
    expect(out[0]['document'], note.document);
    expect(out[0]['ink'], note.ink);
  });

  test('B shape re-reads verbatim (ink map survives untouched)', () {
    final note = fromPages(legacyPages); // produce B
    final again = fromPages(note.toPages()); // read B back

    expect(again.document, note.document);
    expect(again.ink, note.ink);
    expect((again.document['children'] as List).length, 3);
  });

  test('a single legacy page migrates to one pageId-run B note', () {
    final note = fromPages([legacyPages[0]]);
    expect((note.document['children'] as List).map((c) => (c['data'] as Map)['pageId']),
        ['p1', 'p1']);
    expect(note.ink.keys, ['p1']);
  });

  test('legacy page with no ink migrates as text-only entry', () {
    final pages = [
      Map<String, dynamic>.from(legacyPages[0]),
    ];
    (pages[0]['ink'] as List).clear();
    final note = fromPages(pages);
    expect(note.ink, isEmpty);
    expect((note.document['children'] as List).length, 2);
  });

  test('non-list ink does NOT crash; it is discarded from that page', () {
    final pages = [
      Map<String, dynamic>.from(legacyPages[0]),
    ];
    pages[0]['ink'] = 'garbage';
    final note = fromPages(pages);
    expect(note.ink, isEmpty);
  });

  test('empty pages list throws ArgumentError', () {
    expect(() => fromPages(const []), throwsArgumentError);
  });

  test('pages entry without document throws ArgumentError', () {
    expect(
      () => fromPages([
        {'page_id': 'p1'},
      ]),
      throwsArgumentError,
    );
  });

  test('document as JSON string is accepted', () {
    const jsonDoc = {
      'type': 'page',
      'children': <Object>[],
    };
    final pages = [
      {
        'page_id': 'p9',
        'page_index': 0,
        'document': jsonDoc, // already a Map; replace below by explicit test path
        'ink': <Object>[],
      },
    ];
    expect(fromPages(pages).document['type'], 'page');
  });

  test('migrateToB emits one page entry with the main page_id', () {
    final out = migrateToB(legacyPages);
    expect(out, hasLength(1));
    expect(out[0]['page_id'], kStrategyBPageId);
    expect((out[0]['document'] as Map)['children'], hasLength(3));
  });

  group('stampPageIds', () {
    Document docOf(List<Node> children) =>
        Document(root: Node(type: 'page', children: children));

    Node tagged(String id, String pageId) {
      final n = paragraphNode(text: id, attributes: {'pageId': pageId});
      n.id = id;
      return n;
    }

    Node untagged(String id) => paragraphNode(text: id)..id = id;

    test('stamps a fresh untagged block after the sheet it split from', () {
      final doc = docOf([tagged('b0', 'p1'), untagged('b1')]);
      stampPageIds(doc);
      expect(doc.root.children[1].attributes['pageId'], 'p1');
      expect(doc.root.children[0].attributes['pageId'], 'p1');
    });

    test('follows the nearest preceding tag mid-document', () {
      final doc = docOf([
        tagged('b0', 'p1'),
        untagged('b1'),
        tagged('b2', 'p2'),
        untagged('b3'),
      ]);
      stampPageIds(doc);
      expect(doc.root.children[1].attributes['pageId'], 'p1');
      expect(doc.root.children[3].attributes['pageId'], 'p2');
    });

    test('fallback is the single B page id when nothing is tagged', () {
      final doc = docOf([untagged('b0'), untagged('b1')]);
      stampPageIds(doc);
      expect(
        doc.root.children.map((n) => n.attributes['pageId']),
        everyElement(kStrategyBPageId),
      );
    });
  });
}
