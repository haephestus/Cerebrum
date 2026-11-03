import 'package:flutter_test/flutter_test.dart';
import 'package:cerebrum/ui/screens/editor/helpers/page_ink_store.dart';

/// PageInkStore — Strategy-B ink bookkeeping. hasInk must be the exact
/// Strategy-A `_pageHasInk` semantics, pageId-keyed: inked = a sketch with a
/// non-empty lines list.
void main() {
  const emptySketch = {'lines': <dynamic>[]};
  const drawnSketch = {
    'lines': [
      {
        'points': [
          {'x': 1.0, 'y': 2.0},
        ],
        'color': 0,
        'width': 3.0,
      },
    ],
  };

  test('unknown pageId has no ink', () {
    final store = PageInkStore();
    expect(store.hasInk('p1'), isFalse);
    expect(store.inkOf('p1'), isNull);
  });

  test('sketch with no lines is NOT ink; non-empty lines IS', () {
    final store = PageInkStore();
    store.setInk('p1', [emptySketch]);
    expect(store.hasInk('p1'), isFalse, reason: 'an empty sketch is inkless');
    store.setInk('p1', [drawnSketch]);
    expect(store.hasInk('p1'), isTrue);
  });

  test('malformed payloads read as inkless, never crash', () {
    final store = PageInkStore();
    // missing 'lines' key
    store.setInk('p1', [
      <String, dynamic>{},
    ]);
    expect(store.hasInk('p1'), isFalse);
    store.setInk('p2', [
      {'lines': 'not-a-list'},
    ]);
    expect(store.hasInk('p2'), isFalse);
  });

  test('removeInk drops only that page', () {
    final store = PageInkStore();
    store.setInk('p1', [drawnSketch]);
    store.setInk('p2', [drawnSketch]);
    store.removeInk('p1');
    expect(store.hasInk('p1'), isFalse);
    expect(store.hasInk('p2'), isTrue);
  });

  test('round trip through toJson/fromJson preserves ink state', () {
    final a = PageInkStore();
    a.setInk('p1', [drawnSketch]);
    a.setInk('p2', [emptySketch]);
    final b = PageInkStore.fromJson(a.toJson());
    expect(b.hasInk('p1'), isTrue);
    expect(b.hasInk('p2'), isFalse, reason: 'inkless page survives the round trip');
  });

  test('fromJson drops malformed entries instead of landing them', () {
    final b = PageInkStore.fromJson({
      'p1': drawnSketch, // not a LIST of sketches
      'p2': [drawnSketch],
    });
    expect(b.hasInk('p1'), isFalse);
    expect(b.hasInk('p2'), isTrue);
  });
}
