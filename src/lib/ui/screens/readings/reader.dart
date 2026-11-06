// =============================================================================
// READER: STATUS + TODO (for a coding agent)
//
// ┌─────────────────────────────────────────────────────────────────────────┐
// │ NEW: ORIENTATION UI (progress strip / info chip / auto-hide bar / goals)│
// │                                                                         │
// │ Search for these tags in this file to find each feature:                │
// │   [TWEAK]        all tunable constants (sizes, thresholds, offsets)     │
// │   [UI-1 STRIP]   bottom dock: CHAPTER bar (top) + BOOK bar (bottom)     │
// │   [UI-2 CHIP]    "where you are" panel, shown only on `i`               │
// │   [UI-3 BAR]     auto-hiding app bar (overlay, NOT Scaffold.appBar)     │
// │   [UI-4 GOAL]    reading goal + pace / time estimates                   │
// │   [UI-5 PREFS]   accessibility + display options (persisted)            │
// │   [UI-6 TOAST]   chapter-finished / goal-reached moment                 │
// │   [UI-7 KEYS]    new vim keys: i  [[ ]]  gc  m  f  t                    │
// │   [POSITION]     _positionFor(): the one function all of the above read │
// │                                                                         │
// │ Rules these layers follow (so they don't break the crash fixes below):  │
// │  - The PdfViewer is only rebuilt on drawing-mode toggle. Every new UI   │
// │    piece listens to its OWN ValueNotifier (_pageNotifier, _prefs,       │
// │    _goal, _chipExpanded, _barAuto, _toast), never setState().           │
// │  - The app bar is an overlay in the Stack, so showing/hiding it never   │
// │    changes the viewer's constraints (no relayout, no zoom jumps).       │
// │  - This supersedes "nothing floats over the page" below: the strip and  │
// │    the chip are the only things that float, both small and both hidden  │
// │    or inert while drawing.                                              │
// └─────────────────────────────────────────────────────────────────────────┘
//
// pdfrx viewer with scribble-backed annotations. The annotation layer and its
// decision notes live in annotations.dart; the per-page canonical-canvas
// wrapper is in reader_ink_layer.dart. syncfusion_flutter_pdfviewer is removed
// from pubspec.yaml.
//
// Resolved since the syncfusion port:
//  - SCRIBBLE ADOPTED (annotations.dart DECISION): one ScribbleNotifier per
//    page inside a canonical-canvas FittedBox, so strokes never drift under
//    zoom/resize (gate b verified from Flutter's RenderFittedBox source + the
//    installed pdfrx/pdfrx_engine). Pen, highlighter (translucent — plain-alpha
//    fallback, annotations.dart item 8) and eraser (partial/whole) all flow
//    through the editor's existing NoteDrawingLayer; the custom
//    Listener/CustomPainter input path is deleted.
//  - OVERLAY SIZING (bug fixed): pdfrx's pageOverlaysBuilder gives the overlay
//    the zoomed page rect (pageRect) but NOT tight constraints, so a bare
//    FittedBox rendered the canvas at its natural 612x792 size in the page's
//    top-left corner; scribble's hover dot and drawing only worked inside that
//    box, and everywhere else the default cursor returned and drags panned.
//    ReaderInkPage now takes pageRect and forces it with an OverflowBox (see
//    reader_ink_layer.dart). Overlays are keyed by page number so elements
//    aren't reused across pages as pdfrx rebuilds the overlay list.
//  - PAN/ZOOM LOCK REMOVED: while drawing mode is on, scribble's
//    GestureCatcher claims only stylus/mouse pointers (store.pointerMode), so
//    touch still scrolls and pinches (annotations.dart item 2; gate a verified
//    from scribble's pan_gesture_catcher.dart supportedDevices).
//  - TOOLBAR = the editor's ToolDialHub, shown ONLY while drawing (same
//    coupling as EditorScaffold's drawingEnabled): the AppBar's Annotate
//    button enters drawing mode, Done leaves it, and the dial appears with it
//    — no separate "show the wheel state", so the first tap on a chip always
//    lands on an armed canvas. The dial is re-pointed at the active page's
//    notifier by listening to the store and the active-page notifier (a
//    captured notifier would undo the wrong page). Undo/redo in the AppBar
//    follow the active page's ScribbleNotifier directly: the store does not
//    broadcast per-sketch changes (see annotations.dart item 9), so the
//    buttons must listen where the state actually changes.
//  - REBUILD DISCIPLINE: the PdfViewer rebuilds ONLY when drawing mode toggles
//    (store.drawingListenable — text selection follows it). The active page
//    lives in its own ValueNotifier (store.activePageListenable) that only the
//    toolbar and dial follow, so touching a page (pointer-down) or scrolling to
//    another one never rebuilds the viewer or its overlays mid-gesture.
//  - ERROR HANDLING: pdfrx banners wired (errorBannerBuilder /
//    loadingBannerBuilder) — replaces Syncfusion's onDocumentLoadFailed snack.
//  - PAGE JUMP: KnowledgebaseApi.readFile is called with page: null so the
//    `#page=N` fragment never enters pdfrx's cache key (each fragment caused a
//    separate full download); initialPageNumber covers the jump.
//  - VIEWER STRUCTURE STABILITY (crash fix): the PdfViewer is NO LONGER owned
//    by a ValueListenableBuilder. Drawing-mode changes are mirrored into local
//    State via a listener, and the viewer carries a stable ValueKey so its
//    element (and pdfrx's internal State) survives every rebuild. The AppBar
//    toggle defers through addPostFrameCallback so the params swap never races
//    the pointer/wheel event that triggered it. Only params change on toggle
//    (textSelectionParams.enabled); the widget type and key never do.
//  - GO-TO-PAGE DIALOG (crash fix): the TextEditingController is owned by the
//    dialog's own State (_GoToPageDialog), NOT disposed right after
//    `await showDialog` — the route's exit animation keeps rebuilding the
//    TextField after the future completes, which hit a disposed controller.
//    (_ReaderOptionsDialog follows the same rule.)
//  - POSITION INDICATOR: the scroll thumb on the right edge keeps its simple
//    page number; hovering it pops up the chapter breadcrumb
//    (Part › Chapter › Section) and "Page X of Y". The breadcrumb comes from
//    the PDF outline, flattened once on load (_flatOutline); a page's section
//    is the last outline entry starting at or before it. PDFs without an
//    outline show only "Page X of Y". "Go to page" is an app-bar button.
//  - JUMP HISTORY: pages you jump AWAY from (gg/G/{n}G, go-to-page, links,
//    contents drawer) go into _recent (newest first, max 8, never contains the
//    current page). The app-bar history button lists them with their section;
//    ` (or ') swaps with the previous page, like vim's Ctrl+^. Plain scrolling,
//    Ctrl+f/b and search stepping are NOT recorded. The list is a plain field
//    read when the menu opens, so it never triggers a rebuild. Not persisted.
//  - VIM KEYS: the Reader owns a Focus node (own, or one handed in by the host,
//    e.g. FloatingReaderWindow) and handles keys while it has focus and no text
//    field is being typed in. j/k/h/l scroll, Ctrl+d/u half page, Ctrl+f/b page,
//    gg/G first/last page ("41G" = page 41, counts work on j/k/G/gg/Ctrl+f/b),
//    / search + n/N next/prev match, : go to page, o contents, a annotate,
//    u / Ctrl+r undo / redo, +/- zoom, ` jump back, Esc = clear / leave search /
//    leave drawing / hand focus back to the host (onReleaseFocus), ? = cheat
//    sheet. "r" (toggle the floating window) and Ctrl+w (swap focus with the
//    editor) live in the HOST (editor scaffold), not here.
//    New (see [UI-7 KEYS]): i chip, [[ / ]] chapter nav, gc chapter start,
//    m pin app bar, f focus mode, t goal & display.
//
// Still TODO (see annotations.dart for details):
//  - Device-verify stroke alignment after zooming, that stylus doesn't also pan
//    the viewer, and that rotated/cropped PDFs align (items a/b).
//  - TEXT SELECTION: enabled only when no tool is active. Wire selection into
//    text-snapped highlight/underline — the model is in place
//    (HighlightAnnotation), the pdfrx hook is item 4 in annotations.dart.
//  - STICKY NOTES UI (model ready: NoteAnnotation) / EXPORT / SYNC / drift
//    persistence (items 1, 5, 6, 7).
//  - Anything else that used SfPdfViewer / PdfViewerController from Syncfusion
//    elsewhere in the app must be ported too; grep for
//    `syncfusion_flutter_pdfviewer`.
//  - Orientation UI: persist daily goals / reading history across sessions;
//    the current goal is a single "stop at page N" target per file.
//  - Orientation UI: the app bar overlays the top of page 1 while visible. If
//    that bothers you, add top padding via PdfViewerParams (margin) — do NOT
//    go back to Scaffold.appBar (it resizes the viewer).
//  - FloatingReaderWindow draws 8px resize grips along its bottom edge; the
//    strip sits _stripBottomInset above the edge so the grips don't eat its
//    taps. Set the inset to 0 if you ever host the Reader without them.
// =============================================================================
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cerebrum/api/knowledgebase_api.dart';
import 'package:cerebrum/ui/screens/editor/widgets/radial_tool_dial.dart';
import 'package:cerebrum/ui/screens/readings/annotations.dart';
import 'package:cerebrum/ui/screens/readings/reader_ink_layer.dart';

/// One flattened table-of-contents entry: where a section starts and the
/// breadcrumb of titles leading to it (e.g. Part I › Chapter 1 › Clustering).
class _OutlineEntry {
  final String title;
  final int page;
  final List<String> trail;
  const _OutlineEntry(this.title, this.page, this.trail);

  /// 1 = top level of the outline, 2 = its children, ...
  int get depth => trail.length;
}

// =============================================================================
// [POSITION] Everything the orientation UI shows, derived from the page number
// and the flattened outline. Pure data: change the maths in _positionFor().
// =============================================================================
class _Position {
  final int page;
  final int total;
  final _OutlineEntry? chapter; // current chapter-level entry
  final _OutlineEntry? section; // current deepest entry (finest section)
  final _OutlineEntry? nextSection; // next entry of ANY depth
  final _OutlineEntry? nextChapter; // next chapter-level entry
  final int chapterStart; // first page of the chapter
  final int chapterEnd; // first page AFTER the chapter
  // The current SECTION (the outline level just below the chapter level):
  // [sectionStart, sectionEnd) in pages. The first segment of a chapter,
  // before its first section heading, counts as a section too.
  final int sectionStart;
  final int sectionEnd; // first page AFTER the section

  const _Position({
    required this.page,
    required this.total,
    required this.chapter,
    required this.section,
    required this.nextSection,
    required this.nextChapter,
    required this.chapterStart,
    required this.chapterEnd,
    required this.sectionStart,
    required this.sectionEnd,
  });

  /// Pages still to read after this one (0 = you're on the last page).
  int get pagesLeftInChapter => math.max(0, chapterEnd - 1 - page);

  /// True when the chapter is split into sections (otherwise the "section"
  /// would just be the whole chapter and the section UI stays hidden).
  bool get hasSections =>
      sectionStart > chapterStart || sectionEnd < chapterEnd;

  /// Pages still to read in this section after the current one.
  int get pagesLeftInSection => math.max(0, sectionEnd - 1 - page);

  double get sectionProgress =>
      ((page - sectionStart + 1) / math.max(1, sectionEnd - sectionStart))
          .clamp(0.0, 1.0)
          .toDouble();

  double get chapterProgress =>
      ((page - chapterStart + 1) / math.max(1, chapterEnd - chapterStart))
          .clamp(0.0, 1.0)
          .toDouble();

  double get bookProgress =>
      total <= 0 ? 0.0 : (page / total).clamp(0.0, 1.0).toDouble();

