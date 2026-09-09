import 'package:flutter/painting.dart' show Offset;
import 'package:flutter_test/flutter_test.dart';
import 'package:scribble/scribble.dart';
import 'package:cerebrum/ui/screens/editor/screens/drawing_layer.dart';

/// Verifies the partial (split) eraser: it removes points under the eraser and
/// splits the surviving points into sub-strokes, leaving untouched strokes and
/// dots intact. See NoteDrawingLayer.
SketchLine _line(List<List<double>> pts) => SketchLine(
      points: [for (final p in pts) Point(p[0], p[1])],
      color: 0xFF000000,
      width: 3,
    );

void main() {
  final sketch = Sketch(lines: [
    _line([
      [0, 0], [2, 0], [4, 0], [6, 0], [8, 0], [10, 0], // horizontal stroke
    ]),
    _line([
      [100, 100], // a single-point dot
    ]),
  ]);

  test('eraser far away changes nothing', () {
    final out = splitErase(sketch, const Offset(500, 500), 5);
    expect(out.lines.length, 2);
    expect(out.lines.any((l) => l.points.length == 1), isTrue, reason: 'dot kept');
  });

  test('erasing the middle splits the stroke into two pieces', () {
    final out = splitErase(sketch, const Offset(5, 0), 2.5);
    final pieces = out.lines.where((l) => l.points.first.y == 0).toList();
    expect(pieces.length, 2, reason: 'crossed stroke → two sub-strokes');
    // left piece keeps x<=4 (within 2.5 of x=5 removed → 4 and 6 gone? 4 is 1.0
    // away → removed; so left is 0,2), right piece keeps x>=8.
    final leftXs = pieces[0].points.map((p) => p.x.toInt()).toList();
    final rightXs = pieces[1].points.map((p) => p.x.toInt()).toList();
    expect(leftXs, [0, 2]);
    expect(rightXs, [8, 10]);
    expect(out.lines.any((l) => l.points.length == 1), isTrue, reason: 'dot untouched');
  });

  test('erasing an endpoint shortens the stroke (still one piece)', () {
    final out = splitErase(sketch, const Offset(10, 0), 2.5);
    final stroke = out.lines.firstWhere((l) => l.points.first.y == 0);
    expect(stroke.points.map((p) => p.x.toInt()).toList(), [0, 2, 4, 6]);
  });

  test('a 1-point remnant is dropped (no stray dot at the cut)', () {
    // Eraser at x=4 r=3 erases 2,4,6; x=0 survives alone (before the erased run)
    // as a 1-point segment → dropped; 8,10 survive as a real piece.
    final out = splitErase(sketch, const Offset(4, 0), 3);
    final pieces = out.lines.where((l) => l.points.first.y == 0).toList();
    expect(pieces.length, 1, reason: 'lone x=0 dropped, only [8,10] kept');
    expect(pieces.first.points.map((p) => p.x.toInt()).toList(), [8, 10]);
  });
}
