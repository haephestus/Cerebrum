// =============================================================================
// ANNOTATION LAYER: STATUS + TODO (for a coding agent)
//
// The reader's ink layer is now scribble-backed (see reader_ink_layer.dart).
// The SCRIBBLE DECISION below is RESOLVED: scribble drives pen/highlighter
// input and stroke rendering via one ScribbleNotifier per page, wrapped in a
// canonical canvas so strokes don't drift under pdfrx's zoom-resized overlays.
// The custom Listener/CustomPainter input path (old InkPageLayer) is deleted.
// Keep the PageAnnotation persistence model (normalized 0..1, below) for
// storage, export, text markup and notes.
//
// COORDINATE MODEL (what is stored, and how it maps to scribble):
//  Each stroke stores: page number; points as fractions (0..1) of the page's
//  size (width/height, origin top-left); width as a fraction of page width;
//  keyed per file as `ink:<fileFingerprint>`. At runtime each page's overlay is
//  a FIXED logical canvas sized to the page's PDF-point dimensions
//  (PdfPage.width x .height, already rotated) inside a FittedBox that maps it
//  onto pdfrx's zoom-scaled page rect. pdfrx does NOT give overlays tight
//  constraints, so an OverflowBox forces the FittedBox to exactly the `pageRect`
//  pdfrx passes to pageOverlaysBuilder (see reader_ink_layer.dart). Scribble
//  records points in that canonical canvas space, so strokes are
//  zoom-independent by construction (both paint AND hit-test transform through
//  the FittedBox — RenderFittedBox lays its child out with unbounded
//  constraints and hit-tests through its transform). Conversion between the two
//  models lives in sketchFromAnnotations / annotationsFromSketch below.
//
//  STORAGE: one unified PageAnnotation hierarchy (ink / text-markup / note),
//  serialized as a JSON array under `ink:<fileFingerprint>` (key unchanged, so
//  blobs written before the `t` kind tag still load). Highlight and note have
//  a model + codecs today but no UI yet — they are the contract the next
//  feature builds on, so persistence never grows a second shape.
//
//  Known gaps / TODO:
//   a. RESOLVED: each page overlay is a canonical canvas inside a FittedBox
//      that is forced to the zoomed page rect by an OverflowBox. Lesson learned:
//      pdfrx passes `pageRect` but NOT tight constraints, so a bare FittedBox
//      rendered the canvas at natural size (612x792) in the page's top-left
//      corner; scribble's hover dot, drawing and hit-testing only worked inside
//      that box, and everywhere else the default cursor returned and drags
//      panned the viewer. Still verify on device that strokes stay aligned
//      after zooming and that stylus input doesn't also pan the viewer.
//   b. PAGE ROTATION / CROP BOX: PdfPage.width/height are ROTATED sizes, so
//      strokes are stored in rotated page space. Verify with rotated and
//      cropped PDFs; PDF-space export still needs `c`.
//   c. NOT PDF SPACE: stored coordinates are fractions of the rendered page,
//      top-left origin. PDF native space is points with a bottom-left origin.
//      Before embedding real /Ink annotations or exporting to PDF coordinates,
//      add a conversion (multiply by page size in points, flip the y axis, and
//      apply rotation/crop box offsets).
//   d. ASPECT RATIO: stroke width is a fraction of page WIDTH only, so it is
//      consistent across zoom but not resolution-independent for pages with
//      unusual aspect ratios. Revisit if this looks wrong.
//   e. FILE IDENTITY: confirm what `fileFingerprint` is. If it is a content
//      hash, a re-uploaded or edited PDF gets a new fingerprint and loses its
//      annotations. If it is a stable id, strokes could end up on the wrong
//      content when the file changes. Decide the policy, and consider storing
//      the page count and a content hash alongside strokes to detect mismatches.
//   f. RESOLVED: sketchFromAnnotations / annotationsFromSketch (below) are the
//      exact conversion pair the old decision asked for.
//
// TODO (in suggested order):
//  1. PERSISTENCE -> drift. The unified model landed (PageAnnotation, above);
//     the shared_preferences JSON blob in the "persistence" section below is
//     still the backing store. Replace it with a drift table, e.g.
//     `page_annotations` (id, fileFingerprint, page, kind, colorArgb, width,
//     payloadBlob, createdAt) — pack points/quads as a Float32List blob, load
//     per file, write incrementally (insert/delete rows). A real `kind` /
//     `highlighter` column also kills the alpha<1 marker hack below
//     (annotationsFromSketch tags highlights by colour; fine while pen strokes
//     are always opaque).
//  2. RESOLVED — scribble's ScribblePointerMode filters pointers (penOnly /
//     mouseAndPen / all): only stylus (and optionally mouse) draw, touch
//     passes through to the viewer's pan/zoom (verified from scribble source —
//     its GestureCatcher claims only the configured pointer kinds). The old
//     whole-viewer pan/zoom lock in reader.dart is gone. Remaining: palm
//     rejection is untested on device.
//  3. RESOLVED — Point.pressure is recorded per point (scribble) and rendered
//     variably by perfect_freehand.
//  4. TEXT-SNAPPED MARKUP: highlight/underline/strikethrough from the user's
//     text selection. STORAGE IS READY — HighlightAnnotation (normalized quads
//     + colour + quoted text). Still to do: the pdfrx selection hook
//     (PdfTextSelectionParams.onTextSelectionChange -> getSelectedTextRanges()
//     -> enumerateFragmentBoundingRects(), converted with PdfRect.toRect(page:
//     ..., scaledPageSize: canonical page size)) and a painter in this layer.
//  5. STICKY NOTES / TEXT COMMENTS: STORAGE IS READY — NoteAnnotation (anchor
//     quads/position + text + createdAt). Still to do: the trigger (context
//     menu item on the selection, or tap-to-place), the icon painted on the
//     page, and the popup editor positioned through the controller's
//     doc2local converter.
//  6. EXPORT: flatten to a shareable copy (render pages with pdfrx, paint
//     strokes, assemble with the `pdf` package). Output is rasterized (no
//     selectable text), so label it as "share annotated copy". Embedding real
//     /Ink annotations into the original PDF needs a PDF writer that supports
//     it; none chosen yet. Do NOT reintroduce syncfusion_flutter_pdf casually:
//     it pulls xml ^7 and conflicts with appflowy_editor on the current SDK.
//  7. SYNC: strokes currently live only on this device. Decide whether the
//     backend (KnowledgebaseApi) should store them; if so, use stroke ids +
//     createdAt for merge, and consider soft-deletes.
//  8. HIGHLIGHTER BLEND: scribble has no blend mode, so highlights render as
//     translucent strokes (plain alpha) — the documented fallback. A real
//     BlendMode.multiply highlighter (if it even blends over pdfrx's page
//     image) would need a custom painter again. Check visually; revisit only
//     if plain alpha reads badly.
//  9. PERFORMANCE — RESOLVED: the store no longer broadcasts per pointer move
//     (scribble notifies on every move; AnnotationStore._onSketchChanged now
//     only debounces the save). Listeners that need live stroke state (the
//     reader's undo/redo buttons) listen to the page's ScribbleNotifier
//     directly. The PdfViewer rebuilds ONLY when drawing mode toggles
//     ([AnnotationStore.drawingListenable]); active-page changes go through a
//     separate ValueNotifier ([AnnotationStore.activePageListenable]) that only
//     the toolbar and tool dial follow, so pointer-down on a page can't rebuild
//     the viewer and its overlays mid-gesture. Still open: cache finished
//     strokes in a ui.Picture per page if painting a dense page ever shows up
//     in profiles.
// 10. RESOLVED — partial (split-stroke) erase + configurable radius shipped
//     with the editor's NoteDrawingLayer (_PartialEraser / splitErase).
// 11. TESTS — PARTIAL: the PageAnnotation JSON round trip (legacy blob, every
//     kind, unknown-kind passthrough) and the sketch<->annotation round trip
//     (points, width, highlighter alpha marker) are unit-tested in
//     test/page_annotation_test.dart. Undo/redo and normalization still need
//     coverage.
// =============================================================================

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:scribble/scribble.dart';
import 'package:shared_preferences/shared_preferences.dart';

