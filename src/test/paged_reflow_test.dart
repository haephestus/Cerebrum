import 'package:cerebrum/ui/screens/editor/controllers/paged_note_controller.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
/// Regression guard for the BACKWARD reflow (idle-gated pull sweep).
///
/// Pull must be a faithful block move: type, attributes (heading levels),
/// delta text and stable ids survive the serialize → rebuild round trip the
/// sweep performs on both pages. It once rendered a pulled H1 as a plain
/// body paragraph on the receiving page.
///
/// Runs inside [fakeAsync] because the sweep is only reachable through the
/// idle-settle timer (the physical harness measured real frames; here the
/// controller API is driven directly).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('pull moves the donor head with type and attributes intact', () {
    fakeAsync((async) {
      final c = PagedNoteController.fromNote(pages: [
        {
          'page_id': 'p1',
          'page_index': 0,
          'document': {
            'type': 'page',
            'children': [
              {
                'type': 'paragraph',
                'data': {
                  'delta': [
                    {'insert': 'list item one'},
                  ],
                },
              },
              {
                'type': 'numbered_list',
                'data': {
                  'delta': [
                    {'insert': 'short'}
                  ],
                  'number': 1,
                },
              },
            ],
          },
        },
        {
          'page_id': 'p2',
          'page_index': 1,
          'document': {
            'type': 'page',
            'children': [
              {
                'type': 'heading',
                'data': {
                  'delta': [
                    {'insert': 'Training and splitting data'}
                  ],
                  'level': 1,
                },
              },
              {
                'type': 'paragraph',
                'data': {
                  'delta': [
                    {'insert': 'Splitting data according to traing and test.'},
                  ],
                },
              },
            ],
          },
        },
      ]);

      // Receiver page 0 has 500ish doc px free, donor's head is ~20 doc px
      // tall: comfortably past the pull-fit margin.
      c.onPageMeasured(0, 500.0, 20.0);
      c.onPageMeasured(1, 200.0, 20.0);
      async.elapse(const Duration(milliseconds: 700)); // > _reflowSettle

      expect(c.pages.length, 2, reason: 'nothing text-empty here yet');
      final receiverChildren =
          (c.pages[0].controller.documentJson['children'] as List)
              .cast<Map>();
      final donorChildren =
          (c.pages[1].controller.documentJson['children'] as List)
              .cast<Map>();

      expect(
        receiverChildren.map((e) => e['type']).toList(),
        ['paragraph', 'numbered_list', 'heading'],
        reason: 'the donor head moved up as the receiver tail',
      );
      final head = receiverChildren.last;
      expect(head['type'], 'heading');
      final data = head['data'] as Map?;
      expect(data?['level'], 1, reason: 'heading level must survive the move');
      expect(
        (data?['delta'] as List).single['insert'],
        'Training and splitting data',
      );

      // The donor keeps what was left, in order.
      expect(
        donorChildren.map((e) => e['type']).toList(),
        ['paragraph'],
      );
      expect(
        ((donorChildren.single['data'] as Map)['delta'] as List)
            .single['insert'],
        'Splitting data according to traing and test.',
      );
    });
  });
}
