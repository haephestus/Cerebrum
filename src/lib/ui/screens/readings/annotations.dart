// =============================================================================
// ANNOTATION LAYER: STATUS + TODO (for a coding agent)
//
// What exists: freehand pen, highlighter, stroke eraser, color/width, undo/redo,
// per-file persistence. Strokes are stored in page-relative coordinates
// (0..1 of page width/height; width = fraction of page width) so they are
// zoom/render-size independent. Keep that invariant for every new annotation
// type (text highlights, notes, etc.).
//
// Not compiled or tested yet. First step: run `flutter analyze`, fix anything
// that doesn't match the installed pdfrx version, then test on device.
//
// SCRIBBLE (already in pubspec, currently UNUSED; this layer is custom):
//  Per its docs/changelog, `scribble` supports: choosing which pointer kinds
//  can draw (pen/touch/mouse), pen and touch pressure with variable line
//  width, line (whole-stroke) eraser, undo/redo, line simplification, JSON
//  (de)serialization of sketches, setSketch(), PNG export, and its changelog
//  describes pen-draws/finger-scrolls inside a Scrollable and wrapping it in an
//  InteractiveViewer. It removed its marker-like blend mode, so a multiply
//  highlighter is NOT built in. Not verified: how its sketch coordinates behave
//  when the widget is resized or zoomed (assume pixel space of its own widget).
//  DECISION FOR THE AGENT: prototype one Scribble per page overlay (replacing
//  the Listener/CustomPainter input + stroke painting in InkPageLayer) and
//  check whether (a) stylus-only drawing coexists with touch scrolling in the
//  pdfrx viewer, and (b) strokes can be converted to/from the normalized
//  page-relative model on save/load. If both work, use it for items 2, 3 and
//  11 below and delete the redundant code; keep the custom model for
//  persistence, highlighter, text markup, notes and export. If not, keep the
//  custom layer and remove `scribble` from pubspec.yaml.
//
// COORDINATE MODEL (what is stored, and its known gaps):
//  Each stroke stores: page number; points as fractions (0..1) of the page's
//  rendered width/height, origin top-left; width as a fraction of page width;
//  and is keyed per file as `ink:<fileFingerprint>`. Pointer positions are
//  normalized on input and denormalized against the page's current rendered
//  size when painting, which is what keeps strokes aligned across zoom/resize.
//  Known gaps / TODO:
//   a. UNTESTED ASSUMPTION: the design relies on pdfrx's pageOverlaysBuilder
//      widget being sized to the page and scaling with zoom. Verify on device
//      first (draw, zoom in/out, resize window, check alignment). If the
//      overlay is not page-sized, normalization will drift.
//   b. PAGE ROTATION / CROP BOX: pages with a /Rotate flag or a CropBox that
//      differs from the MediaBox are not handled. Check whether pdfrx's page
//      size and the overlay already account for rotation; if not, store
//      coordinates in an unrotated page space and transform on paint. Test with
//      rotated and cropped PDFs.
//   c. NOT PDF SPACE: stored coordinates are fractions of the rendered page,
//      top-left origin. PDF native space is points with a bottom-left origin.
//      Before embedding real /Ink annotations or exporting to PDF coordinates,
//      add a conversion (multiply by page size in points, flip the y axis, and
//      apply rotation/crop box offsets).
//   d. ASPECT RATIO: stroke width is a fraction of page WIDTH only, so it is
//      consistent across zoom but is not resolution-independent for pages with
//      unusual aspect ratios. The eraser radius is also based on page width.
//      Revisit if this looks wrong.
//   e. FILE IDENTITY: confirm what `fileFingerprint` is. If it is a content
//      hash, a re-uploaded or edited PDF gets a new fingerprint and loses its
//      annotations (consider migrating or re-linking). If it is a stable id,
//      strokes could end up on the wrong content when the file changes. Decide
//      the policy, and consider storing the page count and a content hash
//      alongside strokes to detect mismatches.
//   f. COORDINATE CONVERSION FOR SCRIBBLE: if Scribble is adopted (see above),
//      its points are in widget-pixel space, so convert to/from the normalized
//      model on save/load.
//
// TODO (in suggested order):
//  1. PERSISTENCE -> drift. Replace the shared_preferences JSON blob (see
//     "persistence" section below) with a drift table, e.g. `ink_strokes`
//     (id, fileFingerprint, page, colorArgb, width, highlighter, pointsBlob,
//     createdAt). Pack points as a Float32List blob. Load per file, write
//     incrementally (insert/delete rows) instead of rewriting everything.
//     Follow docs/drift-migration.md; codegen needs
//     `dart run build_runner build --force-jit`.
//  2. INPUT: stylus draws, fingers scroll/zoom. Currently any active tool locks
//     pan/zoom for the whole viewer (see reader.dart). Needs per-pointer
//     handling: only PointerDeviceKind.stylus (and optionally mouse) draws,
//     touch passes through to the viewer, palm rejection, and a way to stop a
//     stylus drag from also panning the viewer (verify how pdfrx's
//     InteractiveViewer treats stylus). Possibly a user setting "draw with
//     finger".
//  3. PRESSURE: PointerEvent.pressure is available but not recorded. Add a
//     per-point pressure channel and variable-width rendering (needs a schema
//     change, so do it together with step 1).
//  4. TEXT-SNAPPED MARKUP: highlight/underline/strikethrough from the user's
//     text selection. Needs pdfrx's text selection + per-character rects
//     (verify the API in the installed pdfrx version; don't guess). Store as
//     normalized quads per page + type + color, painted by this same layer.
//  5. STICKY NOTES / TEXT COMMENTS: tap handler on InkPageLayer; model =
//     (page, normalized position, text, createdAt); small icon painted on the
//     page, tap to edit/delete.
//  6. EXPORT: flatten to a shareable copy (render pages with pdfrx, paint
//     strokes via paintInkStroke, assemble with the `pdf` package). Output is
//     rasterized (no selectable text), so label it as "share annotated copy".
//     Embedding real /Ink annotations into the original PDF needs a PDF writer
//     that supports it; none chosen yet. Do NOT reintroduce
//     syncfusion_flutter_pdf casually: it pulls xml ^7 and conflicts with
//     appflowy_editor on the current Dart SDK.
//  7. SYNC: strokes currently live only on this device. Decide whether the
//     backend (KnowledgebaseApi) should store them; if so, use stroke ids +
//     createdAt for merge, and consider soft-deletes.
//  8. HIGHLIGHTER BLEND: BlendMode.multiply may not blend with the PDF image
//     beneath if pdfrx composites overlays in an isolated layer. Check
//     visually; fall back to plain alpha if it looks wrong.
//  9. PERFORMANCE: every pointer move calls notifyListeners(), which rebuilds
//     every visible page layer. Scope repaints to the page being drawn on
//     (per-page notifiers) and consider caching finished strokes in a
//     ui.Picture per page. Also check LayoutBuilder gets a bounded size inside
//     pageOverlaysBuilder.
// 10. ERASER: currently whole-stroke erase with a fixed radius. Optionally add
//     partial (split-stroke) erase and a configurable radius.
// 11. TESTS: unit-test InkStroke JSON round trip, undo/redo (including batched
//     erase ops), and normalization.
// =============================================================================

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AnnotationTool { none, pen, highlighter, eraser }