  List<String> get trail => (section ?? chapter)?.trail ?? const <String>[];

  String get chapterTitle => chapter?.title ?? 'Document';

  String get pagesLeftLabel =>
      pagesLeftInChapter == 0 ? 'last page' : '$pagesLeftInChapter left';
}

// =============================================================================
// [UI-4 GOAL] A "stop at page N" target, remembered per file.
// =============================================================================
class _Goal {
  final int start; // page you were on when you set it
  final int target; // page you want to have reached
  const _Goal(this.start, this.target);

  double progressAt(int page) {
    final span = math.max(1, target - start);
    return ((page - start) / span).clamp(0.0, 1.0).toDouble();
  }

  int leftAt(int page) => math.max(0, target - page);
}

// =============================================================================
// [UI-5 PREFS] Accessibility / display options. Persisted globally (not per
// file) except focusMode, which is a transient "get out of my way" switch.
// =============================================================================
enum _ChipMode { numbers, bar, both }

class _ReaderPrefs {
  final _ChipMode chipMode; // what the collapsed pill shows
  final bool highContrast; // inverted, max-contrast strip + chip
  final double textScale; // 1.0 / 1.25 / 1.5 on top of system text scale
  final bool focusMode; // hide bar + chip, keep only the strip
  final bool barPinned; // never auto-hide the app bar
  final bool showTime; // show time-left estimates

  const _ReaderPrefs({
    this.chipMode = _ChipMode.both,
    this.highContrast = false,
    this.textScale = 1.0,
    this.focusMode = false,
    this.barPinned = false,
    this.showTime = true,
  });

  _ReaderPrefs copyWith({
    _ChipMode? chipMode,
    bool? highContrast,
    double? textScale,
    bool? focusMode,
    bool? barPinned,
    bool? showTime,
  }) => _ReaderPrefs(
    chipMode: chipMode ?? this.chipMode,
    highContrast: highContrast ?? this.highContrast,
    textScale: textScale ?? this.textScale,
    focusMode: focusMode ?? this.focusMode,
    barPinned: barPinned ?? this.barPinned,
    showTime: showTime ?? this.showTime,
  );
}