// =============================================================================
// UNIFIED ANNOTATION MODEL
//
// One hierarchy for everything that can sit on a page. All coordinates are
// fractions (0..1) of the page's width/height with the origin TOP-LEFT — the
// model the ink layer has always used — so ink, markup quads and note anchors
// all survive zoom/resize and any future canonical-canvas change the same way.
//
// Wire format: a JSON array under `ink:<fileFingerprint>` (key UNCHANGED, so
// blobs written before this hierarchy existed still load). Every entry carries
// `t`; an entry with no `t` is ink, and an entry with an unknown `t` round-
// trips verbatim ([_UnknownAnnotation]) so an older app version can't delete
// annotations it doesn't understand.
// =============================================================================

/// One annotation on one page.
///
/// Only [InkAnnotation] has UI today; highlight and note are the storage
/// contract for the reader's next feature (text-snapped markup and sticky
/// notes), so persistence never grows a second shape later.
sealed class PageAnnotation {
  const PageAnnotation({required this.page});

  /// PDF page number (1-based, in the page's rotated space).
  final int page;

  /// Wire tag written as `t` and used by [PageAnnotation.fromJson] dispatch.
  /// Values are part of the on-disk contract — don't rename them.
  String get kind;

  Map<String, dynamic> toJson();

  /// Decodes one persisted entry. Never throws — not on an unknown kind, and
  /// not on an entry whose fields don't parse (truncated write, schema drift):
  /// a bad entry degrades to [_UnknownAnnotation] and round-trips verbatim
  /// instead of making [AnnotationStore.load] abort and drop every annotation
  /// on the file. Same contract as [_rectsFromJson] — one bad byte shouldn't
  /// cost the user their whole file.
  factory PageAnnotation.fromJson(Map<String, dynamic> j) {
    try {
      return switch (j['t']) {
        null || 'ink' => InkAnnotation.fromJson(j),
        'hl' => HighlightAnnotation.fromJson(j),
        'note' => NoteAnnotation.fromJson(j),
        _ => _UnknownAnnotation(j),
      };
    } catch (_) {
      return _UnknownAnnotation(j);
    }
  }
}

