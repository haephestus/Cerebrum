/// =============================================================================
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
// │   [UI-7 KEYS]    new vim keys: i  [[ ]]  gc  m  f  t  b  B              │
// │   [POSITION]     _positionFor(): the one function all of the above read │
// │   [ZOOM]         _zoomBy(): fine, centre-anchored zoom (Ctrl +/- and +/-)│
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
//  - ZOOM STEP: pdfrx's zoomUp()/zoomDown() jump between fixed stops, which
//    overshoots when you're trying to centre the page. Ctrl +/- and +/- now go
//    through _zoomBy(), a small multiplicative step (see [ZOOM]) anchored on
//    the centre of the reader so the page stays centred as you zoom.
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
//  - BOOKMARKS: b opens a vim-navigable list of saved pages; Shift+B toggles
//    the current page. Client-side only (no backend sync), persisted per file
//    in SharedPreferences as page numbers. Labels are derived from the outline
//    when the list is opened, so they track chapter-depth changes.
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
import 'package:cerebrum/services/reading_progress.dart';
import 'package:cerebrum/features/editor/widgets/radial_tool_dial.dart';
import 'package:cerebrum/features/reader/annotations.dart';
import 'package:cerebrum/features/reader/reader_ink_layer.dart';

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

// One selectable row in the contents drawer: a node header/leaf.
typedef _OutlineRow = ({PdfOutlineNode node, List<int> path, int depth});

// Mutable builder for assembling the sidecar TOC tree before freezing it
// into immutable PdfOutlineNodes (value-equality prevents using those as
// tree keys directly).
class _SidecarBuilder {
  final String title;
  final int page;
  final List<_SidecarBuilder> children = [];
  _SidecarBuilder(this.title, this.page);
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
  /// Black tint over the page in dark mode, 0.0 (off) … 0.6 (strong).
  /// Only applies when the app brightness is dark.
  final double dimStrength;

  const _ReaderPrefs({
    this.chipMode = _ChipMode.both,
    this.highContrast = false,
    this.textScale = 1.0,
    this.focusMode = false,
    this.barPinned = false,
    this.showTime = true,
    this.dimStrength = 0.0,
  });

  _ReaderPrefs copyWith({
    _ChipMode? chipMode,
    bool? highContrast,
    double? textScale,
    bool? focusMode,
    bool? barPinned,
    bool? showTime,
    double? dimStrength,
  }) => _ReaderPrefs(
    chipMode: chipMode ?? this.chipMode,
    highContrast: highContrast ?? this.highContrast,
    textScale: textScale ?? this.textScale,
    focusMode: focusMode ?? this.focusMode,
    barPinned: barPinned ?? this.barPinned,
    showTime: showTime ?? this.showTime,
    dimStrength: dimStrength ?? this.dimStrength,
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

  /// Embedded/back-override: when set (e.g. floating reader in editor), the
  /// AppBar back control calls this instead of implying route pop.
  final VoidCallback? onBack;

  const Reader({
    super.key,
    required this.fileFingerprint,
    this.page,
    this.focusNode,
    this.onReleaseFocus,
    this.onBack,
  });

  @override
  State<Reader> createState() => _ReaderState();
}

class _ReaderState extends State<Reader> {
  // ===========================================================================
  // [TWEAK] Every number you're likely to want to change lives here.
  // ===========================================================================

  // [ZOOM] multiplier per press (1.05 = 5%). Lower = finer steps.
  static const _zoomStep = 1.05;
  static const _zoomMin = 0.1;
  static const _zoomMax = 8.0;

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
  // Contents-drawer vim state (nested tree kept, not flattened to a
  // flat list): selected visible-row index and which parent paths are
  // expanded. Row order = drawer reading order, matching how the tiles
  // are laid out. Enter jumps (selecting the header includes a
  // collapsed parent — no extra "Go to section" row needed).
  final _outlineSel = ValueNotifier<int>(0);
  final _outlineExpandedKeys = ValueNotifier<Set<String>>(<String>{});
  final _outlineScroll = ScrollController();
  // Own focus node for the Contents drawer. Scaffold endDrawer lives in a
  // separate FocusScope (modal route), so the page's _onVimKey never sees
  // keys while the drawer is open — navigation must be handled inside the
  // drawer itself. Mirrors _RecentPagesDialog and FloatingOutlineWindow.
  final _outlineFocus = FocusNode(debugLabel: 'reader-outline');
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
  String get _pageKey => ReadingProgress.pageKey(widget.fileFingerprint);
  String get _goalKey => 'reader_goal_${widget.fileFingerprint}';
  String get _depthKey => 'reader_chapter_depth_${widget.fileFingerprint}';