String _fmtDuration(double seconds) {
  final minutes = (seconds / 60).round();
  if (minutes < 1) return '<1 min';
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

class Reader extends StatefulWidget {
  final String fileFingerprint;
  final int? page;

  /// Focus node for the Reader's vim keys. A host that needs to move focus here
  /// from outside (the floating window) passes its own; when null the Reader
  /// owns one and grabs focus on open (standalone page).
  final FocusNode? focusNode;

  /// Esc in the idle Reader: give focus back to the host (the editor).
  final VoidCallback? onReleaseFocus;

  const Reader({
    super.key,
    required this.fileFingerprint,
    this.page,
    this.focusNode,
    this.onReleaseFocus,
  });

  @override
  State<Reader> createState() => _ReaderState();
}

class _ReaderState extends State<Reader> {
  // ===========================================================================
  // [TWEAK] Every number you're likely to want to change lives here.
  // ===========================================================================

  // [UI-1 STRIP]
  static const _stripBottomInset =
      0.0; // dock sits flush; its padding clears the resize grips
  static const _stripHitHeight =
      32.0; // drawn area: pages-left number + flag + 2 bars
  static const _nearEndFraction = 0.9; // chapter bar turns accent past this

  // [UI-2 CHIP]
  static const _chipLeft = 12.0;
  static const _chipBottom = 74.0; // clears the progress dock (~64px tall)
  static const _panelMaxWidth = 360.0;

  // [UI-3 BAR] auto-hide behaviour
  static const _hideAfterPx = 60.0; // scroll down this far -> hide
  static const _revealAfterPx = 24.0; // scroll up this far -> show
  static const _atTopPx = 24.0; // within this of the top -> always show
  static const _hoverRevealZone = 14.0; // mouse at the top edge -> show

  // [CHAPTER DETECTION] null = auto: the shallowest outline depth with at
  // least _autoChapterMinCount entries (so "Part I" headings are skipped and
  // real chapters are used). Set to 1/2/3 to force a depth.
  static const int? _chapterDepthOverride = null;
  static const _autoChapterMinCount = 6;

  // [UI-4 GOAL] reading-pace estimate
  static const _paceMinSamples = 3; // pages before showing a time estimate
  static const _paceMaxSamples = 12; // rolling window
  static const _paceMinGap = Duration(seconds: 2); // faster = flicking, ignore
  static const _paceMaxGap = Duration(minutes: 2); // slower = you left, ignore

  // [UI-6 TOAST]
  static const _toastDuration = Duration(milliseconds: 3500);

  // ===========================================================================

  final _controller = PdfViewerController();
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _searchField = TextEditingController();
  final _searchFocus = FocusNode();

  FocusNode? _ownFocus;
  FocusNode get _vimFocus =>
      widget.focusNode ?? (_ownFocus ??= FocusNode(debugLabel: 'reader-vim'));

  late final AnnotationStore _store;
  // Created in onViewerReady: PdfTextSearcher needs a controller that is
  // already attached to a viewer, so it can't be built in initState.
  PdfTextSearcher? _searcher;
  late Future<AuthenticatedPdfData> _pdfDataFuture;

  List<PdfOutlineNode> _outline = const [];
  // Outline flattened in document order, for the "where am I" breadcrumb.
  List<_OutlineEntry> _flatOutline = const [];
  int _chapterDepth = 1;
  int _autoDepth = 1; // what auto-detection picked
  // User override of the chapter level (0 = auto), remembered per file.
  final _depthNotifier = ValueNotifier<int>(0);
  int _pageCount = 0;
  bool _searching = false;

  // Resume-where-you-left-off state.
  int _lastPage = 1;
  int? _pendingPage;
  Timer? _saveTimer;
  // Page callbacks that fire before the viewer is ready describe the initial
  // jump, not the user reading, so they must not overwrite the saved page.
  bool _viewerReady = false;

  // --- Orientation UI state: each piece has its OWN notifier so none of it
  // --- ever needs setState (which would rebuild the PdfViewer).
  final _pageNotifier = ValueNotifier<int>(1); // live current page
  final _prefs = ValueNotifier<_ReaderPrefs>(const _ReaderPrefs());
  final _goal = ValueNotifier<_Goal?>(null);
  final _chipExpanded = ValueNotifier<bool>(false);
  final _toast = ValueNotifier<String?>(null);
  final _barAuto = ValueNotifier<bool>(true); // scroll/hover wants the bar
  bool _scrollWantsBar = true;
  bool _hoverTop = false;
  bool _matrixListening = false;
  double? _lastMatrixY;
  double? _lastMatrixScale;
  double _scrollAccum = 0;
  Timer? _toastTimer;
  bool _goalAnnounced = false;

  // Pace tracking (seconds per page, rolling).
  final List<double> _paceSamples = [];
  DateTime? _lastPageTime;

  // Distinct prefix from the annotation store's `ink:<fingerprint>` keys.
  String get _pageKey => 'reader_last_page_${widget.fileFingerprint}';
  String get _goalKey => 'reader_goal_${widget.fileFingerprint}';
  String get _depthKey => 'reader_chapter_depth_${widget.fileFingerprint}';

  Future<void> _savePage(int page) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_pageKey, page);
  }

  // Debounced so fast scrolling doesn't write on every page.
  void _rememberPage(int page) {
    if (!_viewerReady) return;
    _pendingPage = page;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), () {
      _pendingPage = null;
      _savePage(page);
    });
  }

  @override
  void initState() {
    super.initState();
    _store = AnnotationStore(widget.fileFingerprint)..load();
    // The saved page must be known before the viewer is built:
    // initialPageNumber is only read when the document loads.
    _pdfDataFuture = () async {
      final prefs = await SharedPreferences.getInstance();
      _lastPage = prefs.getInt(_pageKey) ?? 1;
      _pageNotifier.value = widget.page ?? _lastPage;
      return KnowledgebaseApi.readFile(widget.fileFingerprint, null);
    }();
    _store.drawingListenable.addListener(_onDrawingChanged);
    _searchFocus.onKeyEvent = _onSearchKey;
    _loadPrefs();
    _loadGoal();
    _loadDepth();
  }

  void _onDrawingChanged() {
    if (!mounted) return;
    // Searching and drawing don't mix: leave search when annotating starts.
    if (_store.drawing && _searching) {
      _closeSearch();
    } else {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _store.drawingListenable.removeListener(_onDrawingChanged);
    _store.dispose();
    if (_matrixListening) {
      try {
        _controller.removeListener(_onViewerMatrix);
      } catch (_) {
        // The viewer may already be detached; nothing to remove.
      }
    }
    // Flush the debounced page so leaving right after a scroll isn't lost.
    _saveTimer?.cancel();
    _toastTimer?.cancel();
    final pending = _pendingPage;
    if (pending != null) _savePage(pending); // fire and forget
    _searcher?.dispose();
    _searchField.dispose();
    _searchFocus.dispose();
    _ownFocus?.dispose();
    _pageNotifier.dispose();
    _prefs.dispose();
    _goal.dispose();
    _chipExpanded.dispose();
    _toast.dispose();
    _barAuto.dispose();
    _depthNotifier.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Jump history
  // ---------------------------------------------------------------------------

  static const _maxRecent = 8;
  // Pages you jumped away from, most recent first. Never contains the current
  // page. Read only when the menu opens, so it needs no setState / rebuilds.
  final List<int> _recent = [];

  void _pushRecent(int page) {
    _recent.remove(page);
    _recent.insert(0, page);
    if (_recent.length > _maxRecent) _recent.removeLast();
  }

  // Call just before navigating to [target]: remembers where we are leaving.
  void _noteDeparture(int target) {
    final from = _controller.pageNumber;
    if (from != null && from != target) _pushRecent(from);
  }

  void _goToPage(int page, {bool record = true}) {
    if (!_controller.isReady) return;
    final target = page.clamp(1, _controller.pageCount).toInt();
    if (record) _noteDeparture(target);
    _controller.goToPage(pageNumber: target);
  }

  Future<void> _goToDest(PdfDest dest) async {
    final target = dest.pageNumber;
    if (target != null) _noteDeparture(target);
    await _controller.goToDest(dest);
  }

  // Jump to a page from the history; the page we leave becomes the newest
  // entry, so picking the top item repeatedly toggles between two pages.
  void _jumpToRecent(int target) {
    if (!_controller.isReady) return;
    _recent.remove(target);
    final from = _controller.pageNumber;
    if (from != null && from != target) _pushRecent(from);
    _controller.goToPage(pageNumber: target);
  }

  void _jumpBack() {
    if (_recent.isNotEmpty) _jumpToRecent(_recent.first);
  }

  String _recentLabel(int page) {
    final section = _sectionFor(page)?.title;
    return section == null ? 'Page $page' : 'p. $page  ·  $section';
  }

  // ---------------------------------------------------------------------------
  // Links
  // ---------------------------------------------------------------------------

  Future<void> _onLinkTap(PdfLink link) async {
    // Don't navigate while the user is annotating.
    if (_store.drawing) return;

    final dest = link.dest;
    if (dest != null) {
      await _goToDest(dest);
      return;
    }
    final url = link.url;
    if (url != null) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  // ---------------------------------------------------------------------------
  // Outline (table of contents)
  // ---------------------------------------------------------------------------

  Future<void> _loadOutline(PdfDocument document) async {
    try {
      final outline = await document.loadOutline();
      if (mounted) {
        setState(() {
          _outline = outline;
          _flatOutline = _flatten(outline, const []);
          _autoDepth = _detectChapterDepth(_flatOutline);
          final pref = _depthNotifier.value;
          _chapterDepth = pref > 0 ? pref : _autoDepth;
        });
      }
    } catch (_) {
      // A broken outline shouldn't stop the document from being readable.
    }
  }

  // Depth-first flatten, preserving document order and the title trail.
  List<_OutlineEntry> _flatten(List<PdfOutlineNode> nodes, List<String> trail) {
    final out = <_OutlineEntry>[];
    for (final n in nodes) {
      final t = [...trail, n.title];
      final page = n.dest?.pageNumber;
      if (page != null) out.add(_OutlineEntry(n.title, page, t));
      out.addAll(_flatten(n.children, t));
    }
    return out;
  }

  // The section containing [page]: the last entry starting at or before it.
  _OutlineEntry? _sectionFor(int page) {
    _OutlineEntry? current;
    for (final e in _flatOutline) {
      if (e.page <= page) {
        current = e;
      } else {
        break;
      }
    }
    return current;
  }

  // [CHAPTER DETECTION] Which outline depth counts as "a chapter"? Books often
  // have 3-4 "Part" headings above the real chapters; those are skipped by
  // requiring a depth to have several entries.
  int _detectChapterDepth(List<_OutlineEntry> flat) {
    final override = _chapterDepthOverride;
    if (override != null) return override;
    final counts = <int, int>{};
    for (final e in flat) {
      counts[e.depth] = (counts[e.depth] ?? 0) + 1;
    }
    final depths = counts.keys.toList()..sort();
    for (final d in depths) {
      if ((counts[d] ?? 0) >= _autoChapterMinCount) return d;
    }
    return depths.isEmpty ? 1 : depths.first;
  }

  // ---------------------------------------------------------------------------
  // [POSITION] The one function the strip, chip, toast and keys all read.
  // ---------------------------------------------------------------------------

  _Position _positionFor(int page) {
    final total = _pageCount > 0 ? _pageCount : math.max(1, page);
    _OutlineEntry? chapter, section, nextSection, nextChapter;
    var passed = false;
    for (final e in _flatOutline) {
      if (!passed && e.page <= page) {
        section = e;
        // The last entry at or above chapter depth is the current chapter
        // (a Part heading counts when no chapter has started under it yet).
        if (e.depth <= _chapterDepth) chapter = e;
        continue;
      }
      passed = true;
      if (e.page > page) {
        nextSection ??= e;
        if (e.depth <= _chapterDepth) nextChapter ??= e;
      }
    }
    final chStart = chapter?.page ?? 1;
    final chEnd = nextChapter?.page ?? total + 1;
    // [SECTION] the level directly below the chapter level (same level the
    // CH bar draws its ticks for): the last such heading at/before this page
    // inside the chapter, up to the next heading of that level or shallower.
    final secDepth = _chapterDepth + 1;
    var secStart = chStart;
    int? secEndPage;
    for (final e in _flatOutline) {
      if (e.page <= page) {
        if (e.depth == secDepth && e.page >= secStart) secStart = e.page;
      } else if (e.depth <= secDepth) {
        secEndPage = e.page;
        break;
      }
    }
    return _Position(
      page: page,
      total: total,
      chapter: chapter,
      section: section,
      nextSection: nextSection,
      nextChapter: nextChapter,
      chapterStart: chStart,
      chapterEnd: chEnd,
      sectionStart: secStart,
      sectionEnd: math.min(secEndPage ?? total + 1, chEnd),
    );
  }

  // Page boundaries of every chapter-level entry as 0..1 fractions (strip ticks).
  List<double> _chapterTicks() {
    if (_pageCount <= 0) return const [];
    return [
      for (final e in _flatOutline)
        if (e.depth <= _chapterDepth && e.page > 1) (e.page - 1) / _pageCount,
    ];
  }

  // Section boundaries INSIDE the current chapter as 0..1 fractions of that
  // chapter (drawn on the strip's chapter bar). Only the level directly below
  // the chapter level, so sub-sub-sections don't clutter the bar.
  List<double> _sectionTicks(_Position pos) {
    final span = pos.chapterEnd - pos.chapterStart;
    if (span <= 0) return const [];
    return [
      for (final e in _flatOutline)
        if (e.depth == _chapterDepth + 1 &&
            e.page > pos.chapterStart &&
            e.page < pos.chapterEnd)
          (e.page - pos.chapterStart) / span,
    ];
  }

  // [CHAPTER DETECTION] runtime override (options dialog): 0 = auto.
  int get _maxOutlineDepth {
    var d = 1;
    for (final e in _flatOutline) {
      if (e.depth > d) d = e.depth;
    }
    return math.min(d, 4);
  }

  Future<void> _loadDepth() async {
    final sp = await SharedPreferences.getInstance();
    final d = sp.getInt(_depthKey) ?? 0;
    if (!mounted) return;
    _chapterDepth = d > 0 ? d : _autoDepth;
    _depthNotifier.value = d;
  }

  Future<void> _setChapterDepth(int d) async {
    _chapterDepth = d > 0 ? d : _autoDepth;
    _depthNotifier.value = d;
    final sp = await SharedPreferences.getInstance();
    await sp.setInt(_depthKey, d);
  }

  // Chapter navigation (used by chip buttons, tiles and [[ / ]] / gc keys).
  void _nextChapter() {
    final next = _positionFor(_pageNotifier.value).nextChapter;
    if (next != null) _goToPage(next.page);
  }

  void _chapterStart() {
    final chapter = _positionFor(_pageNotifier.value).chapter;
    if (chapter != null) _goToPage(chapter.page);
  }

  // [[ : start of this chapter, or (if already there) the previous chapter.
  void _prevChapter() {
    final page = _pageNotifier.value;
    final chapter = _positionFor(page).chapter;
    if (chapter != null && page > chapter.page) {
      _goToPage(chapter.page);
      return;
    }
    _OutlineEntry? prev;
    for (final e in _flatOutline) {
      if (e.depth <= _chapterDepth && e.page < page) prev = e;
    }
    if (prev != null) _goToPage(prev.page);
  }

  Widget _outlineTile(PdfOutlineNode node, {double indent = 0}) {
    void jump() {
      Navigator.of(context).pop(); // close the end drawer
      final dest = node.dest;
      if (dest != null) _goToDest(dest);
    }

    if (node.children.isEmpty) {
      return ListTile(
        contentPadding: EdgeInsets.only(left: 16 + indent, right: 16),
        dense: true,
        title: Text(node.title),
        onTap: jump,
      );
    }
    return ExpansionTile(
      tilePadding: EdgeInsets.only(left: 16 + indent, right: 16),
      title: Text(node.title),
      children: [
        ListTile(
          contentPadding: EdgeInsets.only(left: 32 + indent, right: 16),
          dense: true,
          leading: const Icon(Icons.subdirectory_arrow_right, size: 16),
          title: const Text('Go to section'),
          onTap: jump,
        ),
        for (final child in node.children)
          _outlineTile(child, indent: indent + 16),
      ],
    );
  }

  Widget _outlineDrawer() {
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Contents',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                children: [for (final n in _outline) _outlineTile(n)],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Search
  // ---------------------------------------------------------------------------

  void _openSearch() {
    if (_store.drawing) return;
    setState(() => _searching = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  void _closeSearch() {
    _searcher?.resetTextSearch();
    _searchField.clear();
    setState(() => _searching = false);
  }

  void _runSearch(String query) {
    final searcher = _searcher;
    if (searcher == null) return;
    if (query.trim().isEmpty) {
      searcher.resetTextSearch();
    } else {
      searcher.startTextSearch(query, caseInsensitive: true);
    }
  }

  Widget _searchTitle() {
    return TextField(
      controller: _searchField,
      focusNode: _searchFocus,
      textInputAction: TextInputAction.search,
      decoration: const InputDecoration(
        hintText: 'Search in document',
        border: InputBorder.none,
      ),
      onChanged: _runSearch,
      onSubmitted: (_) {
        // Vim-style: Enter jumps to the match and returns to the page so
        // n / N keep stepping; Esc then clears the search.
        _searcher?.goToNextMatch();
        _vimFocus.requestFocus();
      },
    );
  }

  List<Widget> _searchActions() {
    return [
      ListenableBuilder(
        listenable: Listenable.merge([if (_searcher != null) _searcher!]),
        builder: (context, _) {
          final total = _searcher?.matches.length ?? 0;
          final current = _searcher?.currentIndex;
          final label =
              (_searcher?.isSearching ?? false)
                  ? '…'
                  : total == 0
                  ? (_searchField.text.isEmpty ? '' : '0')
                  : '${(current ?? 0) + 1}/$total';
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(label),
            ),
          );
        },
      ),
      IconButton(
        tooltip: 'Previous match',
        icon: const Icon(Icons.keyboard_arrow_up),
        onPressed: () => _searcher?.goToPrevMatch(),
      ),
      IconButton(
        tooltip: 'Next match',
        icon: const Icon(Icons.keyboard_arrow_down),
        onPressed: () => _searcher?.goToNextMatch(),
      ),
      IconButton(
        tooltip: 'Close search',
        icon: const Icon(Icons.close),
        onPressed: _closeSearch,
      ),
    ];
  }

  // ---------------------------------------------------------------------------
  // Page indicator / jump to page
  // ---------------------------------------------------------------------------

  Future<void> _promptJumpToPage() async {
    if (!_controller.isReady) return;
    final pageCount = _controller.pageCount;
    // The dialog owns (and disposes) its own TextEditingController: disposing
    // it here, right after showDialog returns, races the route's exit
    // animation and crashes with "used after being disposed".
    final result = await showDialog<int>(
      context: context,
      builder: (_) => _GoToPageDialog(pageCount: pageCount),
    );
    if (result != null && result >= 1 && result <= pageCount) {
      _goToPage(result);
    }
  }

  // Popup text for the scroll-thumb hover: the full breadcrumb for [page]
  // (Part › Chapter › Section) plus "Page X of Y".
  String _positionTip(int page) {
    final trail = _sectionFor(page)?.trail ?? const <String>[];
    final total = _controller.isReady ? _controller.pageCount : 0;
    return [
      if (trail.isNotEmpty) trail.join('\n  › '),
      total > 0 ? 'Page $page of $total' : 'Page $page',
    ].join('\n');
  }

  // ===========================================================================
  // [UI-5 PREFS] load / save / change
  // ===========================================================================

  Future<void> _loadPrefs() async {
    final sp = await SharedPreferences.getInstance();
    final modeIdx =
        (sp.getInt('reader_pref_chip_mode') ?? _ChipMode.both.index)
            .clamp(0, _ChipMode.values.length - 1)
            .toInt();
    var scale = sp.getDouble('reader_pref_text_scale') ?? 1.0;
    if (scale != 1.0 && scale != 1.25 && scale != 1.5) scale = 1.0;
    final loaded = _ReaderPrefs(
      chipMode: _ChipMode.values[modeIdx],
      highContrast: sp.getBool('reader_pref_high_contrast') ?? false,
      textScale: scale,
      barPinned: sp.getBool('reader_pref_bar_pinned') ?? false,
      showTime: sp.getBool('reader_pref_show_time') ?? true,
    );
    if (mounted) _prefs.value = loaded;
  }

  Future<void> _savePrefs(_ReaderPrefs p) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setInt('reader_pref_chip_mode', p.chipMode.index);
    await sp.setBool('reader_pref_high_contrast', p.highContrast);
    await sp.setDouble('reader_pref_text_scale', p.textScale);
    await sp.setBool('reader_pref_bar_pinned', p.barPinned);
    await sp.setBool('reader_pref_show_time', p.showTime);
  }

  void _setPrefs(_ReaderPrefs p) {
    _prefs.value = p;
    _savePrefs(p);
  }

  // ===========================================================================
  // [UI-4 GOAL] goal + pace
  // ===========================================================================

  Future<void> _loadGoal() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_goalKey);
    if (raw == null) return;
    final parts = raw.split(':');
    if (parts.length != 2) return;
    final start = int.tryParse(parts[0]);
    final target = int.tryParse(parts[1]);
    if (start == null || target == null || !mounted) return;
    _goal.value = _Goal(start, target);
    _goalAnnounced = _pageNotifier.value >= target;
  }

  Future<void> _setGoal(int? target) async {
    final sp = await SharedPreferences.getInstance();
    if (target == null) {
      _goal.value = null;
      await sp.remove(_goalKey);
      return;
    }
    final start = _pageNotifier.value;
    _goal.value = _Goal(start, target);
    _goalAnnounced = start >= target;
    await sp.setString(_goalKey, '$start:$target');
  }

  // Median of recent seconds-per-page samples; null until there are enough.
  double? get _secPerPage {
    if (_paceSamples.length < _paceMinSamples) return null;
    final sorted = [..._paceSamples]..sort();
    return sorted[sorted.length ~/ 2];
  }

  // Called from onPageChanged. Never calls setState.
  void _onPageForProgress(int page) {
    final prev = _pageNotifier.value;
    if (page == prev) return;
    final now = DateTime.now();
    final forwardStep = page > prev && page - prev <= 2;

    // Pace: only count natural forward reading, ignore jumps and idle gaps.
    final last = _lastPageTime;
    if (_viewerReady && last != null && forwardStep) {
      final dt = now.difference(last);
      if (dt > _paceMinGap && dt < _paceMaxGap) {
        _paceSamples.add(dt.inMilliseconds / 1000.0 / (page - prev));
        if (_paceSamples.length > _paceMaxSamples) _paceSamples.removeAt(0);
      }
    }
    _lastPageTime = now;

    // [UI-6 TOAST] crossed a chapter boundary while reading forward.
    if (_viewerReady && forwardStep && _flatOutline.isNotEmpty) {
      final before = _positionFor(prev).chapter;
      final after = _positionFor(page).chapter;
      if (before != null && after != null && !identical(before, after)) {
        _celebrate('Finished: ${before.title}');
      }
    }

    // Goal reached.
    final goal = _goal.value;
    if (_viewerReady &&
        goal != null &&
        !_goalAnnounced &&
        page >= goal.target) {
      _goalAnnounced = true;
      _celebrate('Reading goal reached (p. ${goal.target})');
    }

    _pageNotifier.value = page;
  }

  // ===========================================================================
  // [UI-6 TOAST]
  // ===========================================================================

  void _celebrate(String message) {
    HapticFeedback.lightImpact();
    _toast.value = message;
    _toastTimer?.cancel();
    _toastTimer = Timer(_toastDuration, () {
      if (mounted) _toast.value = null;
    });
  }

  // ===========================================================================
  // [UI-3 BAR] auto-hide: scroll direction + hover, no setState
  // ===========================================================================

  void _attachMatrixListener() {
    if (_matrixListening) return;
    _matrixListening = true;
    _controller.addListener(_onViewerMatrix);
  }

  // Watches the viewer's transform: scrolling down hides the bar, scrolling up
  // (or being near the top of the document) shows it. Zoom changes are ignored
  // so pinching never toggles it.
  void _onViewerMatrix() {
    if (!_controller.isReady) return;
    final m = _controller.value.storage;
    final y = m[13];
    final scale = m[0];
    final lastY = _lastMatrixY;
    final lastScale = _lastMatrixScale;
    _lastMatrixY = y;
    _lastMatrixScale = scale;
    if (lastY == null || lastScale == null) return;
    if ((scale - lastScale).abs() > 1e-6) return; // zooming, not scrolling

    final dy = y - lastY; // negative = reading downward
    if (dy.abs() < 0.5) return;

    var wants = _scrollWantsBar;
    if (y > -_atTopPx) {
      wants = true;
      _scrollAccum = 0;
    } else {
      // Reset the running total when direction flips.
      if ((dy > 0) != (_scrollAccum > 0)) _scrollAccum = 0;
      _scrollAccum += dy;
      if (_scrollAccum < -_hideAfterPx) {
        wants = false;
      } else if (_scrollAccum > _revealAfterPx) {
        wants = true;
      }
    }
    if (wants != _scrollWantsBar) {
      _scrollWantsBar = wants;
      // Microtask: this listener can fire during layout, and the notifier's
      // listeners mark widgets dirty.
      scheduleMicrotask(() {
        if (mounted) _syncBarAuto();
      });
    }
  }

  void _syncBarAuto() => _barAuto.value = _scrollWantsBar || _hoverTop;

  void _setHover(bool v) {
    if (_hoverTop == v) return;
    _hoverTop = v;
    _syncBarAuto();
  }

  // Mouse near the top edge reveals the bar; moving well below it releases.
  void _onViewerHoverDy(double dy) {
    if (dy < _hoverRevealZone) {
      _setHover(true);
    } else if (dy > kToolbarHeight + 8) {
      _setHover(false);
    }
  }

  // ---------------------------------------------------------------------------
  // Vim keys
  // ---------------------------------------------------------------------------

  static const _scrollStep = 80.0; // px per j/k/h/l press

  // Count prefix ("5j", "41G") and the pending first key of "gg" / "gc" / "[[".
  String _count = '';
  String? _pendingKey;
  DateTime? _pendingAt;

  bool get _hasCount => _count.isNotEmpty;

  int _takeCount() {
    final n = int.tryParse(_count) ?? 1;
    _count = '';
    return n < 1 ? 1 : n;
  }

  // True while a text field (search box, go-to-page dialog, ...) has focus:
  // letters must be typed, not run as commands.
  bool _typingInTextField() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    return ctx.widget is EditableText ||
        ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  void _scrollBy({double dx = 0, double dy = 0}) {
    if (!_controller.isReady) return;
    final m = _controller.value.clone();
    m.storage[12] -= dx; // translation x
    m.storage[13] -= dy; // translation y
    _controller.goTo(m, duration: const Duration(milliseconds: 80));
  }

  double _viewportHeight() => context.size?.height ?? 600;

  // Deferred like the app-bar button so the params swap never races the key.
  void _toggleDrawing() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _store.toggleDrawingMode();
    });
  }

  // Esc inside the search box: close the search and return to the page.
  KeyEventResult _onSearchKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      _closeSearch();
      _vimFocus.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  static final _modifierKeys = <LogicalKeyboardKey>{
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
    LogicalKeyboardKey.capsLock,
  };

  KeyEventResult _onVimKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (_typingInTextField()) return KeyEventResult.ignored;

    final hk = HardwareKeyboard.instance;
    if (hk.isAltPressed || hk.isMetaPressed) return KeyEventResult.ignored;
    final ctrl = hk.isControlPressed;
    final shift = hk.isShiftPressed;
    final key = event.logicalKey;
    final ch = event.character;
    const handled = KeyEventResult.handled;

    // A bare modifier press (e.g. Shift for "G") must not cancel a pending
    // two-key sequence like "gg".
    if (_modifierKeys.contains(key)) return KeyEventResult.ignored;

    // Was a lone first key (g, [, ]) pressed just before this one?
    final pendingChar =
        _pendingKey != null &&
                _pendingAt != null &&
                DateTime.now().difference(_pendingAt!) <
                    const Duration(milliseconds: 600)
            ? _pendingKey
            : null;
    final pendingG = pendingChar == 'g';
    _pendingKey = null;
    _pendingAt = null;

    // Esc: peel back one layer per press.
    if (key == LogicalKeyboardKey.escape) {
      final scaffold = _scaffoldKey.currentState;
      if (scaffold?.isEndDrawerOpen ?? false) {
        scaffold?.closeEndDrawer();
      } else if (_hasCount || pendingChar != null) {
        _count = '';
      } else if (_store.drawing) {
        _toggleDrawing();
      } else if (_searching) {
        _closeSearch();
      } else if (_chipExpanded.value) {
        _chipExpanded.value = false;
      } else if (_prefs.value.focusMode) {
        _setPrefs(_prefs.value.copyWith(focusMode: false));
      } else {
        widget.onReleaseFocus?.call();
      }
      return handled;
    }

    // While annotating only undo/redo/toggle are keys; the rest is the pen's.
    if (_store.drawing) {
      if (ctrl && key == LogicalKeyboardKey.keyR) {
        _store.redo();
        return handled;
      }
      if (!ctrl && key == LogicalKeyboardKey.keyU) {
        _store.undo();
        return handled;
      }
      if (!ctrl && !shift && key == LogicalKeyboardKey.keyA) {
        _toggleDrawing();
        return handled;
      }
      return KeyEventResult.ignored;
    }

    if (ctrl) {
      if (shift) return KeyEventResult.ignored;
      if (key == LogicalKeyboardKey.keyD) {
        _scrollBy(dy: _viewportHeight() / 2 * _takeCount());
        return handled;
      }
      if (key == LogicalKeyboardKey.keyU) {
        _scrollBy(dy: -_viewportHeight() / 2 * _takeCount());
        return handled;
      }
      if (key == LogicalKeyboardKey.keyF) {
        _goToPage((_controller.pageNumber ?? 1) + _takeCount(), record: false);
        return handled;
      }
      if (key == LogicalKeyboardKey.keyB) {
        _goToPage((_controller.pageNumber ?? 1) - _takeCount(), record: false);
        return handled;
      }
      if (key == LogicalKeyboardKey.keyR) {
        _store.redo();
        return handled;
      }
      return KeyEventResult.ignored; // Ctrl+w etc. belong to the host
    }

    // Count prefix. A leading 0 is not a count (vim: 0 is its own command).
    if (ch != null &&
        ch.length == 1 &&
        ch.compareTo('0') >= 0 &&
        ch.compareTo('9') <= 0 &&
        !(ch == '0' && _count.isEmpty)) {
      _count += ch;
      return handled;
    }

    // -------------------------------------------------------------------------
    // [UI-7 KEYS] new orientation keys
    // -------------------------------------------------------------------------
    // ]] next chapter, [[ start of this chapter / previous chapter.
    if (ch == ']' || ch == '[') {
      _count = '';
      if (pendingChar == ch) {
        if (ch == ']') {
          _nextChapter();
        } else {
          _prevChapter();
        }
      } else {
        _pendingKey = ch;
        _pendingAt = DateTime.now();
      }
      return handled;
    }
    // gc = go to the start of the current chapter.
    if (!shift && pendingG && key == LogicalKeyboardKey.keyC) {
      _count = '';
      _chapterStart();
      return handled;
    }
    // i = expand / collapse the "where you are" chip.
    if (!shift && key == LogicalKeyboardKey.keyI) {
      _chipExpanded.value = !_chipExpanded.value;
      return handled;
    }
    // m = pin the app bar (never auto-hide) on / off.
    if (!shift && key == LogicalKeyboardKey.keyM) {
      final p = _prefs.value;
      _setPrefs(p.copyWith(barPinned: !p.barPinned));
      return handled;
    }
    // f = focus mode: hide app bar + chip, keep only the progress strip.
    if (!shift && key == LogicalKeyboardKey.keyF) {
      final p = _prefs.value;
      _setPrefs(p.copyWith(focusMode: !p.focusMode));
      return handled;
    }
    // t = goal & display options.
    if (!shift && key == LogicalKeyboardKey.keyT) {
      _showOptions();
      return handled;
    }

    if (key == LogicalKeyboardKey.keyG) {
      if (shift) {
        // G = last page, {n}G = page n.
        _goToPage(
          _hasCount
              ? _takeCount()
              : (_controller.isReady ? _controller.pageCount : 1),
        );
      } else if (pendingG) {
        // gg = first page, {n}gg = page n.
        _goToPage(_hasCount ? _takeCount() : 1);
      } else {
        _pendingKey = 'g';
        _pendingAt = DateTime.now();
      }
      return handled;
    }

    if (!shift && key == LogicalKeyboardKey.keyJ) {
      _scrollBy(dy: _scrollStep * _takeCount());
      return handled;
    }
    if (!shift && key == LogicalKeyboardKey.keyK) {
      _scrollBy(dy: -_scrollStep * _takeCount());
      return handled;
    }
    if (!shift && key == LogicalKeyboardKey.keyH) {
      _scrollBy(dx: -_scrollStep * _takeCount());
      return handled;
    }
    if (!shift && key == LogicalKeyboardKey.keyL) {
      _scrollBy(dx: _scrollStep * _takeCount());
      return handled;
    }
    if (key == LogicalKeyboardKey.space) {
      _scrollBy(dy: _viewportHeight() * 0.9 * (shift ? -1 : 1) * _takeCount());
      return handled;
    }

    if (key == LogicalKeyboardKey.keyN) {
      _count = '';
      if (shift) {
        _searcher?.goToPrevMatch();
      } else {
        _searcher?.goToNextMatch();
      }
      return handled;
    }

    if (ch == '/') {
      _count = '';
      _openSearch();
      return handled;
    }
    if (ch == ':') {
      _count = '';
      _promptJumpToPage();
      return handled;
    }
    if (ch == '?') {
      _count = '';
      _showVimHelp();
      return handled;
    }
    if (ch == '`' || ch == "'") {
      _count = '';
      _jumpBack();
      return handled;
    }
    if (ch == '+' || ch == '=') {
      _controller.zoomUp();
      return handled;
    }
    if (ch == '-') {
      _controller.zoomDown();
      return handled;
    }

    if (!shift && key == LogicalKeyboardKey.keyO) {
      if (_outline.isNotEmpty) _scaffoldKey.currentState?.openEndDrawer();
      return handled;
    }
    if (!shift && key == LogicalKeyboardKey.keyA) {
      _toggleDrawing();
      return handled;
    }
    if (!shift && key == LogicalKeyboardKey.keyU) {
      if (_store.activeNotifier.canUndo) _store.undo();
      return handled;
    }

    return KeyEventResult.ignored;
  }

  void _showVimHelp() {
    const rows = <(String, String)>[
      ('j / k', 'scroll down / up  (5j = 5 steps)'),
      ('h / l', 'scroll left / right'),
      ('Ctrl+d / u', 'half page down / up'),
      ('Ctrl+f / b', 'next / previous page'),
      ('Space', 'page down  (Shift+Space = up)'),
      ('gg / G', 'first / last page  (41G = page 41)'),
      (']] / [[', 'next chapter / start of chapter (then previous)'),
      ('gc', 'go to the start of this chapter'),
      (':', 'go to page'),
      ('` / \'', 'jump back to previous page (toggles)'),
      ('/', 'search   (Enter = jump, Esc = close)'),
      ('n / N', 'next / previous match'),
      ('o', 'contents'),
      ('i', 'show / hide the where-you-are panel'),
      ('t', 'reading goal & display options'),
      ('m', 'pin / unpin the app bar'),
      ('f', 'focus mode: only the progress strip'),
      ('a', 'annotate on / off'),
      ('u / Ctrl+r', 'undo / redo annotation'),
      ('+ / -', 'zoom'),
      ('Esc', 'clear, leave search / drawing / panel, then back to editor'),
      ('r', 'close the reader        (from either pane)'),
      ('Ctrl+w', 'switch focus: reader <-> editor'),
    ];
    showDialog<void>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Reader keys'),
            content: SingleChildScrollView(
              child: Table(
                defaultColumnWidth: const IntrinsicColumnWidth(),
                children: [
                  for (final r in rows)
                    TableRow(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 20, bottom: 6),
                          child: Text(
                            r.$1,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(r.$2),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
    );
  }

  // ===========================================================================
  // [UI-5 PREFS] / [UI-4 GOAL] options dialog launcher
  // ===========================================================================

  Future<void> _showOptions() async {
    final pos = _positionFor(_pageNotifier.value);
    await showDialog<void>(
      context: context,
      builder:
          (_) => _ReaderOptionsDialog(
            prefs: _prefs,
            goal: _goal,
            currentPage: pos.page,
            pageCount: pos.total,
            chapterLastPage: pos.chapter != null ? pos.chapterEnd - 1 : null,
            onPrefs: _setPrefs,
            onGoal: _setGoal,
            depth: _depthNotifier,
            maxDepth: _maxOutlineDepth,
            onDepth: _setChapterDepth,
          ),
    );
    if (mounted) _vimFocus.requestFocus();
  }

  // ---------------------------------------------------------------------------
  // Toolbar (the AppBar's actions)
  // ---------------------------------------------------------------------------

  List<Widget> _toolbar() {
    if (_searching) return _searchActions();

    return [
      ListenableBuilder(
        listenable: Listenable.merge([_store, _store.activePageListenable]),
        builder: (context, _) {
          final notifier = _store.activeNotifier;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!_store.drawing) ...[
                IconButton(
                  tooltip: 'Search',
                  icon: const Icon(Icons.search),
                  onPressed: _openSearch,
                ),
                IconButton(
                  tooltip: 'Go to page',
                  icon: const Icon(Icons.pin_outlined),
                  onPressed: _promptJumpToPage,
                ),
                PopupMenuButton<int>(
                  tooltip: 'Recent pages',
                  icon: const Icon(Icons.history),
                  onSelected: (p) {
                    _jumpToRecent(p);
                    _vimFocus.requestFocus();
                  },
                  onCanceled: _vimFocus.requestFocus,
                  itemBuilder:
                      (_) =>
                          _recent.isEmpty
                              ? const [
                                PopupMenuItem<int>(
                                  enabled: false,
                                  child: Text('No recent pages'),
                                ),
                              ]
                              : [
                                for (final p in _recent)
                                  PopupMenuItem<int>(
                                    value: p,
                                    child: Text(_recentLabel(p)),
                                  ),
                              ],
                ),
                if (_outline.isNotEmpty)
                  IconButton(
                    tooltip: 'Contents',
                    icon: const Icon(Icons.toc),
                    onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
                  ),
                // [UI-4 GOAL] / [UI-5 PREFS] entry point (key: t)
                IconButton(
                  tooltip: 'Reading goal & display',
                  icon: const Icon(Icons.flag_outlined),
                  onPressed: _showOptions,
                ),
              ],
              ListenableBuilder(
                listenable: notifier,
                builder:
                    (context, _) => IconButton(
                      tooltip: 'Undo',
                      icon: const Icon(Icons.undo),
                      onPressed: notifier.canUndo ? _store.undo : null,
                    ),
              ),
              ListenableBuilder(
                listenable: notifier,
                builder:
                    (context, _) => IconButton(
                      tooltip: 'Redo',
                      icon: const Icon(Icons.redo),
                      onPressed: notifier.canRedo ? _store.redo : null,
                    ),
              ),
              IconButton(
                tooltip: _store.drawing ? 'Done — stop drawing' : 'Annotate',
                icon: Icon(_store.drawing ? Icons.check : Icons.draw),
                onPressed: () {
                  // Defer so the params swap never races the pointer/wheel
                  // event that triggered the toggle.
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    _store.toggleDrawingMode();
                  });
                },
              ),
            ],
          );
        },
      ),
    ];
  }

  // ---------------------------------------------------------------------------
  // Banners
  // ---------------------------------------------------------------------------

  Widget _errorBanner(
    BuildContext context,
    Object error,
    StackTrace? stackTrace,
    PdfDocumentRef documentRef,
  ) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 40,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 12),
              const Text(
                'Failed to load this document. The knowledge-base daemon may '
                'be offline, or the file may no longer be available.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                '$error',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _loadingBanner(
    BuildContext context,
    int bytesDownloaded,
    int? totalBytes,
  ) {
    final progress =
        totalBytes == null || totalBytes <= 0
            ? null
            : (bytesDownloaded / totalBytes).clamp(0.0, 1.0);
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (progress == null)
                const CircularProgressIndicator()
              else
                CircularProgressIndicator(value: progress),
              const SizedBox(height: 12),
              const Text('Loading document…'),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Viewer
  // ---------------------------------------------------------------------------

  // One params builder shared by the online and offline viewers.
  PdfViewerParams _params() {
    return PdfViewerParams(
      // No pan/zoom lock: scribble's pointer-kind filter (store.pointerMode)
      // claims only stylus/mouse while drawing, so touch scrolls/zooms.
      // Wheel multiplier / arrow-key step (px). Raise for faster scrolling.
      scrollByMouseWheel: 1.5,
      scrollByArrowKey: 120,
      textSelectionParams: PdfTextSelectionParams(enabled: !_store.drawing),
      linkHandlerParams: PdfLinkHandlerParams(onLinkTap: _onLinkTap),
      onViewerReady: (document, controller) {
        _viewerReady = true;
        _pageCount = document.pages.length;
        _attachMatrixListener(); // [UI-3 BAR] scroll-direction auto-hide
        _loadOutline(document);
        // Safe to build the searcher now that the controller is attached.
        if (_searcher == null) {
          setState(() => _searcher = PdfTextSearcher(controller));
        }
      },
      onPageChanged: (pageNumber) {
        if (pageNumber != null) {
          _store.setActivePage(pageNumber);
          _rememberPage(pageNumber);
          _onPageForProgress(
            pageNumber,
          ); // [UI-1/2/4/6] feed the orientation UI
        }
      },
      // Search-hit highlighting.
      pagePaintCallbacks: [
        if (_searcher != null) _searcher!.pageTextMatchPaintCallback,
      ],
      viewerOverlayBuilder:
          (context, size, handleLinkTap) => [
            PdfViewerScrollThumb(
              controller: _controller,
              orientation: ScrollbarOrientation.right,
              thumbSize: const Size(40, 25),
              // The simple page number on the right edge; hovering it pops up
              // the chapter breadcrumb and "Page X of Y".
              thumbBuilder:
                  (context, thumbSize, pageNumber, controller) => Tooltip(
                    message: _positionTip(pageNumber ?? 1),
                    waitDuration: const Duration(milliseconds: 150),
                    preferBelow: false,
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.6),
                      alignment: Alignment.center,
                      child: Text(
                        pageNumber.toString(),
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
            ),
          ],
      errorBannerBuilder: _errorBanner,
      loadingBannerBuilder: _loadingBanner,
      // pageRect is the page's CURRENT zoom-scaled rect; the overlay forces its
      // canvas to exactly this size. The ValueKey stops Flutter reusing one
      // page's element for another page as the overlay list is rebuilt.
      pageOverlaysBuilder:
          (context, pageRect, page) => [
            // Outside drawing mode the ink layer must not take pointers, or it
            // sits on top of the link hit areas and links appear dead.
            ListenableBuilder(
              key: ValueKey(page.pageNumber),
              listenable: _store.drawingListenable,
              builder:
                  (context, _) => IgnorePointer(
                    ignoring: !_store.drawing,
                    child: ReaderInkPage(
                      store: _store,
                      page: page,
                      pageRect: pageRect,
                    ),
                  ),
            ),
          ],
    );
  }

  // pass lastViewedPage number to allow user to continue progress
  Widget _onlineReader(url, headers, lastViewedPage) {
    return PdfViewer.uri(
      Uri.parse(url),
      // Stable key — NEVER UniqueKey().
      key: const ValueKey('canonical_pdf_viewer'),
      headers: headers,
      controller: _controller,
      initialPageNumber: widget.page ?? lastViewedPage,
      params: _params(),
    );
  }

  Widget _offlineReader(path, headers, lastViewedPage) {
    return PdfViewer.file(
      path,
      key: const ValueKey('canonical_pdf_viewer'),
      controller: _controller,
      initialPageNumber: widget.page ?? lastViewedPage,
      params: _params(),
    );
  }

  // The viewer + the drawing dial (the original body of the Scaffold).
  Widget _readerBody(AsyncSnapshot<AuthenticatedPdfData> snapshot) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const Center(child: CircularProgressIndicator());
    }
    if (snapshot.hasError || !snapshot.hasData) {
      return Center(child: Text('Error preparing reader: ${snapshot.error}'));
    }
    final pdfData = snapshot.data!;
    return MouseRegion(
      // [UI-3 BAR] mouse at the very top edge reveals the app bar. Not opaque
      // and wrapping (not covering) the viewer, so it never eats pointer events.
      opaque: false,
      onHover: (event) => _onViewerHoverDy(event.localPosition.dy),
      child: Stack(
        children: [
          _onlineReader(pdfData.url, pdfData.headers, _lastPage),

          // The dial exists only IN drawing mode and is re-pointed at the
          // ACTIVE page's notifier. Positioned must stay the direct Stack
          // child. This builder wraps ONLY ToolDialHub.
          Positioned.fill(
            child: ListenableBuilder(
              listenable: Listenable.merge([
                _store,
                _store.activePageListenable,
              ]),
              builder:
                  (context, _) =>
                      _store.drawing
                          ? ToolDialHub(
                            notifier: _store.activeNotifier,
                            onSelectTool: _store.applyDrawingTool,
                            partialEraser: _store.partialEraser,
                            eraserWidth: _store.eraserWidth,
                          )
                          : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // [UI-1 STRIP] thin always-visible progress strip: book track + chapter
  // track + chapter ticks + goal flag. Tap or drag to jump.
  // Stays visible when the app bar is hidden and in focus mode.
  // ===========================================================================
  Widget _progressStrip() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: _stripBottomInset,
      child: ListenableBuilder(
        listenable: Listenable.merge([
          _pageNotifier,
          _goal,
          _prefs,
          _depthNotifier,
        ]),
        builder: (context, _) {
          final pos = _positionFor(_pageNotifier.value);
          final goal = _goal.value;
          return _ProgressStrip(
            pos: pos,
            ticks: _chapterTicks(),
            sectionTicks: _sectionTicks(pos),
            goalPage: goal?.target,
            highContrast: _prefs.value.highContrast,
            nearEnd:
                pos.chapter != null && pos.chapterProgress >= _nearEndFraction,
            // Not draggable while drawing: don't steal pen strokes at the edge.
            interactive: !_store.drawing,
            hitHeight: _stripHitHeight,
            onJump: (page, record) => _goToPage(page, record: record),
          );
        },
      ),
    );
  }

  // ===========================================================================
  // [UI-2 CHIP] "where you are" panel. HIDDEN by default: it only appears when
  // you press `i` (or open it from the flag menu) and goes away on `i` again,
  // Esc, or its collapse button. The progress strip stays visible regardless.
  // Also hidden in drawing mode and focus mode.
  // ===========================================================================
  Widget _infoChip() {
    return Positioned.fill(
      child: ListenableBuilder(
        listenable: Listenable.merge([
          _pageNotifier,
          _goal,
          _prefs,
          _chipExpanded,
          _depthNotifier,
        ]),
        builder: (context, _) {
          final prefs = _prefs.value;
          if (_store.drawing || prefs.focusMode || !_chipExpanded.value) {
            return const SizedBox.shrink();
          }
          final pos = _positionFor(_pageNotifier.value);
          return LayoutBuilder(
            builder: (context, c) {
              final maxW = math.max(
                160.0,
                math.min(c.maxWidth - _chipLeft * 2, _panelMaxWidth),
              );
              final maxH = math.max(140.0, c.maxHeight - _chipBottom - 24);
              return Padding(
                padding: const EdgeInsets.only(
                  left: _chipLeft,
                  right: _chipLeft,
                  bottom: _chipBottom,
                ),
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: _InfoChip(
                    pos: pos,
                    prefs: prefs,
                    goal: _goal.value,
                    secPerPage: _secPerPage,
                    expanded: _chipExpanded.value,
                    maxWidth: maxW,
                    maxHeight: maxH,
                    onToggle: () => _chipExpanded.value = !_chipExpanded.value,
                    onOptions: _showOptions,
                    onChapterStart: _chapterStart,
                    onNextChapter: _nextChapter,
                    onJump: (p) => _goToPage(p),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  // ===========================================================================
  // [UI-6 TOAST] short "chapter finished" / "goal reached" pill
  // ===========================================================================
  Widget _toastLayer() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: _chipBottom + 52,
      child: IgnorePointer(
        child: ValueListenableBuilder<String?>(
          valueListenable: _toast,
          builder:
              (context, msg, _) => AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child:
                    msg == null
                        ? const SizedBox.shrink(key: ValueKey('no-toast'))
                        : Center(
                          key: ValueKey(msg),
                          child: _ToastPill(text: msg),
                        ),
              ),
        ),
      ),
    );
  }

  // ===========================================================================
  // [UI-3 BAR] the auto-hiding app bar. An OVERLAY in the Stack, deliberately
  // NOT Scaffold.appBar: that would resize the viewer every time it toggles.
  //
  // Shown when ANY of: still loading, drawing, searching, pinned (m / options),
  // or (not in focus mode) the scroll/hover logic wants it.
  // ===========================================================================
  Widget _autoHideAppBar(String title, {required bool forceShow}) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: kToolbarHeight,
      child: ListenableBuilder(
        listenable: Listenable.merge([_barAuto, _prefs]),
        builder: (context, _) {
          final p = _prefs.value;
          final show =
              forceShow ||
              _store.drawing ||
              _searching ||
              p.barPinned ||
              (!p.focusMode && _barAuto.value);
          return IgnorePointer(
            ignoring: !show,
            child: AnimatedSlide(
              offset: show ? Offset.zero : const Offset(0, -1),
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              child: AnimatedOpacity(
                opacity: show ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: AppBar(
                  // The Reader may live inside a floating window, and the
                  // enclosing SafeArea already handles the status bar.
                  primary: false,
                  title:
                      _searching
                          ? _searchTitle()
                          : Text(title, overflow: TextOverflow.ellipsis),
                  actions: _toolbar(),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _vimFocus,
      // Standalone page: take focus so keys work immediately. Hosted in the
      // floating window the host moves focus explicitly (r / Ctrl+w / click).
      autofocus: widget.focusNode == null,
      onKeyEvent: _onVimKey,
      child: FutureBuilder<AuthenticatedPdfData>(
        future: _pdfDataFuture,
        builder: (context, snapshot) {
          final pdfData = snapshot.data;
          final title = pdfData?.filename ?? 'PDF';
          final ready =
              snapshot.connectionState != ConnectionState.waiting &&
              !snapshot.hasError &&
              snapshot.hasData;

          return Scaffold(
            key: _scaffoldKey,
            // endDrawer, not drawer: a start drawer would replace the back button.
            endDrawer: _outline.isEmpty ? null : _outlineDrawer(),
            // NOTE: no Scaffold.appBar — see [UI-3 BAR].
            body: SafeArea(
              child: Stack(
                children: [
                  Positioned.fill(child: _readerBody(snapshot)),

                  // Orientation layers, bottom to top. Each is a direct
                  // Positioned child of this Stack.
                  if (ready && _pageCount > 0) ...[
                    _progressStrip(), // [UI-1 STRIP]
                    _infoChip(), //      [UI-2 CHIP]
                    _toastLayer(), //    [UI-6 TOAST]
                  ],
                  _autoHideAppBar(title, forceShow: !ready), // [UI-3 BAR]
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// =============================================================================
// [UI-1 STRIP] widget + painter
// =============================================================================

// Width reserved at the left of both bars for their "CH" / "BOOK" tags.
const double _kStripGutter = 26.0;
// y (inside the strip's drawn area) that separates the chapter row from the
// book row for taps/drags.
const double _kStripRowSplit = 23.0;

/// The progress dock's two bars:
///   TOP    "CH"   = this chapter. Section boundaries are ticks on it. Fill =
///                   how far through the chapter you are; the rest is what's
///                   left. Tap/drag seeks WITHIN the chapter.
///   BOTTOM "BOOK" = the whole book. Chapter boundaries are ticks on it.
///                   Tap/drag seeks anywhere in the book.
/// Above the bars: one small line with Chapter › Section, pages left, page x/y.
class _ProgressStrip extends StatefulWidget {
  final _Position pos;
  final List<double> ticks; // chapter boundaries, 0..1 of the book
  final List<double> sectionTicks; // section boundaries, 0..1 of the chapter
  final int? goalPage;
  final bool highContrast;
  final bool nearEnd;
  final bool interactive;
  final double hitHeight;

  /// (page, record): record = whether to add the page you left to jump history
  /// (true on tap, false while dragging).
  final void Function(int page, bool record) onJump;

  const _ProgressStrip({
    required this.pos,
    required this.ticks,
    required this.sectionTicks,
    required this.goalPage,
    required this.highContrast,
    required this.nearEnd,
    required this.interactive,
    required this.hitHeight,
    required this.onJump,
  });

  @override
  State<_ProgressStrip> createState() => _ProgressStripState();
}

class _ProgressStripState extends State<_ProgressStrip> {
  // Which bar a drag started on (locked for the whole drag).
  bool _dragOnChapter = false;

  void _jump(double dx, double width, bool chapterRow, {required bool record}) {
    final pos = widget.pos;
    final bw = width - _kStripGutter;
    if (pos.total < 1 || bw <= 0) return;
    final f = ((dx - _kStripGutter) / bw).clamp(0.0, 1.0).toDouble();
    int page;
    if (chapterRow && pos.chapter != null) {
      final span = math.max(1, pos.chapterEnd - pos.chapterStart);
      page =
          (pos.chapterStart + (f * span).floor())
              .clamp(
                pos.chapterStart,
                math.max(pos.chapterStart, pos.chapterEnd - 1),
              )
              .toInt();
    } else {
      page = (f * pos.total).ceil().clamp(1, pos.total).toInt();
    }
    widget.onJump(page, record);
  }

  @override
  Widget build(BuildContext context) {
    final pos = widget.pos;
    final scheme = Theme.of(context).colorScheme;
    final hc = widget.highContrast;
    final pct = (pos.chapterProgress * 100).round();
    final fg = scheme.onSurface;
    final bg = scheme.surface.withValues(alpha: hc ? 1.0 : 0.94);

    // Goal on both scales: a flag on the chapter bar if the goal page is in
    // this chapter, and a mark on the book bar.
    final gp = widget.goalPage;
    final goalBook =
        gp == null
            ? null
            : (gp / math.max(1, pos.total)).clamp(0.0, 1.0).toDouble();
    double? goalChapter;
    if (gp != null &&
        pos.chapter != null &&
        gp >= pos.chapterStart &&
        gp < pos.chapterEnd) {
      goalChapter =
          ((gp - pos.chapterStart + 1) /
                  math.max(1, pos.chapterEnd - pos.chapterStart))
              .clamp(0.0, 1.0)
              .toDouble();
    }

    // [SECTION] where the current section sits on the CH bar (fractions of the
    // chapter) and how many pages of it are left. Null = chapter has no sections.
    double? secA, secB;
    int? secLeft;
    if (pos.chapter != null && pos.hasSections) {
      final span = math.max(1, pos.chapterEnd - pos.chapterStart);
      secA = (pos.sectionStart - pos.chapterStart) / span;
      secB = (pos.sectionEnd - pos.chapterStart) / span;
      secLeft = pos.pagesLeftInSection;
    }

    final strip = LayoutBuilder(
      builder: (context, c) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown:
              (d) => _jump(
                d.localPosition.dx,
                c.maxWidth,
                d.localPosition.dy < _kStripRowSplit,
                record: true,
              ),
          onHorizontalDragStart:
              (d) => _dragOnChapter = d.localPosition.dy < _kStripRowSplit,
          onHorizontalDragUpdate:
              (d) => _jump(
                d.localPosition.dx,
                c.maxWidth,
                _dragOnChapter,
                record: false,
              ),
          child: CustomPaint(
            size: Size(c.maxWidth, widget.hitHeight),
            painter: _ProgressStripPainter(
              book: pos.bookProgress,
              chapter: pos.chapterProgress,
              ticks: widget.ticks,
              sectionTicks: widget.sectionTicks,
              goalBook: goalBook,
              goalChapter: goalChapter,
              sectionA: secA,
              sectionB: secB,
              sectionLeft: secLeft,
              nearEnd: widget.nearEnd,
              track: fg.withValues(alpha: hc ? 0.45 : 0.18),
              bookColor: hc ? fg : scheme.primary.withValues(alpha: 0.65),
              chapterColor: hc ? fg : scheme.primary,
              nearEndColor: hc ? fg : scheme.tertiary,
              tick: fg.withValues(alpha: hc ? 0.95 : 0.6),
              goalColor: hc ? fg : scheme.secondary,
              surface: scheme.surface,
              tagColor: fg.withValues(alpha: hc ? 0.95 : 0.6),
            ),
          ),
        );
      },
    );

    // One small line: Chapter › Section on the left, pages left + page on the
    // right. Small type so a deep breadcrumb still fits; it ellipsizes.
    final chapterTitle = pos.chapter?.title ?? pos.section?.title;
    final sectionTitle =
        (pos.section != null && !identical(pos.section, pos.chapter))
            ? pos.section!.title
            : null;
    final small = TextStyle(color: fg, fontSize: 10, height: 1.2);
    final label = ExcludeSemantics(
      child: Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: chapterTitle ?? 'Document',
                    style: small.copyWith(fontWeight: FontWeight.w700),
                  ),
                  if (sectionTitle != null) ...[
                    TextSpan(
                      text: '  ›  ',
                      style: small.copyWith(color: fg.withValues(alpha: 0.55)),
                    ),
                    TextSpan(
                      text: sectionTitle,
                      style: small.copyWith(fontWeight: FontWeight.w500),
                    ),
                  ],
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${pos.pagesLeftLabel}  ·  p.${pos.page}/${pos.total}',
            maxLines: 1,
            style: small.copyWith(
              color: fg.withValues(alpha: 0.75),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );

    return Stack(
      children: [
        // Screen readers: one node for the numbers, updated per page...
        Semantics(
          container: true,
          label: 'Reading progress',
          value:
              '${pos.chapterTitle}, $pct percent, ${pos.pagesLeftLabel}. '
              'Page ${pos.page} of ${pos.total}.',
          child: Container(
            decoration: BoxDecoration(
              color: bg,
              border: Border(
                top: BorderSide(color: fg.withValues(alpha: hc ? 0.6 : 0.12)),
              ),
            ),
            // 26 / 10 clears the floating window's resize grips.
            padding: const EdgeInsets.fromLTRB(26, 5, 26, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                label,
                const SizedBox(height: 1),
                SizedBox(
                  height: widget.hitHeight,
                  child: IgnorePointer(
                    ignoring: !widget.interactive,
                    child: strip,
                  ),
                ),
              ],
            ),
          ),
        ),
        // ...and a tiny live-region node whose label only changes when the
        // SECTION changes, so it announces "Classification" once, not per page.
        Semantics(
          liveRegion: true,
          label: pos.section?.title ?? '',
          child: const SizedBox(width: 1, height: 1),
        ),
      ],
    );
  }
}

class _ProgressStripPainter extends CustomPainter {
  final double book;
  final double chapter;
  final List<double> ticks;
  final List<double> sectionTicks;
  final double? goalBook;
  final double? goalChapter;
  final double? sectionA; // current section start, 0..1 of the chapter
  final double? sectionB; // current section end, 0..1 of the chapter
  final int? sectionLeft; // pages left in the current section
  final bool nearEnd;
  final Color track;
  final Color bookColor;
  final Color chapterColor;
  final Color nearEndColor;
  final Color tick;
  final Color goalColor;
  final Color surface;
  final Color tagColor;

  const _ProgressStripPainter({
    required this.book,
    required this.chapter,
    required this.ticks,
    required this.sectionTicks,
    required this.goalBook,
    required this.goalChapter,
    required this.sectionA,
    required this.sectionB,
    required this.sectionLeft,
    required this.nearEnd,
    required this.track,
    required this.bookColor,
    required this.chapterColor,
    required this.nearEndColor,
    required this.tick,
    required this.goalColor,
    required this.surface,
    required this.tagColor,
  });

  void _tag(Canvas canvas, String text, double cy) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: tagColor,
          fontSize: 7,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(0, cy - tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final p = Paint()..isAntiAlias = true;

    // Geometry (32px tall): [pages-left number + goal flag 0-11]
    // [chapter bar 15-21] [book bar 25-29]
    const chTop = 15.0, chH = 6.0;
    const bkTop = 25.0, bkH = 4.0;
    final x0 = _kStripGutter;
    final bw = math.max(1.0, w - x0);
    double x(double f) => x0 + bw * f;

    final chTrack = RRect.fromRectAndRadius(
      Rect.fromLTWH(x0, chTop, bw, chH),
      const Radius.circular(chH / 2),
    );
    final bkTrack = RRect.fromRectAndRadius(
      Rect.fromLTWH(x0, bkTop, bw, bkH),
      const Radius.circular(bkH / 2),
    );

    // Tags so the hierarchy is obvious: top bar = chapter, bottom = book.
    _tag(canvas, 'CH', chTop + chH / 2);
    _tag(canvas, 'BOOK', bkTop + bkH / 2);

    // Tracks.
    p.color = track;
    canvas.drawRRect(chTrack, p);
    canvas.drawRRect(bkTrack, p);

    // [SECTION] tint the current section's stretch of the CH bar; the tint's
    // right edge is where this section ends.
    final segColor = nearEnd ? nearEndColor : chapterColor;
    final sa = sectionA, sb = sectionB;
    if (sa != null && sb != null && sb > sa) {
      canvas.save();
      canvas.clipRRect(chTrack);
      p.color = segColor.withValues(alpha: 0.32);
      canvas.drawRect(Rect.fromLTRB(x(sa), chTop, x(sb), chTop + chH), p);
      canvas.restore();
    }

    // Fills (clipped so the left end stays rounded).
    canvas.save();
    canvas.clipRRect(chTrack);
    p.color = nearEnd ? nearEndColor : chapterColor;
    canvas.drawRect(Rect.fromLTWH(x0, chTop, bw * chapter, chH), p);
    canvas.restore();

    canvas.save();
    canvas.clipRRect(bkTrack);
    p.color = bookColor;
    canvas.drawRect(Rect.fromLTWH(x0, bkTop, bw * book, bkH), p);
    canvas.restore();

    // Section boundaries on the CHAPTER bar.
    p.color = tick;
    for (final t in sectionTicks) {
      final tx = (x(t) - 0.75).clamp(x0, x0 + bw - 1.5).toDouble();
      canvas.drawRect(Rect.fromLTWH(tx, chTop - 1.5, 1.5, chH + 3), p);
    }
    // Chapter boundaries on the BOOK bar.
    for (final t in ticks) {
      final tx = (x(t) - 0.75).clamp(x0, x0 + bw - 1.5).toDouble();
      canvas.drawRect(Rect.fromLTWH(tx, bkTop - 1.5, 1.5, bkH + 3), p);
    }

    // "You are here" knobs.
    final accent = nearEnd ? nearEndColor : chapterColor;
    final kx =
        x(chapter).clamp(x0 + 5, math.max(x0 + 5, x0 + bw - 5)).toDouble();
    p.color = surface;
    canvas.drawCircle(Offset(kx, chTop + chH / 2), 6.5, p);
    p.color = accent;
    canvas.drawCircle(Offset(kx, chTop + chH / 2), 4.5, p);

    // [SECTION] pages left in this section, centred above the knob.
    final left = sectionLeft;
    if (left != null) {
      final tp = TextPainter(
        text: TextSpan(
          text: '$left',
          style: TextStyle(
            color: segColor,
            fontSize: 9,
            fontWeight: FontWeight.w800,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final tx =
          (kx - tp.width / 2).clamp(x0, math.max(x0, w - tp.width)).toDouble();
      tp.paint(canvas, Offset(tx, 1.5));
    }

    final bx = x(book).clamp(x0 + 3, math.max(x0 + 3, x0 + bw - 3)).toDouble();
    p.color = surface;
    canvas.drawCircle(Offset(bx, bkTop + bkH / 2), 4.5, p);
    p.color = bookColor;
    canvas.drawCircle(Offset(bx, bkTop + bkH / 2), 3, p);

    // Goal: mark on the book bar; flag on the chapter bar when it's in range.
    final gb = goalBook;
    if (gb != null) {
      p.color = goalColor;
      final gx = (x(gb) - 1).clamp(x0, x0 + bw - 2).toDouble();
      canvas.drawRect(Rect.fromLTWH(gx, bkTop - 2.5, 2, bkH + 5), p);
    }
    final gc = goalChapter;
    if (gc != null) {
      final gx = x(gc).clamp(x0, x0 + bw).toDouble();
      p.color = goalColor;
      final flipLeft = gx > x0 + bw - 12;
      canvas.drawRect(
        Rect.fromLTWH(flipLeft ? gx - 1.5 : gx, 0, 1.5, chTop + chH),
        p,
      );
      final dir = flipLeft ? -1.0 : 1.0;
      final fx = flipLeft ? gx - 1.5 : gx + 1.5;
      final path =
          Path()
            ..moveTo(fx, 0)
            ..lineTo(fx + dir * 9, 3.5)
            ..lineTo(fx, 7)
            ..close();
      canvas.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(_ProgressStripPainter old) =>
      old.book != book ||
      old.chapter != chapter ||
      old.goalBook != goalBook ||
      old.goalChapter != goalChapter ||
      old.sectionA != sectionA ||
      old.sectionB != sectionB ||
      old.sectionLeft != sectionLeft ||
      old.nearEnd != nearEnd ||
      old.ticks.length != ticks.length ||
      old.sectionTicks.length != sectionTicks.length ||
      old.track != track ||
      old.bookColor != bookColor ||
      old.chapterColor != chapterColor ||
      old.surface != surface ||
      old.tagColor != tagColor;
}

// =============================================================================
// [UI-2 CHIP] widget: collapsed pill + expanded panel
// =============================================================================

class _InfoChip extends StatelessWidget {
  final _Position pos;
  final _ReaderPrefs prefs;
  final _Goal? goal;
  final double? secPerPage;
  final bool expanded;
  final double maxWidth;
  final double maxHeight;
  final VoidCallback onToggle;
  final VoidCallback onOptions;
  final VoidCallback onChapterStart;
  final VoidCallback onNextChapter;
  final ValueChanged<int> onJump;

  const _InfoChip({
    required this.pos,
    required this.prefs,
    required this.goal,
    required this.secPerPage,
    required this.expanded,
    required this.maxWidth,
    required this.maxHeight,
    required this.onToggle,
    required this.onOptions,
    required this.onChapterStart,
    required this.onNextChapter,
    required this.onJump,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mq = MediaQuery.of(context);
    // Respect the system text scale, then multiply by the in-app size option.
    final sys = mq.textScaler.scale(14) / 14;
    final hc = prefs.highContrast;
    final bg =
        hc
            ? scheme.onSurface
            : scheme.surfaceContainerHighest.withValues(alpha: 0.95);
    final fg = hc ? scheme.surface : scheme.onSurface;
    final accent = hc ? scheme.surface : scheme.primary;

    return MediaQuery(
      data: mq.copyWith(textScaler: TextScaler.linear(sys * prefs.textScale)),
      child: expanded ? _panel(bg, fg, accent) : _pill(bg, fg, accent),
    );
  }

  // --- collapsed: "Classification · 14 left · p.83/540  ▮▮▮▯▯" -------------
  Widget _pill(Color bg, Color fg, Color accent) {
    final showText = prefs.chipMode != _ChipMode.bar;
    final showBar = prefs.chipMode != _ChipMode.numbers;
    final summary =
        '${pos.chapterTitle} · ${pos.pagesLeftLabel} · '
        'p.${pos.page}/${pos.total}';
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Material(
        color: bg,
        elevation: 4,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onToggle,
          onLongPress: onOptions,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showText)
                  Flexible(
                    child: Text(
                      summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: fg,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                if (showText && showBar) const SizedBox(width: 8),
                if (showBar)
                  SizedBox(
                    width: 48,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: pos.chapterProgress,
                        minHeight: 5,
                        color: accent,
                        backgroundColor: fg.withValues(alpha: 0.25),
                      ),
                    ),
                  ),
                const SizedBox(width: 4),
                Icon(Icons.expand_less, size: 16, color: fg),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- expanded panel ---------------------------------------------------------
  Widget _panel(Color bg, Color fg, Color accent) {
    final pct = (pos.chapterProgress * 100).round();
    final next = pos.nextSection;
    final nextCh = pos.nextChapter;
    final g = goal;
    final spp = secPerPage;

    String? chapterTime;
    if (prefs.showTime) {
      chapterTime =
          spp == null
              ? 'Time estimate appears after a few pages'
              : (pos.hasSections
                      ? '${_fmtDuration(spp * pos.pagesLeftInSection)} left in this section · '
                      : '') +
                  '${_fmtDuration(spp * pos.pagesLeftInChapter)} left in this chapter';
    }

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
      child: Material(
        color: bg,
        elevation: 8,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header: breadcrumb + collapse.
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 6, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      pos.trail.isEmpty
                          ? 'Page ${pos.page} of ${pos.total}'
                          : pos.trail.join(' › '),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: fg,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Collapse',
                    icon: Icon(Icons.expand_more, color: fg),
                    onPressed: onToggle,
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _bar(
                      'This chapter',
                      pos.chapterProgress,
                      '$pct% · ${pos.pagesLeftLabel}',
                      fg,
                      accent,
                    ),
                    // [SECTION] pages left in the current section
                    if (pos.hasSections)
                      _bar(
                        'This section',
                        pos.sectionProgress,
                        pos.pagesLeftInSection == 0
                            ? 'last page'
                            : '${pos.pagesLeftInSection} left',
                        fg,
                        accent,
                      ),
                    _bar(
                      'Whole book',
                      pos.bookProgress,
                      'p.${pos.page} of ${pos.total}',
                      fg,
                      accent,
                    ),
                    if (chapterTime != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          chapterTime,
                          style: TextStyle(
                            color: fg.withValues(alpha: 0.8),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    // [UI-4 GOAL]
                    if (g != null) ...[
                      _bar(
                        'Goal: page ${g.target}',
                        g.progressAt(pos.page),
                        g.leftAt(pos.page) == 0
                            ? 'reached'
                            : '${g.leftAt(pos.page)} to go',
                        fg,
                        accent,
                      ),
                      if (prefs.showTime &&
                          spp != null &&
                          g.leftAt(pos.page) > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '${_fmtDuration(spp * g.leftAt(pos.page))} to reach your goal',
                            style: TextStyle(
                              color: fg.withValues(alpha: 0.8),
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ] else
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: TextButton.icon(
                          style: TextButton.styleFrom(foregroundColor: fg),
                          onPressed: onOptions,
                          icon: const Icon(Icons.flag_outlined, size: 16),
                          label: const Text('Set a reading goal'),
                        ),
                      ),
                    const SizedBox(height: 8),
                    if (next != null && !identical(next, nextCh))
                      _navTile('Next section', next, fg),
                    if (nextCh != null) _navTile('Next chapter', nextCh, fg),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        if (pos.chapter != null)
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: fg,
                              side: BorderSide(
                                color: fg.withValues(alpha: 0.5),
                              ),
                            ),
                            onPressed: onChapterStart,
                            icon: const Icon(Icons.first_page, size: 16),
                            label: const Text('Chapter start'),
                          ),
                        if (nextCh != null)
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: fg,
                              side: BorderSide(
                                color: fg.withValues(alpha: 0.5),
                              ),
                            ),
                            onPressed: onNextChapter,
                            icon: const Icon(Icons.last_page, size: 16),
                            label: const Text('Next chapter'),
                          ),
                        TextButton.icon(
                          style: TextButton.styleFrom(foregroundColor: fg),
                          onPressed: onOptions,
                          icon: const Icon(Icons.tune, size: 16),
                          label: const Text('Goal & display'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bar(
    String label,
    double value,
    String trailing,
    Color fg,
    Color accent,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: fg,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(trailing, style: TextStyle(color: fg, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: value,
              minHeight: 6,
              color: accent,
              backgroundColor: fg.withValues(alpha: 0.2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _navTile(String label, _OutlineEntry e, Color fg) {
    return InkWell(
      onTap: () => onJump(e.page),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(Icons.arrow_forward, size: 16, color: fg),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: fg.withValues(alpha: 0.7),
                      fontSize: 11,
                    ),
                  ),
                  Text(
                    e.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: fg,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'p.${e.page} · in ${e.page - pos.page}',
              style: TextStyle(color: fg.withValues(alpha: 0.8), fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// [UI-6 TOAST] widget
// =============================================================================

class _ToastPill extends StatelessWidget {
  final String text;
  const _ToastPill({required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.inverseSurface,
      elevation: 6,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, size: 16, color: scheme.onInverseSurface),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: scheme.onInverseSurface,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// [UI-4 GOAL] + [UI-5 PREFS] options dialog. Owns its TextEditingController
// (see the go-to-page crash note in the header).
// =============================================================================

class _ReaderOptionsDialog extends StatefulWidget {
  final ValueNotifier<_ReaderPrefs> prefs;
  final ValueNotifier<_Goal?> goal;
  final int currentPage;
  final int pageCount;
  final int? chapterLastPage;
  final ValueChanged<_ReaderPrefs> onPrefs;
  final ValueChanged<int?> onGoal;
  final ValueNotifier<int> depth; // 0 = auto
  final int maxDepth;
  final ValueChanged<int> onDepth;

  const _ReaderOptionsDialog({
    required this.prefs,
    required this.goal,
    required this.currentPage,
    required this.pageCount,
    required this.chapterLastPage,
    required this.onPrefs,
    required this.onGoal,
    required this.depth,
    required this.maxDepth,
    required this.onDepth,
  });

  @override
  State<_ReaderOptionsDialog> createState() => _ReaderOptionsDialogState();
}

class _ReaderOptionsDialogState extends State<_ReaderOptionsDialog> {
  final _pageField = TextEditingController();

  @override
  void dispose() {
    _pageField.dispose();
    super.dispose();
  }

  void _submitPage() {
    final n = int.tryParse(_pageField.text.trim());
    if (n != null && n >= 1 && n <= widget.pageCount) {
      widget.onGoal(n);
      _pageField.clear();
    }
  }

  int _plus(int n) =>
      (widget.currentPage + n).clamp(1, widget.pageCount).toInt();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chapterLast = widget.chapterLastPage;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: ListenableBuilder(
              listenable: Listenable.merge([
                widget.prefs,
                widget.goal,
                widget.depth,
              ]),
              builder: (context, _) {
                final p = widget.prefs.value;
                final g = widget.goal.value;
                void set(_ReaderPrefs n) => widget.onPrefs(n);

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ----- goal ------------------------------------------------
                    Text('Reading goal', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      g == null
                          ? 'No goal set. Pick where you want to get to today.'
                          : 'Stop at page ${g.target} (set at page ${g.start}).',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        if (chapterLast != null &&
                            chapterLast > widget.currentPage)
                          ActionChip(
                            label: Text('End of chapter (p.$chapterLast)'),
                            onPressed: () => widget.onGoal(chapterLast),
                          ),
                        ActionChip(
                          label: Text('+10 pages (p.${_plus(10)})'),
                          onPressed: () => widget.onGoal(_plus(10)),
                        ),
                        ActionChip(
                          label: Text('+25 pages (p.${_plus(25)})'),
                          onPressed: () => widget.onGoal(_plus(25)),
                        ),
                        if (g != null)
                          ActionChip(
                            label: const Text('Clear goal'),
                            onPressed: () => widget.onGoal(null),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _pageField,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              isDense: true,
                              hintText:
                                  'Stop at page (max ${widget.pageCount})',
                            ),
                            onSubmitted: (_) => _submitPage(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: _submitPage,
                          child: const Text('Set'),
                        ),
                      ],
                    ),

                    const Divider(height: 28),

                    // ----- what counts as a chapter ----------------------------
                    Text('Chapter level', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      'Which level of the contents the CH bar follows. If it '
                      'shows a whole Part, pick a deeper level.',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final d in [
                          0,
                          for (var i = 1; i <= widget.maxDepth; i++) i,
                        ])
                          ChoiceChip(
                            label: Text(d == 0 ? 'Auto' : 'Level $d'),
                            selected: widget.depth.value == d,
                            onSelected: (_) => widget.onDepth(d),
                          ),
                      ],
                    ),

                    const Divider(height: 28),

                    // ----- display / accessibility -----------------------------
                    Text(
                      'Progress readout',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final (mode, label) in const [
                          (_ChipMode.numbers, 'Numbers'),
                          (_ChipMode.bar, 'Bar'),
                          (_ChipMode.both, 'Both'),
                        ])
                          ChoiceChip(
                            label: Text(label),
                            selected: p.chipMode == mode,
                            onSelected: (_) => set(p.copyWith(chipMode: mode)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text('Text size', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final (scale, label) in const [
                          (1.0, 'Normal'),
                          (1.25, 'Large'),
                          (1.5, 'Largest'),
                        ])
                          ChoiceChip(
                            label: Text(label),
                            selected: p.textScale == scale,
                            onSelected:
                                (_) => set(p.copyWith(textScale: scale)),
                          ),
                      ],
                    ),
                    SwitchListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('High contrast'),
                      subtitle: const Text('Stronger strip and panel colours'),
                      value: p.highContrast,
                      onChanged: (v) => set(p.copyWith(highContrast: v)),
                    ),
                    SwitchListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Show time estimates'),
                      subtitle: const Text('Based on your own reading pace'),
                      value: p.showTime,
                      onChanged: (v) => set(p.copyWith(showTime: v)),
                    ),
                    SwitchListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Keep app bar visible'),
                      subtitle: const Text('Turns off auto-hide (key: m)'),
                      value: p.barPinned,
                      onChanged: (v) => set(p.copyWith(barPinned: v)),
                    ),
                    SwitchListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Focus mode'),
                      subtitle: const Text(
                        'Hide everything except the progress strip (key: f)',
                      ),
                      value: p.focusMode,
                      onChanged: (v) => set(p.copyWith(focusMode: v)),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Close'),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// "Go to page" dialog. Owns its TextEditingController so it is disposed only
/// when the dialog is actually unmounted (after the exit animation), not when
/// showDialog's future completes.
class _GoToPageDialog extends StatefulWidget {
  final int pageCount;
  const _GoToPageDialog({required this.pageCount});

  @override
  State<_GoToPageDialog> createState() => _GoToPageDialogState();
}

class _GoToPageDialogState extends State<_GoToPageDialog> {
  final _field = TextEditingController();

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(int.tryParse(_field.text.trim()));

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Go to page'),
      content: TextField(
        controller: _field,
        autofocus: true,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(hintText: '1 – ${widget.pageCount}'),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _submit, child: const Text('Go')),
      ],
    );
  }
}