/// A freehand stroke. Points are normalized (0..1) relative to the page's
/// width/height, and [width] is a fraction of page width, so strokes stay
/// aligned at any zoom level or render size.
class InkAnnotation extends PageAnnotation {
  InkAnnotation({
    required super.page,
    required this.points,
    required this.color,
    required this.width,
    required this.highlighter,
  });

  final List<Offset> points;
  final Color color;
  final double width;

  /// Marker flag: true = highlighter (rendered translucent, alpha 0.4).
  final bool highlighter;

  @override
  String get kind => 'ink';

  @override
  Map<String, dynamic> toJson() => {
    't': kind,
    'p': page,
    'c': color.toARGB32(),
    'w': width,
    'h': highlighter,
    'pts': [
      for (final o in points) ...[o.dx, o.dy],
    ],
  };

  /// Accepts both the current entries (`t: 'ink'`) and pre-`t` legacy blobs.
  factory InkAnnotation.fromJson(Map<String, dynamic> j) {
    final flat = (j['pts'] as List).cast<num>();
    return InkAnnotation(
      page: j['p'] as int,
      color: Color(j['c'] as int),
      width: (j['w'] as num).toDouble(),
      highlighter: j['h'] as bool? ?? false,
      points: [
        for (var i = 0; i + 1 < flat.length; i += 2)
          Offset(flat[i].toDouble(), flat[i + 1].toDouble()),
      ],
    );
  }
}

/// Text-snapped markup — stored as rectangles, not freehand points: one
/// normalized quad per line of the selection (converted from pdfrx's text
/// rects), plus the colour and the quoted text for list/popup views.
class HighlightAnnotation extends PageAnnotation {
  HighlightAnnotation({
    required super.page,
    required this.quads,
    required this.color,
    this.text = '',
  });

  /// Selection rectangles in normalized page space (0..1, top-left origin).
  final List<Rect> quads;
  final Color color;

  /// The selected string this highlight is anchored to.
  final String text;

