import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scribble/scribble.dart';
import 'package:cerebrum/ui/screens/editor/helpers/page_ink_store.dart';
import 'package:cerebrum/ui/screens/editor/helpers/page_ink_surface.dart';

/// PageInkSurface — one ScribbleNotifier per pageId, seeded from the store,
/// persisted back on change, fans the drawing tool out to all sheets.
int? _selectedColor(ScribbleNotifier n) => n.value.map(
      drawing: (d) => d.selectedColor,
      erasing: (_) => null,
    );

void main() {
  const drawnSketch = {
    'lines': [
      {
        'points': [
          {'x': 10.0, 'y': 20.0},
          {'x': 30.0, 'y': 40.0},
        ],
        'color': 0xFF000000,
        'width': 3.0,
      },
    ],
  };
  const recolouredSketch = {
    'lines': [
      {
        'points': [
          {'x': 99.0, 'y': 88.0},
        ],
        'color': 0xFFFF0000,
        'width': 6.0,
      },
    ],
  };

  test('notifierFor is lazy and stable; seeded from the store', () {
    final store = PageInkStore();
    store.setInk('p2', [drawnSketch]);
    final surface = PageInkSurface(store: store);
    final n = surface.notifierFor('p2');
    expect(surface.notifierFor('p2'), same(n), reason: 'same instance reused');
    expect(n.currentSketch.lines, isNotEmpty, reason: 'seeded from store');
    surface.dispose();
  });

  test('sketch changes persist back into the store', () {
    final store = PageInkStore();
    final surface = PageInkSurface(store: store);
    final n = surface.notifierFor('p1');
    expect(store.hasInk('p1'), isFalse);
    n.setSketch(sketch: Sketch.fromJson(drawnSketch));
    expect(store.hasInk('p1'), isTrue);
    expect(store.inkOf('p1')!.first['lines'], hasLength(1));
    surface.dispose();
  });

  test('applyDrawingTool reaches live AND future notifiers', () {
    final store = PageInkStore();
    final surface = PageInkSurface(store: store);
    final a = surface.notifierFor('p1');
    final colorOf = _selectedColor;
    surface.applyDrawingTool((n) => n.setColor(const Color(0xFF00FF00)));
    expect(colorOf(a), 0xFF00FF00);
    final b = surface.notifierFor('p2');
    expect(colorOf(b), 0xFF00FF00, reason: 'the tool config applies to notifiercreated after');
    surface.dispose();
  });

  test('removePage drops the notifier and the store entry', () {
    final store = PageInkStore();
    store.setInk('p1', [drawnSketch]);
    final surface = PageInkSurface(store: store);
    surface.notifierFor('p1');
    surface.removePage('p1');
    expect(store.hasInk('p1'), isFalse);
    surface.dispose();
  });

  test('a whole-sketch replacement round trips color and width into the store',
      () {
    final store = PageInkStore();
    final surface = PageInkSurface(store: store);
    final n = surface.notifierFor('p1');
    n.setSketch(sketch: Sketch.fromJson(recolouredSketch));
    final stored = store.inkOf('p1')!;
    final storedLine =
        (stored.first['lines'] as List).first as Map<String, dynamic>;
    final points = (storedLine['points'] as List).cast<Map<String, dynamic>>();
    expect(points.first['x'], 99.0);
    expect(points.first['y'], 88.0);
    expect(storedLine['color'], 0xFFFF0000);
    expect(storedLine['width'], 6.0);
    surface.dispose();
  });
}
