import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/gestures.dart' show EagerGestureRecognizer;
import 'package:flutter/material.dart';
import 'package:scribble/scribble.dart';

/// Freehand ink layer for ONE page, backed by `scribble`.
///
/// ## Two eraser modes — why, and how they're chosen
///
/// `scribble`'s built-in eraser is **whole-stroke**: it drops an entire line the
/// moment the eraser touches any point of it (see its `_erasePoint`). That's one
/// valid mode, but a note-taker usually wants to rub out *part* of a stroke.
///
/// So the eraser has two modes, chosen on the tool wheel and carried here by
/// [partialEraser]:
///   * **Partial (split)** — this layer **blocks scribble's own pointers** with
///     an `IgnorePointer` (scribble still *renders*), and overlays a
///     [_PartialEraser] that edits the polyline point lists directly: drops the
///     points under the eraser and splits the survivors into shorter sub-strokes
///     (see [splitErase]). Vector-accurate partial erasure.
///   * **Whole-stroke** — scribble's native eraser handles the pointers (no
///     overlay, no IgnorePointer); it shows its own eraser cursor.
///
/// Both are only in play while the tool is the eraser (`state is Erasing`, set
/// by the wheel). For any other tool this layer is just the plain canvas. Ink is
/// page-LOCAL — each page has its own bounded scribble widget.
class NoteDrawingLayer extends StatelessWidget {
  const NoteDrawingLayer({
    super.key,
    required this.notifier,
    this.partialEraser,
    this.eraserWidth,
  });

  final ScribbleNotifier notifier;

  /// Whether the eraser is in **partial (split)** mode. Shared across all pages
  /// (owned by EditorScaffold) so the choice is global. Null → default to
  /// partial. Only consulted while erasing.
  final ValueListenable<bool>? partialEraser;

  /// Eraser **diameter** (logical px), driven by the tool wheel's size selector
  /// and shared across pages. Null → fall back to [_kDefaultEraserWidth]. The
  /// partial-erase cut radius is half this.
  final ValueListenable<double>? eraserWidth;

  @override
  Widget build(BuildContext context) {
    // Rebuild on the sketch/tool state, the partial/whole toggle, OR the size.
    return AnimatedBuilder(
      animation: Listenable.merge([notifier, partialEraser, eraserWidth]),
      builder: (context, _) {
        final erasing = notifier.value is Erasing;
        final partial = partialEraser?.value ?? true;
        final useSplit = erasing && partial; // our custom eraser is in charge
        final radius = (eraserWidth?.value ?? _kDefaultEraserWidth) / 2;
        return Stack(
          children: [
            // Scribble RENDERS the sketch either way. In split mode we block its
            // pointers so its whole-stroke eraser can't fire — [_PartialEraser]
            // takes them. In whole-stroke mode scribble erases itself and shows
            // its own eraser cursor (drawEraser).
            IgnorePointer(
              ignoring: useSplit,
              child: Scribble(notifier: notifier, drawEraser: !useSplit),
            ),
            if (useSplit)
              Positioned.fill(
                child: _PartialEraser(notifier: notifier, radius: radius),
              ),
          ],
        );
      },
    );
  }
}

/// Fallback eraser diameter when no shared size is wired in.
const double _kDefaultEraserWidth = 24;

/// Overlaid while the eraser tool is active. Handles the pointer itself and
/// rewrites the sketch as a **split erase** (see [splitErase]).
///
/// Undo semantics mirror scribble's own draw gesture: during the drag each move
/// pushes with `addToUndoHistory: false` (scribble's transient `temporaryValue`,
/// so it renders live but isn't an undo step), and on pointer-up we commit once
/// with `addToUndoHistory: true` — so the whole erase stroke is a SINGLE undo.
class _PartialEraser extends StatefulWidget {
  const _PartialEraser({required this.notifier, required this.radius});

  final ScribbleNotifier notifier;

  /// Cut radius (logical px) — half the eraser diameter from the tool wheel.
  final double radius;

  @override
  State<_PartialEraser> createState() => _PartialEraserState();
}

class _PartialEraserState extends State<_PartialEraser> {
  double get _radius => widget.radius;