  @override
  String get kind => 'hl';

  @override
  Map<String, dynamic> toJson() => {
    't': kind,
    'p': page,
    'c': color.toARGB32(),
    'q': [for (final r in quads) _rectToJson(r)],
    'tx': text,
  };

  factory HighlightAnnotation.fromJson(Map<String, dynamic> j) =>
      HighlightAnnotation(
        page: j['p'] as int,
        color: Color(j['c'] as int),
        quads: _rectsFromJson(j['q']),
        text: j['tx'] as String? ?? '',
      );
}

/// A sticky note (Acrobat-style): a marker on the page that opens a popup
/// showing [text].
///
/// The marker sits at [position]; when the note was created from a text
/// selection, [quads] carries the anchor rects (empty when it was placed by a
/// plain tap). [createdAt] is stored as epoch milliseconds.
class NoteAnnotation extends PageAnnotation {
  NoteAnnotation({
    required super.page,
    required this.position,
    required this.quads,
    required this.text,
    required this.createdAt,
  });

  /// Marker position, normalized (0..1, top-left origin).
  final Offset position;

  /// Anchor rects of the selection the note was attached to (may be empty).
  final List<Rect> quads;

  final String text;
  final DateTime createdAt;

  @override
  String get kind => 'note';

  @override
  Map<String, dynamic> toJson() => {
    't': kind,
    'p': page,
    'x': position.dx,
    'y': position.dy,
    'q': [for (final r in quads) _rectToJson(r)],
    'tx': text,
    'ts': createdAt.millisecondsSinceEpoch,
  };

  factory NoteAnnotation.fromJson(Map<String, dynamic> j) => NoteAnnotation(
    page: j['p'] as int,
    position: Offset((j['x'] as num).toDouble(), (j['y'] as num).toDouble()),
    quads: _rectsFromJson(j['q']),
    text: j['tx'] as String? ?? '',
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      (j['ts'] as num?)?.toInt() ?? 0,
    ),
  );
}

/// An entry written by a NEWER version of the app (unknown `t`): kept exactly
/// as it was read so a downgrade doesn't delete what it can't render.
class _UnknownAnnotation extends PageAnnotation {
  _UnknownAnnotation(this.raw) : super(page: (raw['p'] as num?)?.toInt() ?? 0);

  final Map<String, dynamic> raw;

  @override
  String get kind => (raw['t'] ?? 'unknown').toString();

  @override
  Map<String, dynamic> toJson() => raw;
}

/// A rect as four numbers `[left, top, right, bottom]`, still in 0..1 space.
List<num> _rectToJson(Rect r) => [r.left, r.top, r.right, r.bottom];

/// Inverse of [_rectToJson]; malformed entries are skipped rather than
/// throwing — a single bad quad shouldn't cost the user their whole file.
List<Rect> _rectsFromJson(Object? raw) {
  final out = <Rect>[];
  for (final q in (raw as List? ?? const [])) {
    final c = (q as List).cast<num>();
    if (c.length == 4) {
      out.add(
        Rect.fromLTRB(
          c[0].toDouble(),
          c[1].toDouble(),
          c[2].toDouble(),
          c[3].toDouble(),
        ),
      );
    }
  }
  return out;
}

/// Brings persisted annotations for one page into a scribble [Sketch] in that
/// page's CANONICAL canvas space (PDF points, from PdfPage.width/height).
/// Only ink contributes strokes — markup and notes are painted by their own
/// layers (pending, header items 4/5). Highlighter strokes are stored
/// full-alpha + flag; we render them with the same translucent style the tool
/// dial produces (alpha 0.4).
Sketch sketchFromAnnotations(List<PageAnnotation> annotations, Size pageSize) {
  return Sketch(
    lines: [
      for (final s in annotations.whereType<InkAnnotation>())
        SketchLine(
          points: [
            for (final o in s.points)
              Point(o.dx * pageSize.width, o.dy * pageSize.height),
          ],
          color:
              (s.highlighter ? s.color.withValues(alpha: 0.4) : s.color)
                  .toARGB32(),
          width: s.width * pageSize.width,
        ),
    ],
  );
}