/// One freehand stroke. Points are normalized (0..1) relative to the page's
/// width/height, and [width] is a fraction of page width, so strokes stay
/// aligned at any zoom level or render size.
class InkStroke {
  InkStroke({
    required this.page,
    required this.points,
    required this.color,
    required this.width,
    required this.highlighter,
  });

  final int page;
  final List<Offset> points;
  final Color color;
  final double width;
  final bool highlighter;

  Map<String, dynamic> toJson() => {
    'p': page,
    'c': color.toARGB32(),
    'w': width,
    'h': highlighter,
    'pts': [
      for (final o in points) ...[o.dx, o.dy],
    ],
  };

  factory InkStroke.fromJson(Map<String, dynamic> j) {
    final flat = (j['pts'] as List).cast<num>();
    return InkStroke(
      page: j['p'] as int,
      color: Color(j['c'] as int),
      width: (j['w'] as num).toDouble(),
      highlighter: j['h'] as bool,
      points: [
        for (var i = 0; i + 1 < flat.length; i += 2)
          Offset(flat[i].toDouble(), flat[i + 1].toDouble()),
      ],
    );
  }
}

class _Op {
  _Op({this.added = const [], this.removed = const []});
  final List<InkStroke> added;
  final List<InkStroke> removed;
}

class AnnotationStore extends ChangeNotifier {
  AnnotationStore(this.fingerprint);