  // The sketch we're progressively erasing, accumulated across moves. Tracked
  // locally (not re-read from the notifier) because live updates go to the
  // transient channel, which `currentSketch` doesn't reflect.
  Sketch? _working;
  Offset? _cursor;

  void _begin(Offset p) {
    _working = widget.notifier.currentSketch;
    _erase(p);
  }

  void _erase(Offset p) {
    final base = _working ?? widget.notifier.currentSketch;
    final next = splitErase(base, p, _radius);
    _working = next;
    // Transient: renders live, not an undo step.
    widget.notifier.setSketch(sketch: next, addToUndoHistory: false);
    setState(() => _cursor = p);
  }

  void _end() {
    final done = _working;
    if (done != null) {
      // Commit the whole erase as one undo step.
      widget.notifier.setSketch(sketch: done, addToUndoHistory: true);
    }
    _working = null;
    setState(() => _cursor = null);
  }

  @override
  Widget build(BuildContext context) {
    // Why RawGestureDetector + EagerGestureRecognizer, not a bare Listener:
    // the eraser lives inside the paged ListView. A bare Listener observes
    // pointer moves but never CLAIMS the gesture arena, so a drag would erase
    // AND the ListView would also scroll — the two fought. Scribble avoids this
    // by driving drawing through an eager gesture catcher; we mirror that. The
    // Eager recogniser wins the arena immediately (so scroll doesn't engage),
    // while the inner Listener still receives the pointer positions we erase by.
    // Mouse-wheel scrolling is a PointerSignal, not a drag, so it still works.
    return RawGestureDetector(
      behavior: HitTestBehavior.opaque, // capture every pointer over the sheet
      gestures: <Type, GestureRecognizerFactory>{
        EagerGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
          EagerGestureRecognizer.new,
          (_) {},
        ),
      },
      child: Listener(
        onPointerDown: (e) => _begin(e.localPosition),
        onPointerMove: (e) => _erase(e.localPosition),
        onPointerUp: (_) => _end(),
        onPointerCancel: (_) => _end(),
        child: CustomPaint(
          painter: _EraserCursorPainter(center: _cursor, radius: _radius),
        ),
      ),
    );
  }
}

/// Return a copy of [sketch] with the points within [radius] of [eraser]
/// removed, splitting each affected stroke into the surviving sub-strokes.
///
///  * A stroke the eraser doesn't touch is kept unchanged (so single-point
///    "dot" strokes survive).
///  * A stroke the eraser crosses is split: each run of consecutive surviving
///    points becomes its own [SketchLine] (keeping the original colour/width);
///    runs shorter than 2 points are dropped so no stray dots linger at the cut.
///
/// Points are never mutated — only filtered/regrouped — so pressure/colour/width
/// are preserved exactly on the surviving pieces.
Sketch splitErase(Sketch sketch, Offset eraser, double radius) {
  bool erased(Point p) => (eraser - Offset(p.x, p.y)).distance <= radius;

  final out = <SketchLine>[];
  for (final line in sketch.lines) {
    if (!line.points.any(erased)) {
      out.add(line); // untouched — keep as-is (incl. 1-point dots)
      continue;
    }
    var segment = <Point>[];
    for (final p in line.points) {
      if (erased(p)) {
        if (segment.length >= 2) out.add(line.copyWith(points: segment));
        segment = <Point>[];
      } else {
        segment.add(p);
      }
    }
    if (segment.length >= 2) out.add(line.copyWith(points: segment));
  }
  return sketch.copyWith(lines: out);
}

/// A soft ring showing where the eraser is while dragging. IgnorePointer-free
/// (it's inside the Listener) and cheap — repaints only when the cursor moves.
class _EraserCursorPainter extends CustomPainter {
  _EraserCursorPainter({required this.center, required this.radius});

  final Offset? center;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final c = center;
    if (c == null) return;
    canvas.drawCircle(c, radius, Paint()..color = Colors.black12);
    canvas.drawCircle(
      c,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.black45,
    );
  }

  @override
  bool shouldRepaint(covariant _EraserCursorPainter old) =>
      old.center != center || old.radius != radius;
}