/// Converts one page's canonical-space [Sketch] back into normalized ink
/// annotations (non-ink annotations aren't in the sketch — they never enter
/// scribble, so they must not be re-derived from it; the store keeps them in
/// its unmaterialized list instead).
///
/// A line whose colour has alpha < 1 is a highlighter: the tool dial bakes
/// 0.4 alpha into highlight strokes and pen strokes are always opaque, so the
/// marker round-trips losslessly while scribble has no blend-mode support.
/// For highlighter lines the alpha is forced back to opaque in STORAGE, so the
/// invariant is "full-alpha colour + flag" on every save (not only the first
/// one); rendering reapplies 0.4, so nothing visual changes. This hack is
/// slated to die with the drift migration (item 1), where a real `highlighter`
/// column exists.
List<PageAnnotation> annotationsFromSketch(
  Sketch sketch,
  int page,
  Size pageSize,
) {
  final out = <PageAnnotation>[];
  for (final line in sketch.lines) {
    final color = Color(line.color);
    final highlighter = ((line.color >> 24) & 0xFF) != 0xFF;
    out.add(
      InkAnnotation(
        page: page,
        points: [
          for (final p in line.points)
            Offset(p.x / pageSize.width, p.y / pageSize.height),
        ],
        color: highlighter ? color.withValues(alpha: 1.0) : color,
        width: line.width / pageSize.width,
        highlighter: highlighter,
      ),
    );
  }
  return out;
}

/// Owns one scribble notifier per PDF page plus the [PageAnnotation]
/// persistence model, and broadcasts tool selections across pages (mirrors
/// PagedNoteController.applyDrawingTool, which the editor already proved).
///
/// The notifier for a page is created on demand; its sketch is materialized
/// from loaded ink only once the page's canonical size is known
/// ([setPageSize], called by ReaderInkPage), because loaded `width`/`points`
/// are normalized fractions that need the page size to denormalize. Saving
/// runs the opposite conversion. Non-ink annotations never enter scribble —
/// they stay in [_rawAnnotations] and are written straight back.
///
/// LISTENING: three channels, by how often they fire.
///  * [drawingListenable] — drawing mode on/off. The only thing the PdfViewer
///    rebuilds for (text selection is disabled while drawing), and what each
///    ink overlay follows for its IgnorePointer.
///  * [activePageListenable] — the active page. Followed by the undo/redo
///    buttons and the tool dial, NEVER by the viewer: it changes on
///    pointer-down, and rebuilding the viewer there rebuilt every ink overlay
///    in the middle of the gesture that was starting a stroke.
///  * the store itself (notifyListeners) — drawing-mode and tool-selection
///    changes and load completion, for the toolbar and the dial.
/// The store deliberately does NOT notify when a sketch changes — scribble
/// notifies on every pointer move, and broadcasting that used to rebuild the
/// reader's whole PdfViewer per move (header item 9). Anything that needs live
/// stroke state (undo/redo availability) must listen to the page's
/// [ScribbleNotifier] directly.
class AnnotationStore extends ChangeNotifier {
  AnnotationStore(this.fingerprint);

  final String fingerprint;

  /// Eraser mode toggle (partial ↔ whole-stroke), shared with ReaderInkPage
  /// and the tool dial. Same wiring as EditorScaffold.
  final ValueNotifier<bool> partialEraser = ValueNotifier(true);

  /// Eraser diameter in canonical canvas points, driven by the tool dial's
  /// size selector while the eraser is active.
  final ValueNotifier<double> eraserWidth = ValueNotifier(24);

  /// Which pointer kinds may draw. Stylus-only on touch-first platforms,
  /// stylus + mouse elsewhere. Touch always passes through to the viewer's
  /// pan/zoom (scribble's GestureCatcher only claims these kinds).
  ScribblePointerMode pointerMode = _defaultPointerMode();

  final Map<int, ScribbleNotifier> _notifiers = {};
  final Map<int, Size> _pageSizes = {};