  final String fingerprint;

  AnnotationTool tool = AnnotationTool.none;
  Color color = const Color(0xFF1565C0);
  double penWidth = 0.003; // fraction of page width
  static const double highlighterWidth = 0.02;

  final List<InkStroke> _strokes = [];
  final List<_Op> _undo = [];
  final List<_Op> _redo = [];
  InkStroke? live;
  final List<InkStroke> _eraseBatch = [];
  Timer? _saveTimer;

  bool get drawing => tool != AnnotationTool.none;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  Iterable<InkStroke> strokesFor(int page) =>
      _strokes.where((s) => s.page == page);

  // ---- tool state ---------------------------------------------------------

  void setTool(AnnotationTool t) {
    tool = (tool == t) ? AnnotationTool.none : t; // tap again to leave
    notifyListeners();
  }

  void setColor(Color c) {
    color = c;
    notifyListeners();
  }

  void setPenWidth(double w) {
    penWidth = w;
    notifyListeners();
  }

  // ---- pointer input (called from the page layer) -------------------------

  Offset _norm(Offset local, Size size) => Offset(
    (local.dx / size.width).clamp(0.0, 1.0),
    (local.dy / size.height).clamp(0.0, 1.0),
  );

  void pointerDown(int page, Offset local, Size size) {
    if (tool == AnnotationTool.eraser) {
      _eraseBatch.clear();
      _erase(page, local, size);
      return;
    }
    final hl = tool == AnnotationTool.highlighter;
    live = InkStroke(
      page: page,
      points: [_norm(local, size)],
      color: color,
      width: hl ? highlighterWidth : penWidth,
      highlighter: hl,
    );
    notifyListeners();
  }

  void pointerMove(int page, Offset local, Size size) {
    if (tool == AnnotationTool.eraser) {
      _erase(page, local, size);
      return;
    }
    live?.points.add(_norm(local, size));
    notifyListeners();
  }

  void pointerUp() {
    if (tool == AnnotationTool.eraser) {
      if (_eraseBatch.isNotEmpty) {
        _push(_Op(removed: List.of(_eraseBatch)));
        _eraseBatch.clear();
      }
      return;
    }
    final s = live;
    live = null;
    if (s != null) {
      _strokes.add(s);
      _push(_Op(added: [s]));
    }
    notifyListeners();
  }

  void _erase(int page, Offset local, Size size) {
    final radius = size.width * 0.02;
    final hit = <InkStroke>[];
    for (final s in strokesFor(page)) {
      final px =
          s.points
              .map((p) => Offset(p.dx * size.width, p.dy * size.height))
              .toList();
      final r = radius + s.width * size.width / 2;
      var touched = px.length == 1 && (px.first - local).distance <= r;
      for (var i = 0; !touched && i < px.length - 1; i++) {
        touched = _distToSegment(local, px[i], px[i + 1]) <= r;
      }
      if (touched) hit.add(s);
    }
    if (hit.isEmpty) return;
    _strokes.removeWhere(hit.contains);
    _eraseBatch.addAll(hit);
    notifyListeners();
  }