  Future<void> _savePage(int page) =>
      ReadingProgress.savePage(widget.fileFingerprint, page);

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
    _loadBookmarks();
    // The library sorts "recently read" by this timestamp; opening counts even
    // if the user leaves before the debounced page save fires.
    ReadingProgress.markOpened(widget.fileFingerprint);
    // Standalone page: request focus imperatively after the first frame so
    // vim keys work immediately. `autofocus: true` in build is the backup,
    // but a pushed MaterialPageRoute can drop it during the transition;
    // the host in floating mode does post-frame requestFocus for the same
    // reason (EditorScaffold._focusReader). Centralized here so both hosts
    // share one path — see _onReaderPointerDown for click-to-focus.
    if (widget.focusNode == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _vimFocus.requestFocus();
      });
    }
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
    _bookmarks.dispose();
    _depthNotifier.dispose();
    _outlineSel.dispose();
    _outlineExpandedKeys.dispose();
    _outlineScroll.dispose();
    _outlineFocus.dispose();
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
  // Bookmarks (client-side only; per file, persisted in SharedPreferences)
  // ---------------------------------------------------------------------------

  // Pages the user saved, ascending. A page bookmark is enough: the label is
  // derived from the outline at read time (_recentLabel), so it stays correct
  // if the outline is reloaded or the chapter depth changes.
  String get _bookmarksKey => 'reader_bookmarks_${widget.fileFingerprint}';
  final _bookmarks = ValueNotifier<List<int>>(const []);

  bool _isBookmarked(int page) => _bookmarks.value.contains(page);

  Future<void> _loadBookmarks() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getStringList(_bookmarksKey) ?? const <String>[];
    final pages = <int>{};
    for (final s in raw) {
      final p = int.tryParse(s);
      if (p != null && p > 0) pages.add(p);
    }
    final sorted = pages.toList()..sort();
    if (mounted) _bookmarks.value = sorted;
  }

  Future<void> _persistBookmarks(List<int> pages) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setStringList(_bookmarksKey, [for (final p in pages) '$p']);
  }

  // Add/remove the current page (or [page] when the dialog toggles it).
  void _toggleBookmark([int? page]) {
    final p = page ?? _controller.pageNumber ?? _pageNotifier.value;
    final current = _bookmarks.value;
    final wasSaved = current.contains(p);
    final next = [...current];
    if (wasSaved) {
      next.remove(p);
    } else {
      next
        ..add(p)
        ..sort();
    }
    _bookmarks.value = next;
    _persistBookmarks(next);
    _celebrate(wasSaved ? 'Bookmark removed (p. $p)' : 'Bookmarked p. $p');
  }

  void _removeBookmark(int page) {
    final next = [..._bookmarks.value]..remove(page);
    _bookmarks.value = next;
    _persistBookmarks(next);
  }

  Future<void> _showBookmarks() async {
    final current = _controller.pageNumber ?? _pageNotifier.value;
    final picked = await showDialog<int>(
      context: context,
      builder:
          (_) => _BookmarksDialog(
            pages: List<int>.of(_bookmarks.value),
            labelFor: _recentLabel,
            onDelete: _removeBookmark,
            currentPage: current,
            onToggleCurrent: () => _toggleBookmark(current),
            snapshot: () => List<int>.of(_bookmarks.value),
          ),
    );
    if (!mounted) return;
    if (picked != null) _goToPage(picked);
    _vimFocus.requestFocus();
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
    List<PdfOutlineNode> outline = const [];
    try {
      outline = await document.loadOutline();
    } catch (_) {
      // A broken outline shouldn't stop the document from being readable.
    }
    // Sidecar fallback, ONLY when this PDF ships no embedded outline. The
    // daemon's .toc.json is otherwise ignored — embedded is always preferred
    // when present, so generated entries never shadow an authoritative TOC.
    if (outline.isEmpty) {
      try {
        final sidecar = await KnowledgebaseApi.fetchToc(widget.fileFingerprint);
        if (sidecar.isNotEmpty) {
          outline = _buildOutlineTreeFromSidecar(sidecar);
        }
      } catch (_) {
        // No TOC available — reader falls back to "Page X of Y".
      }
    }
    if (mounted) {
      setState(() {
        _outline = outline;
        _flatOutline = _flatten(outline, const []);
        _autoDepth = _detectChapterDepth(_flatOutline);
        final pref = _depthNotifier.value;
        _chapterDepth = pref > 0 ? pref : _autoDepth;
      });
    }
  }

  // Build a nested PdfOutlineNode tree from the daemon sidecar's flat
  // [level, title, page] list (document order) so the drawer, chapter
  // detection and chip all reuse the embedded-outline code path verbatim.
  List<PdfOutlineNode> _buildOutlineTreeFromSidecar(
    List<Map<String, dynamic>> entries,
  ) {
    // PdfOutlineNode is immutable + value-equality, so it can't be a
    // mutable tree key (duplicates would collide). Build with a holder.
    final roots = <_SidecarBuilder>[];
    final stack = <({int level, _SidecarBuilder node})>[];

    for (final e in entries) {
      final title = (e['title'] ?? '').toString().trim();
      final page = (e['page'] as num?)?.toInt() ?? 0;
      if (title.isEmpty || page <= 0) continue;
      final level = (e['level'] as num?)?.toInt() ?? 1;
      final node = _SidecarBuilder(title, page);
      while (stack.isNotEmpty && stack.last.level >= level) {
        stack.removeLast();
      }
      if (stack.isEmpty) {
        roots.add(node);
      } else {
        stack.last.node.children.add(node);
      }
      stack.add((level: level, node: node));
    }

    PdfOutlineNode freeze(_SidecarBuilder b) {
      return PdfOutlineNode(
        title: b.title,
        dest: PdfDest(b.page, PdfDestCommand.xyz, const [null, null, null]),
        children: b.children.map(freeze).toList(),
      );
    }

    return roots.map(freeze).toList();
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

  String _outlineKey(List<int> path) => path.join('/');

  List<_OutlineRow> _visibleOutlineRows() {
    final out = <_OutlineRow>[];
    void walk(List<PdfOutlineNode> nodes, List<int> parent, int depth) {
      for (var i = 0; i < nodes.length; i++) {
        final node = nodes[i];
        final path = <int>[...parent, i];
        out.add((node: node, path: path, depth: depth));
        if (node.children.isNotEmpty &&
            _outlineExpandedKeys.value.contains(_outlineKey(path))) {
          walk(node.children, path, depth + 1);
        }
      }
    }

    walk(_outline, const <int>[], 0);
    return out;
  }

  int _outlineIndexOf(List<_OutlineRow> rows, List<int> path) =>
      rows.indexWhere((r) => _outlineKey(r.path) == _outlineKey(path));

  void _ensureOutlineVisible(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_outlineScroll.hasClients) return;
      final target = (index * 44.0).clamp(
        0.0,
        _outlineScroll.position.maxScrollExtent,
      );
      _outlineScroll.animateTo(
        target,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    });
  }

  void _outlineMove(int delta) {
    final rows = _visibleOutlineRows();
    if (rows.isEmpty) return;
    final next = (_outlineSel.value + delta).clamp(0, rows.length - 1);
    _outlineSel.value = next;
    _ensureOutlineVisible(next);
  }

  void _setOutlineExpanded(List<int> path, bool expanded) {
    final key = _outlineKey(path);
    final set = <String>{..._outlineExpandedKeys.value};
    if (expanded) {
      set.add(key);
    } else {
      set.remove(key);
    }
    _outlineExpandedKeys.value = set;
  }

  void _toggleOutlineExpand(int index, bool? expand) {
    final rows = _visibleOutlineRows();
    if (index < 0 || index >= rows.length) return;
    final row = rows[index];
    if (row.node.children.isEmpty) return;
    final key = _outlineKey(row.path);
    _setOutlineExpanded(
      row.path,
      expand ?? !_outlineExpandedKeys.value.contains(key),
    );
  }

  void _outlineJumpTo(int index) {
    final rows = _visibleOutlineRows();
    if (index < 0 || index >= rows.length) return;
    _closeOutline();
    final dest = rows[index].node.dest;
    if (dest != null) _goToDest(dest);
  }

  /// Enter always jumps — header and leaf alike. Unfolding is only
  /// via `l`/`h` (or tapping the header with the mouse).
  void _outlineActivate(int index) => _outlineJumpTo(index);

  void _outlineIndentSelect(int index) {
    final rows = _visibleOutlineRows();
    if (index <= 0 || index >= rows.length) return;
    final row = rows[index];
    final parentPath = row.path.sublist(0, row.path.length - 1);
    if (parentPath.isEmpty) return;
    _setOutlineExpanded(parentPath, false);
    final after = _visibleOutlineRows();
    final parentIdx = _outlineIndexOf(after, parentPath);
    if (parentIdx >= 0) {
      _outlineSel.value = parentIdx;
      _ensureOutlineVisible(parentIdx);
    }
  }

  void _openOutline() {
    if (_outline.isEmpty) return;
    final cur = _pageNotifier.value;
    final rows = _visibleOutlineRows();
    var sel = 0;
    for (final (i, r) in rows.indexed) {
      final p = r.node.dest?.pageNumber;
      if (p != null && p <= cur) sel = i;
    }
    _outlineSel.value = sel;
    _count = '';
    _pendingKey = null;
    _pendingAt = null;
    _scaffoldKey.currentState?.openEndDrawer();
    _ensureOutlineVisible(sel);
    // Drawer opens in its own FocusScope; it must own focus or its j/k keys
    // go nowhere. autofocus:true in _outlineDrawer is the backup.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _outlineFocus.requestFocus();
    });
  }

  void _closeOutline() {
    _scaffoldKey.currentState?.closeEndDrawer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _vimFocus.requestFocus();
    });
  }

  // Drawer-local vim keys. The page's _onVimKey drawer-open branch stays as
  // a fallback, but because Scaffold's endDrawer pushes a modal route with
  // its own FocusScope, the page branch is unreachable while the drawer is
  // open — all drawer keys must be handled here. Shares _count/_pendingKey
  // so counts (5j) and gg/G behave identically to page scrolling.
  KeyEventResult _onOutlineKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (_typingInTextField()) return KeyEventResult.ignored;
    final hk = HardwareKeyboard.instance;
    final key = event.logicalKey;
    if (hk.isAltPressed) return KeyEventResult.ignored;
    final shift = hk.isShiftPressed;
    final ch = event.character;
    const handled = KeyEventResult.handled;

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

    if (key == LogicalKeyboardKey.escape) {
      _count = '';
      _closeOutline();
      return handled;
    }
    if (!shift && key == LogicalKeyboardKey.keyO) {
      _count = '';
      _closeOutline();
      return handled;
    }

    final isDown =
        key == LogicalKeyboardKey.arrowDown ||
        (!shift && key == LogicalKeyboardKey.keyJ);
    final isUp =
        key == LogicalKeyboardKey.arrowUp ||
        (!shift && key == LogicalKeyboardKey.keyK);
    final isLeft =
        key == LogicalKeyboardKey.arrowLeft ||
        (!shift && key == LogicalKeyboardKey.keyH);
    final isRight =
        key == LogicalKeyboardKey.arrowRight ||
        (!shift && key == LogicalKeyboardKey.keyL);
    if (isDown) {
      _outlineMove(_takeCount());
      return handled;
    }
    if (isUp) {
      _outlineMove(-_takeCount());
      return handled;
    }
    if (isRight) {
      _count = '';
      _toggleOutlineExpand(_outlineSel.value, true);
      return handled;
    }
    if (isLeft) {
      _count = '';
      final cur = _visibleOutlineRows();
      final idx = _outlineSel.value.clamp(0, cur.isEmpty ? 0 : cur.length - 1);
      final row = cur.isEmpty ? null : cur[idx];
      if (row != null &&
          _outlineExpandedKeys.value.contains(_outlineKey(row.path))) {
        _toggleOutlineExpand(idx, false);
      } else {
        _outlineIndentSelect(idx);
      }
      return handled;
    }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.space) {
      _count = '';
      _outlineActivate(_outlineSel.value);
      return handled;
    }
    if (key == LogicalKeyboardKey.home) {
      _count = '';
      _outlineSel.value = 0;
      _ensureOutlineVisible(0);
      return handled;
    }
    if (key == LogicalKeyboardKey.end) {
      _count = '';
      final last = _visibleOutlineRows().length - 1;
      _outlineSel.value = last < 0 ? 0 : last;
      _ensureOutlineVisible(_outlineSel.value);
      return handled;
    }
    if (key == LogicalKeyboardKey.keyG) {
      if (shift) {
        _count = '';
        final last = _visibleOutlineRows().length - 1;
        _outlineSel.value = last < 0 ? 0 : last;
        _ensureOutlineVisible(_outlineSel.value);
      } else if (pendingG) {
        _count = '';
        _outlineSel.value = 0;
        _ensureOutlineVisible(0);
      } else {
        _pendingKey = 'g';
        _pendingAt = DateTime.now();
      }
      return handled;
    }
    // Count prefix.
    if (ch != null &&
        ch.length == 1 &&
        ch.compareTo('0') >= 0 &&
        ch.compareTo('9') <= 0 &&
        !(ch == '0' && _count.isEmpty)) {
      _count += ch;
      return handled;
    }
    return handled;
  }

  Widget _outlineTile(
    PdfOutlineNode node,
    List<int> path, {
    double indent = 0,
    required List<_OutlineRow> visible,
  }) {
    void jump() {
      _closeOutline();
      final dest = node.dest;
      if (dest != null) _goToDest(dest);
    }

    final pathKey = _outlineKey(path);
    final nodeIdx = _outlineIndexOf(visible, path);
    final isSel = nodeIdx >= 0 && nodeIdx == _outlineSel.value;
    final selColor = Theme.of(
      context,
    ).colorScheme.primary.withValues(alpha: 0.18);

    if (node.children.isEmpty) {
      return ListTile(
        key: ValueKey('outline-$pathKey'),
        contentPadding: EdgeInsets.only(left: 16 + indent, right: 16),
        dense: true,
        selected: isSel,
        selectedTileColor: selColor,
        title: Text(node.title),
        onTap: () {
          _outlineSel.value = nodeIdx;
          jump();
        },
      );
    }
    final isExpanded = _outlineExpandedKeys.value.contains(pathKey);
    // Split controls (no ExpansionTile): title tap = jump to the
    // section (mirrors Enter), chevron button = expand/collapse
    // (mirrors l/h). Kept as two InkWell targets so a chevron tap can
    // never also jump, and vice versa. ExpansionTile's built-in header
    // tap always toggles, which forced the old "Go to section" row as
    // the only mouse jump — dropping it loses that affordance.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          key: ValueKey('outline-$pathKey'),
          contentPadding: EdgeInsets.only(left: 16 + indent, right: 16),
          dense: true,
          selected: isSel,
          selectedTileColor: selColor,
          title: Text(node.title),
          trailing: IconButton(
            icon: Icon(
              isExpanded ? Icons.expand_more : Icons.chevron_right,
              size: 18,
            ),
            tooltip: isExpanded ? 'Collapse' : 'Expand',
            onPressed: () {
              _outlineSel.value = nodeIdx;
              _toggleOutlineExpand(nodeIdx, null);
            },
          ),
          onTap: () {
            _outlineSel.value = nodeIdx;
            jump();
          },
        ),
        if (isExpanded)
          for (final (i, child) in node.children.indexed)
            _outlineTile(
              child,
              <int>[...path, i],
              indent: indent + 16,
              visible: visible,
            ),
      ],
    );
  }

  Widget _outlineDrawer() {
    return Drawer(
      // Scaffold endDrawer pushes a modal route with its own FocusScope,
      // so the page's _onVimKey never sees keys here. The drawer must own
      // focus (autofocus + _onOutlineKey) — without it j/k do nothing,
      // which is why TOC navigation looked "missing" in both hosts.
      child: Focus(
        focusNode: _outlineFocus,
        autofocus: true,
        onKeyEvent: _onOutlineKey,
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
                child: ListenableBuilder(
                  listenable: Listenable.merge([
                    _outlineSel,
                    _outlineExpandedKeys,
                  ]),
                  builder: (context, _) {
                    final visible = _visibleOutlineRows();
                    return ListView(
                      controller: _outlineScroll,
                      children: [
                        for (final (i, n) in _outline.indexed)
                          _outlineTile(n, <int>[i], visible: visible),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
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
    final dim = (sp.getDouble('reader_pref_dim_strength') ?? 0.0).clamp(
      0.0,
      0.6,
    );
    final loaded = _ReaderPrefs(
      chipMode: _ChipMode.values[modeIdx],
      highContrast: sp.getBool('reader_pref_high_contrast') ?? false,
      textScale: scale,
      barPinned: sp.getBool('reader_pref_bar_pinned') ?? false,
      showTime: sp.getBool('reader_pref_show_time') ?? true,
      dimStrength: dim.toDouble(),
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
    await sp.setDouble('reader_pref_dim_strength', p.dimStrength);
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

  // Click-to-focus, centralized so standalone and floating behave identically.
  // Previously only FloatingReaderWindow had this Listener (on the shared
  // _readerFocus node); standalone had autofocus only and lost vim keys after
  // the first tap/drag stole focus to something else. Request _vimFocus on
  // any pointer-down inside the Reader, except while typing: stealing focus
  // from the search box would eat keystrokes. When the primary focus is the
  // pdf's inner node, _vimFocus.hasFocus is still true (ancestor), so we
  // request unconditionally here — pdfrx's inner handler is also neutralized
  // for zoom (see onKey in _params) so the fine _zoomBy in _onVimKey always
  // wins even if focus races.
  void _onReaderPointerDown() {
    if (!mounted) return;
    if (_typingInTextField()) return;
    final node = _vimFocus;
    if (!node.hasFocus || FocusManager.instance.primaryFocus != node) {
      node.requestFocus();
    }
  }

  void _scrollBy({double dx = 0, double dy = 0}) {
    if (!_controller.isReady) return;
    final m = _controller.value.clone();
    m.storage[12] -= dx; // translation x
    m.storage[13] -= dy; // translation y
    _controller.goTo(m, duration: const Duration(milliseconds: 80));
  }

  // ---------------------------------------------------------------------------
  // [ZOOM] Fine zoom anchored on the centre of the reader, so the page stays
  // centred while you zoom. Replaces pdfrx's zoomUp()/zoomDown(), which jump
  // between fixed stops. Change _zoomStep in [TWEAK] to tune the step size.
  // ---------------------------------------------------------------------------
  void _zoomBy(double factor) {
    if (!_controller.isReady) return;
    final size = context.size;
    if (size == null) return;
    final m = _controller.value.clone();
    final current = m.storage[0];
    if (current <= 0) return;
    final target = (current * factor).clamp(_zoomMin, _zoomMax).toDouble();
    final f = target / current;
    if ((f - 1).abs() < 1e-4) return;
    final cx = size.width / 2, cy = size.height / 2;
    final zoom =
        Matrix4.translationValues(cx, cy, 0) *
        Matrix4.diagonal3Values(f, f, 1) *
        Matrix4.translationValues(-cx, -cy, 0);
    _controller.goTo(zoom * m, duration: const Duration(milliseconds: 80));
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
    final key = event.logicalKey;
    // Zoom chords belong to the reader when it has focus: consuming
    // them here (return handled) keeps the EditorScaffold's global
    // CallbackShortcuts (Ctrl+/Cmd+=/- /0) from zooming the editor
    // instead. Meta is the macOS counterpart of Ctrl for these keys.
    final isZoomKey =
        key == LogicalKeyboardKey.equal ||
        key == LogicalKeyboardKey.minus ||
        key == LogicalKeyboardKey.digit0;
    if (hk.isAltPressed || (hk.isMetaPressed && !isZoomKey)) {
      return KeyEventResult.ignored;
    }
    final ctrl = hk.isControlPressed || hk.isMetaPressed;
    final shift = hk.isShiftPressed;
    final ch = event.character;
    const handled = KeyEventResult.handled;

    // A bare modifier press (e.g. Shift for "G") must not cancel a pending
    // two-key sequence like "gg".
    if (_modifierKeys.contains(key)) return KeyEventResult.ignored;

    // Ctrl/Cmd + = / - / 0: reader zoom. Must run before the drawer
    // swallow below so the PDF zooms even while Contents is open, and
    // must return handled so the scaffold's shortcuts never see it.
    if (ctrl && isZoomKey) {
      _count = '';
      if (key == LogicalKeyboardKey.equal) {
        _zoomBy(_zoomStep);
      } else if (key == LogicalKeyboardKey.minus) {
        _zoomBy(1 / _zoomStep);
      } else if (key == LogicalKeyboardKey.digit0) {
        // No fit-reset API on the pdfrx controller; swallow the chord
        // so it can't leak to the editor's reset/fit-all instead.
      }
      return handled;
    }

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

    // Contents drawer open: vim navigates the outline, NOT the page.
    // Sits before every page-scroll branch below, or j/k would keep
    // scrolling the PDF behind the scrim. Counts work like page scroll
    // (5j = 5 rows), gg/G jump within the list.
    if (_scaffoldKey.currentState?.isEndDrawerOpen ?? false) {
      final isDown =
          key == LogicalKeyboardKey.arrowDown ||
          (!shift && key == LogicalKeyboardKey.keyJ);
      final isUp =
          key == LogicalKeyboardKey.arrowUp ||
          (!shift && key == LogicalKeyboardKey.keyK);
      final isLeft =
          key == LogicalKeyboardKey.arrowLeft ||
          (!shift && key == LogicalKeyboardKey.keyH);
      final isRight =
          key == LogicalKeyboardKey.arrowRight ||
          (!shift && key == LogicalKeyboardKey.keyL);
      if (isDown) {
        _outlineMove(_takeCount());
        return handled;
      }
      if (isUp) {
        _outlineMove(-_takeCount());
        return handled;
      }
      if (isRight) {
        _count = '';
        _toggleOutlineExpand(_outlineSel.value, true);
        return handled;
      }
      if (isLeft) {
        _count = '';
        final cur = _visibleOutlineRows();
        final idx = _outlineSel.value.clamp(
          0,
          cur.isEmpty ? 0 : cur.length - 1,
        );
        final row = cur.isEmpty ? null : cur[idx];
        if (row != null &&
            _outlineExpandedKeys.value.contains(_outlineKey(row.path))) {
          _toggleOutlineExpand(idx, false);
        } else {
          _outlineIndentSelect(idx);
        }
        return handled;
      }
      if (key == LogicalKeyboardKey.enter) {
        _count = '';
        _outlineActivate(_outlineSel.value);
        return handled;
      }
      if (key == LogicalKeyboardKey.home) {
        _count = '';
        _outlineSel.value = 0;
        _ensureOutlineVisible(0);
        return handled;
      }
      if (key == LogicalKeyboardKey.end) {
        _count = '';
        final last = _visibleOutlineRows().length - 1;
        _outlineSel.value = last < 0 ? 0 : last;
        _ensureOutlineVisible(_outlineSel.value);
        return handled;
      }
      if (key == LogicalKeyboardKey.keyG) {
        if (shift) {
          _count = '';
          final last = _visibleOutlineRows().length - 1;
          _outlineSel.value = last < 0 ? 0 : last;
          _ensureOutlineVisible(_outlineSel.value);
        } else if (pendingG) {
          _count = '';
          _outlineSel.value = 0;
          _ensureOutlineVisible(0);
        } else {
          _pendingKey = 'g';
          _pendingAt = DateTime.now();
        }
        return handled;
      }
      if (!shift && key == LogicalKeyboardKey.keyO) {
        _count = '';
        _scaffoldKey.currentState?.closeEndDrawer();
        return handled;
      }
      // Space / Ctrl+* would page-scroll behind the scrim — swallow.
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
    // Shift+R = recent pages (bare r closes the reader — see
    // EditorScaffold._onGlobalKey — so the capital is what stays free).
    if (shift && key == LogicalKeyboardKey.keyR) {
      _count = '';
      _showRecent();
      return handled;
    }
    // b = bookmarks list, Shift+B = bookmark/unbookmark this page. Ctrl+b
    // above is "previous page", so the bare and shifted keys are free.
    if (!shift && key == LogicalKeyboardKey.keyB) {
      _count = '';
      _showBookmarks();
      return handled;
    }
    if (shift && key == LogicalKeyboardKey.keyB) {
      _count = '';
      _toggleBookmark();
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
    if (key == LogicalKeyboardKey.backspace && widget.onBack != null) {
      _count = '';
      widget.onBack!.call();
      return handled;
    }
    if (ch == '`' || ch == "'") {
      _count = '';
      _jumpBack();
      return handled;
    }
    if (ch == '+' || ch == '=') {
      _zoomBy(_zoomStep);
      return handled;
    }
    if (ch == '-') {
      _zoomBy(1 / _zoomStep);
      return handled;
    }

    if (!shift && key == LogicalKeyboardKey.keyO) {
      _openOutline();
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
      (
        'o',
        'contents — in drawer: j/k move, Enter jump, l/h expand, Esc close',
      ),
      ('Shift+R', 'recent pages  (j/k — Enter jump, Esc close)'),
      ('b', 'bookmarks  (j/k — Enter jump, d delete, Esc close)'),
      ('Shift+B', 'bookmark / unbookmark this page'),
      ('i', 'show / hide the where-you-are panel'),
      ('t', 'reading goal & display options'),
      ('m', 'pin / unpin the app bar'),
      ('f', 'focus mode: only the progress strip'),
      ('a', 'annotate on / off'),
      ('u / Ctrl+r', 'undo / redo annotation'),
      ('+ / -', 'zoom  (also Ctrl+ / Ctrl-)'),
      ('Esc', 'clear, leave search / drawing / panel, then back to editor'),
      ('Backspace', 'back to library (floating reader)'),
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

  // ---------------------------------------------------------------------------
  // Recent pages dialog (vim-navigable, mirrors the Contents drawer)
  // ---------------------------------------------------------------------------

  Future<void> _showRecent() async {
    if (_recent.isEmpty) return;
    final picked = await showDialog<int>(
      context: context,
      builder:
          (_) => _RecentPagesDialog(
            pages: List<int>.of(_recent),
            labelFor: _recentLabel,
          ),
    );
    if (!mounted) return;
    if (picked != null) {
      _jumpToRecent(picked);
    }
    _vimFocus.requestFocus();
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
                IconButton(
                  tooltip: 'Recent pages',
                  icon: const Icon(Icons.history),
                  onPressed: _recent.isEmpty ? null : _showRecent,
                ),
                ListenableBuilder(
                  listenable: Listenable.merge([_pageNotifier, _bookmarks]),
                  builder: (context, _) {
                    final page = _pageNotifier.value;
                    final marked = _isBookmarked(page);
                    return IconButton(
                      tooltip:
                          marked
                              ? 'Bookmarks — page $page saved (b)'
                              : 'Bookmarks (b)',
                      icon: Icon(
                        marked ? Icons.bookmarks : Icons.bookmarks_outlined,
                      ),
                      onPressed: _showBookmarks,
                    );
                  },
                ),
                if (_outline.isNotEmpty)
                  IconButton(
                    tooltip: 'Contents',
                    icon: const Icon(Icons.toc),
                    onPressed: _openOutline,
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
      // Single owner for zoom keys: pdfrx's inner _onKey would otherwise
      // intercept Ctrl/Cmd + - / 0 with coarse 2x zoom stops (and those
      // stops then clamp at its fit-page floor), so Reader's fine centre-
      // anchored _zoomBy in _onVimKey never sees them when its own Focus
      // node happens to be the primary focus — or when focus has raced to
      // pdfrx's inner node after a tap/pan (FocusFocus). Returning false
      // lets the key bubble up to _onVimKey; returning null would invoke
      // pdfrx's default handler, returning true would swallow without
      // zooming. Arrows/PageUp/Space stay with pdfrx (null path) because
      // Reader's vim keys don't cover raw arrows outside the drawer.
      onKey: (params, key, isRealKeyPress) {
        final isZoomKey =
            key == LogicalKeyboardKey.equal ||
            key == LogicalKeyboardKey.minus ||
            key == LogicalKeyboardKey.digit0;
        if (isZoomKey &&
            (HardwareKeyboard.instance.isControlPressed ||
                HardwareKeyboard.instance.isMetaPressed)) {
          return false;
        }
        return null;
      },
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

          // Dark-mode page tint. Overlay only (IgnorePointer): never sits
          // in the PdfViewer's hit path and never rebuilds the viewer —
          // the slider just notifies _prefs.
          Positioned.fill(
            child: ListenableBuilder(
              listenable: _prefs,
              builder: (context, _) {
                final s = _prefs.value.dimStrength;
                if (s <= 0 || Theme.of(context).brightness != Brightness.dark) {
                  return const SizedBox.shrink();
                }
                return IgnorePointer(
                  child: Container(color: Colors.black.withValues(alpha: s)),
                );
              },
            ),
          ),

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
                  automaticallyImplyLeading: widget.onBack == null,
                  leading:
                      widget.onBack != null
                          ? IconButton(
                            icon: const BackButtonIcon(),
                            tooltip: 'Back to library',
                            onPressed: widget.onBack,
                          )
                          : null,
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
      // Standalone page: take focus so keys work immediately (post-frame
      // request in initState is the robust path; autofocus is the backup).
      // Hosted in the floating window the host moves focus explicitly
      // (r / Ctrl+w); click-to-focus is centralized in _onReaderPointerDown
      // so both hosts behave the same.
      autofocus: widget.focusNode == null,
      onKeyEvent: _onVimKey,
      // Listener (translucent) never blocks the viewer or toolbars: it only
      // reclaims vim focus on pointer-down, exactly as FloatingReaderWindow
      // used to do externally. See _onReaderPointerDown for the typing guard.
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _onReaderPointerDown(),
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
                    Text(
                      'Night dimmer  ·  ${(p.dimStrength * 100).round()}%',
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Slider(
                      value: p.dimStrength,
                      min: 0.0,
                      max: 0.6,
                      divisions: 12,
                      label:
                          p.dimStrength <= 0
                              ? 'Off'
                              : '${(p.dimStrength * 100).round()}%',
                      onChanged: (v) => set(p.copyWith(dimStrength: v)),
                    ),
                    Text(
                      p.dimStrength <= 0
                          ? 'Off — page renders normally.'
                          : 'Dims the page in dark mode only. '
                              '0% is off, 60% is strongest.',
                      style: theme.textTheme.bodySmall,
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

/// Recent-pages popup: vim-navigable list mirroring the Contents
/// drawer (j/k/arrows move, Enter picks, Esc closes). Owns its focus
/// so the main reader's `_onVimKey` never sees the keys — page scroll
/// can't leak behind it.
class _RecentPagesDialog extends StatefulWidget {
  final List<int> pages;
  final String Function(int) labelFor;
  const _RecentPagesDialog({required this.pages, required this.labelFor});

  @override
  State<_RecentPagesDialog> createState() => _RecentPagesDialogState();
}

class _RecentPagesDialogState extends State<_RecentPagesDialog> {
  int _sel = 0;
  final _focus = FocusNode(debugLabel: 'recent-vim');
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _move(int delta) {
    if (widget.pages.isEmpty) return;
    setState(() {
      _sel = (_sel + delta).clamp(0, widget.pages.length - 1);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        (_sel * 40.0).clamp(0.0, _scroll.position.maxScrollExtent),
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      );
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    const handled = KeyEventResult.handled;
    final down =
        key == LogicalKeyboardKey.arrowDown ||
        (!shift && key == LogicalKeyboardKey.keyJ);
    final up =
        key == LogicalKeyboardKey.arrowUp ||
        (!shift && key == LogicalKeyboardKey.keyK);
    if (down) {
      _move(1);
      return handled;
    }
    if (up) {
      _move(-1);
      return handled;
    }
    if (key == LogicalKeyboardKey.home) {
      setState(() => _sel = 0);
      return handled;
    }
    if (key == LogicalKeyboardKey.end) {
      setState(() => _sel = widget.pages.length - 1);
      return handled;
    }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.space) {
      if (widget.pages.isNotEmpty) {
        Navigator.of(context).pop(widget.pages[_sel]);
      }
      return handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return handled;
    }
    // Swallow everything else so the page can't scroll behind the dialog.
    return handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: AlertDialog(
        title: const Text('Recent pages'),
        content: SizedBox(
          width: 360,
          child:
              widget.pages.isEmpty
                  ? const Text('No recent pages')
                  : ListView.builder(
                    controller: _scroll,
                    shrinkWrap: true,
                    itemCount: widget.pages.length,
                    itemBuilder: (context, i) {
                      final p = widget.pages[i];
                      return MouseRegion(
                        onEnter: (_) => setState(() => _sel = i),
                        child: ListTile(
                          dense: true,
                          selected: i == _sel,
                          title: Text(widget.labelFor(p)),
                          onTap: () => Navigator.of(context).pop(p),
                        ),
                      );
                    },
                  ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}

/// Bookmark popup: vim-navigable list mirroring the recent-pages dialog
/// (j/k/arrows move, Enter jumps, d/Delete removes, Esc closes). Owns its
/// focus so the main reader's `_onVimKey` never sees the keys. Deletion and
/// the current-page toggle call back into the Reader, which owns persistence.
class _BookmarksDialog extends StatefulWidget {
  final List<int> pages;
  final String Function(int) labelFor;
  final void Function(int) onDelete;
  final int currentPage;
  final VoidCallback onToggleCurrent;
  final List<int> Function() snapshot;
  const _BookmarksDialog({
    required this.pages,
    required this.labelFor,
    required this.onDelete,
    required this.currentPage,
    required this.onToggleCurrent,
    required this.snapshot,
  });

  @override
  State<_BookmarksDialog> createState() => _BookmarksDialogState();
}

class _BookmarksDialogState extends State<_BookmarksDialog> {
  late List<int> _pages = List<int>.of(widget.pages);
  int _sel = 0;
  final _focus = FocusNode(debugLabel: 'bookmarks-vim');
  final _scroll = ScrollController();

  bool get _currentSaved => _pages.contains(widget.currentPage);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _move(int delta) {
    if (_pages.isEmpty) return;
    setState(() {
      _sel = (_sel + delta).clamp(0, _pages.length - 1);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        (_sel * 40.0).clamp(0.0, _scroll.position.maxScrollExtent),
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      );
    });
  }

  void _deleteSelected() {
    if (_pages.isEmpty) return;
    final page = _pages[_sel];
    widget.onDelete(page);
    setState(() {
      _pages = widget.snapshot();
      if (_sel >= _pages.length) _sel = math.max(0, _pages.length - 1);
    });
  }

  void _toggleCurrent() {
    widget.onToggleCurrent();
    setState(() => _pages = widget.snapshot());
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    const handled = KeyEventResult.handled;
    final down =
        key == LogicalKeyboardKey.arrowDown ||
        (!shift && key == LogicalKeyboardKey.keyJ);
    final up =
        key == LogicalKeyboardKey.arrowUp ||
        (!shift && key == LogicalKeyboardKey.keyK);
    if (down) {
      _move(1);
      return handled;
    }
    if (up) {
      _move(-1);
      return handled;
    }
    if (key == LogicalKeyboardKey.home) {
      setState(() => _sel = 0);
      return handled;
    }
    if (key == LogicalKeyboardKey.end) {
      setState(() => _sel = _pages.isEmpty ? 0 : _pages.length - 1);
      return handled;
    }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.space) {
      if (_pages.isNotEmpty) Navigator.of(context).pop(_pages[_sel]);
      return handled;
    }
    if (!shift &&
        (key == LogicalKeyboardKey.keyD ||
            key == LogicalKeyboardKey.delete ||
            key == LogicalKeyboardKey.backspace)) {
      _deleteSelected();
      return handled;
    }
    if (shift && key == LogicalKeyboardKey.keyB) {
      _toggleCurrent();
      return handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return handled;
    }
    // Swallow everything else so the page can't scroll behind the dialog.
    return handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: AlertDialog(
        title: const Text('Bookmarks'),
        content: SizedBox(
          width: 360,
          child:
              _pages.isEmpty
                  ? const Text(
                    'No bookmarks yet.\nPress Shift+B on a page to add one.',
                  )
                  : ListView.builder(
                    controller: _scroll,
                    shrinkWrap: true,
                    itemCount: _pages.length,
                    itemBuilder: (context, i) {
                      final p = _pages[i];
                      return MouseRegion(
                        onEnter: (_) => setState(() => _sel = i),
                        child: ListTile(
                          dense: true,
                          selected: i == _sel,
                          leading: const Icon(Icons.bookmark, size: 18),
                          title: Text(widget.labelFor(p)),
                          onTap: () => Navigator.of(context).pop(p),
                        ),
                      );
                    },
                  ),
        ),
        actions: [
          TextButton(
            onPressed: _toggleCurrent,
            child: Text(
              _currentSaved
                  ? 'Remove p. ${widget.currentPage}'
                  : 'Bookmark p. ${widget.currentPage}',
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
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