  /// Active page, as its own notifier. Changing it must NOT rebuild the
  /// PdfViewer: it used to go through notifyListeners() during the pointer-down
  /// that starts a stroke, rebuilding the viewer and every ink overlay
  /// mid-gesture. Only the undo/redo buttons and the tool dial follow it.
  final ValueNotifier<int> activePageListenable = ValueNotifier(1);

  /// Whether the ink overlays take pointers. Independent of which tool is
  /// selected, exactly like the editor's `drawingEnabled`: entering drawing
  /// mode shows the dial and arms the overlays, and the last-used tool (or
  /// scribble's black/5 default) is already on every notifier. This is the
  /// ONLY store state the PdfViewer params depend on.
  final ValueNotifier<bool> drawingListenable = ValueNotifier(false);

  /// The currently selected tool broadcast (see [applyDrawingTool]), kept for
  /// notifiers created later. Survives leaving drawing mode so reopening
  /// restores the same pen/colour/size.
  void Function(ScribbleNotifier)? _activeTool;

  /// Loaded annotations that have NOT been materialized into a notifier: ink
  /// for pages whose canonical size isn't known yet, plus ALL highlight/note
  /// entries (they never enter a sketch). Drained by [_takeRawFor] / written
  /// back verbatim by [_saveNow].
  List<PageAnnotation> _rawAnnotations = [];
  Timer? _saveTimer;

  bool get drawing => drawingListenable.value;
  int get activePage => activePageListenable.value;

  /// Everything known for [page]: unmaterialized entries (ink whose canonical
  /// size isn't known yet, plus EVERY highlight/note — they never enter a
  /// sketch) merged with the ink held by the page's live sketch. The two sets
  /// are disjoint by construction ([_takeRawFor] drains the ink it seeds).
  ///
  /// Side-effect free: it does not create a notifier, so a rendering layer can
  /// inspect markup without arming that page for drawing.
  List<PageAnnotation> annotations(int page) {
    final out = <PageAnnotation>[
      for (final a in _rawAnnotations)
        if (a.page == page) a,
    ];
    final n = _notifiers[page];
    final size = _pageSizes[page];
    if (n != null && size != null) {
      out.addAll(annotationsFromSketch(n.currentSketch, page, size));
    }
    return out;
  }

  ScribbleNotifier get activeNotifier => notifierFor(activePage);

  /// The page's scribble canvas, created lazily. The first call also wires the
  /// save-listener; strokes are seeded once the page size is known.
  ScribbleNotifier notifierFor(int pageNumber) {
    final existing = _notifiers[pageNumber];
    if (existing != null) return existing;
    final n = ScribbleNotifier(allowedPointersMode: pointerMode)
      ..addListener(_onSketchChanged);
    _notifiers[pageNumber] = n;
    _materialize(n, pageNumber);
    return n;
  }

  /// Registers a page's canonical canvas size (PDF points). Called by
  /// ReaderInkPage on every build; idempotent. First registration for a page
  /// seeds its sketch from the loaded strokes.
  void setPageSize(int pageNumber, Size size) {
    if (_pageSizes[pageNumber] == size) return;
    _pageSizes[pageNumber] = size;
    final n = _notifiers[pageNumber];
    if (n != null) _materialize(n, pageNumber);
  }

  /// Undo/redo and the tool dial act on the page last touched. Updates a
  /// ValueNotifier only (a no-op when unchanged) — no store broadcast, so the
  /// viewer and its overlays never rebuild because of it.
  void setActivePage(int pageNumber) {
    activePageListenable.value = pageNumber;
  }

  /// Broadcast a tool config (from ToolDialHub's onSelectTool) to every page
  /// notifier, and remember it for pages created later — the same pattern as
  /// PagedNoteController.applyDrawingTool. Also enters drawing mode, so a
  /// caller that only knows how to pick a tool still ends up drawing.
  void applyDrawingTool(void Function(ScribbleNotifier) config) {
    _activeTool = config;
    for (final n in _notifiers.values) {
      config(n);
    }
    drawingListenable.value = true;
    notifyListeners();
  }

  /// Enters drawing mode: the tool dial appears and the overlays take
  /// pointers (only the pointer kinds in [pointerMode]; touch still scrolls).
  void enterDrawingMode() {
    if (drawing) return;
    drawingListenable.value = true;
    notifyListeners();
  }