  static double _distToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (len2 == 0) return (p - a).distance;
    final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2).clamp(
      0.0,
      1.0,
    );
    return (p - (a + ab * t)).distance;
  }

  // ---- undo / redo --------------------------------------------------------

  void _push(_Op op) {
    _undo.add(op);
    _redo.clear();
    _scheduleSave();
  }

  void undo() {
    if (_undo.isEmpty) return;
    final op = _undo.removeLast();
    _strokes.removeWhere(op.added.contains);
    _strokes.addAll(op.removed);
    _redo.add(op);
    _scheduleSave();
    notifyListeners();
  }

  void redo() {
    if (_redo.isEmpty) return;
    final op = _redo.removeLast();
    _strokes.removeWhere(op.removed.contains);
    _strokes.addAll(op.added);
    _undo.add(op);
    _scheduleSave();
    notifyListeners();
  }

  // ---- persistence ---------------------------------------------------------
  // TODO(drift): replace this whole section; see header item 1. Note that undo
  // history is in-memory only and is lost when the reader closes (fine for now).

  String get _key => 'ink:$fingerprint';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return;
    _strokes
      ..clear()
      ..addAll(
        (jsonDecode(raw) as List).map(
          (e) => InkStroke.fromJson(e as Map<String, dynamic>),
        ),
      );
    notifyListeners();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), _saveNow);
  }

  Future<void> _saveNow() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(_strokes.map((s) => s.toJson()).toList()),
    );
  }

  @override
  void dispose() {
    if (_saveTimer?.isActive ?? false) {
      _saveTimer!.cancel();
      _saveNow();
    }
    super.dispose();
  }
}

// ---- painting ---------------------------------------------------------------

void paintInkStroke(Canvas canvas, Size size, InkStroke s) {
  final paint =
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = s.highlighter ? StrokeCap.butt : StrokeCap.round
        ..strokeWidth = s.width * size.width
        ..color = s.highlighter ? s.color.withValues(alpha: 0.35) : s.color
        ..blendMode = s.highlighter ? BlendMode.multiply : BlendMode.srcOver;

  final pts =
      s.points
          .map((p) => Offset(p.dx * size.width, p.dy * size.height))
          .toList();
  if (pts.length == 1) {
    canvas.drawCircle(
      pts.first,
      paint.strokeWidth / 2,
      paint..style = PaintingStyle.fill,
    );
    return;
  }
  // Smooth through midpoints with quadratic curves.
  final path = Path()..moveTo(pts.first.dx, pts.first.dy);
  for (var i = 1; i < pts.length - 1; i++) {
    final mid = (pts[i] + pts[i + 1]) / 2;
    path.quadraticBezierTo(pts[i].dx, pts[i].dy, mid.dx, mid.dy);
  }
  path.lineTo(pts.last.dx, pts.last.dy);
  canvas.drawPath(path, paint);
}

class _InkPainter extends CustomPainter {
  _InkPainter(this.store, this.page) : super(repaint: store);
  final AnnotationStore store;
  final int page;

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in store.strokesFor(page)) {
      paintInkStroke(canvas, size, s);
    }
    final live = store.live;
    if (live != null && live.page == page) paintInkStroke(canvas, size, live);
  }

  @override
  bool shouldRepaint(_InkPainter old) => old.page != page || old.store != store;
}

/// Put this in `PdfViewerParams.pageOverlaysBuilder`. It paints the page's
/// strokes always, and only captures pointer input while a tool is active.
class InkPageLayer extends StatelessWidget {
  const InkPageLayer({
    super.key,
    required this.store,
    required this.pageNumber,
  });

  final AnnotationStore store;
  final int pageNumber;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder:
          (context, _) => IgnorePointer(
            ignoring: !store.drawing,
            child: LayoutBuilder(
              builder: (context, c) {
                final size = c.biggest;
                // TODO(input): filter by e.kind (stylus vs touch), palm rejection,
                // record e.pressure, handle multi-pointer (ignore extra pointers
                // while a stroke is live). See header items 2 and 3.
                // TODO(notes/markup): tap handling for sticky notes and for
                // selecting/deleting existing annotations goes here.
                return Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown:
                      (e) =>
                          store.pointerDown(pageNumber, e.localPosition, size),
                  onPointerMove:
                      (e) =>
                          store.pointerMove(pageNumber, e.localPosition, size),
                  onPointerUp: (_) => store.pointerUp(),
                  onPointerCancel: (_) => store.pointerUp(),
                  child: CustomPaint(
                    size: size,
                    painter: _InkPainter(store, pageNumber),
                  ),
                );
              },
            ),
          ),
    );
  }
}