  /// Leaves drawing mode: overlays stop taking pointers and the dial hides.
  /// Notifiers keep their last tool state, so reopening shows it.
  void exitDrawingMode() {
    if (!drawing) return;
    drawingListenable.value = false;
    notifyListeners();
  }

  void toggleDrawingMode() => drawing ? exitDrawingMode() : enterDrawingMode();

  void undo() => activeNotifier.undo();
  void redo() => activeNotifier.redo();

  // ---- persistence ---------------------------------------------------------
  // TODO(drift): replace this whole section; see header item 1.

  String get _key => 'ink:$fingerprint';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return;
    _rawAnnotations = [
      // Non-object elements (foreign/garbage values) are dropped; a bad OBJECT
      // is kept verbatim by PageAnnotation.fromJson — see its contract.
      for (final e in jsonDecode(raw) as List)
        if (e is Map<String, dynamic>) PageAnnotation.fromJson(e),
    ];
    // Pages whose overlays already built (before load finished) get their
    // ink now.
    for (final page in _notifiers.keys) {
      if (_pageSizes.containsKey(page)) {
        _materialize(_notifiers[page]!, page);
      }
    }
    notifyListeners();
  }

  void _materialize(ScribbleNotifier n, int pageNumber) {
    final size = _pageSizes[pageNumber];
    if (size == null) return;
    // If the canvas already holds live strokes (user drew before load()
    // finished), leave the persisted ink in _rawAnnotations — the next save
    // writes both, so neither the fresh drawing nor the old annotations are
    // lost.
    if (n.currentSketch.lines.isNotEmpty) {
      _activeTool?.call(n);
      return;
    }
    final ink = _takeRawFor(pageNumber);
    if (ink.isNotEmpty) {
      n.setSketch(
        sketch: sketchFromAnnotations(ink, size),
        addToUndoHistory: false,
      );
    }
    _activeTool?.call(n);
  }

  /// Removes and returns the still-unmaterialized INK for [pageNumber].
  ///
  /// Only ink is taken: markup and notes are never put into a sketch, so they
  /// must stay in [_rawAnnotations] or the next save would drop them.
  List<PageAnnotation> _takeRawFor(int pageNumber) {
    final out = <PageAnnotation>[];
    final rest = <PageAnnotation>[];
    for (final a in _rawAnnotations) {
      if (a.page == pageNumber && a is InkAnnotation) {
        out.add(a);
      } else {
        rest.add(a);
      }
    }
    _rawAnnotations = rest;
    return out;
  }

  /// Debounces the save ONLY. No notifyListeners here: scribble fires this on
  /// every pointer move, and broadcasting it rebuilt the reader's entire
  /// PdfViewer per move (header item 9). Live stroke state is listened to on
  /// the ScribbleNotifier itself; this store announces mode/tool changes.
  void _onSketchChanged() => _scheduleSave();

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), _saveNow);
  }

  Future<void> _saveNow() async {
    final prefs = await SharedPreferences.getInstance();
    // Unmaterialized ink + every markup/note entry (never in a sketch), plus
    // the ink derived from each page that has a live notifier.
    final out = <PageAnnotation>[
      ..._rawAnnotations,
      for (final MapEntry(key: page, value: n) in _notifiers.entries)
        if (_pageSizes[page] case final Size size)
          ...annotationsFromSketch(n.currentSketch, page, size),
    ];
    await prefs.setString(_key, jsonEncode([for (final a in out) a.toJson()]));
  }

  @override
  void dispose() {
    if (_saveTimer?.isActive ?? false) {
      _saveTimer!.cancel();
      _saveNow();
    }
    for (final n in _notifiers.values) {
      n.dispose();
    }
    partialEraser.dispose();
    eraserWidth.dispose();
    activePageListenable.dispose();
    drawingListenable.dispose();
    super.dispose();
  }

  static ScribblePointerMode _defaultPointerMode() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        // Touch-first devices: stylus draws, fingers scroll/zoom.
        return ScribblePointerMode.penOnly;
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        return ScribblePointerMode.mouseAndPen;
    }
  }
}
