// =============================================================================
// READER: STATUS + TODO (for a coding agent)
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
//  - POSITION INDICATOR: nothing floats over the page. The scroll thumb on the
//    right edge keeps its simple page number; hovering it pops up the chapter
//    breadcrumb (Part › Chapter › Section) and "Page X of Y". The breadcrumb
//    comes from the PDF outline, flattened once on load (_flatOutline); a
//    page's section is the last outline entry starting at or before it. PDFs
//    without an outline show only "Page X of Y". "Go to page" is an app-bar
//    button.
//  - VIM KEYS: the Reader owns a Focus node (own, or one handed in by the host,
//    e.g. FloatingReaderWindow) and handles keys while it has focus and no text
//    field is being typed in. j/k/h/l scroll, Ctrl+d/u half page, Ctrl+f/b page,
//    gg/G first/last page ("41G" = page 41, counts work on j/k/G/gg/Ctrl+f/b),
//    / search + n/N next/prev match, : go to page, o contents, a annotate,
//    u / Ctrl+r undo / redo, +/- zoom, Esc = clear / leave search / leave
//    drawing / hand focus back to the host (onReleaseFocus), ? = cheat sheet.
//    "r" (toggle the floating window) and Ctrl+w (swap focus with the editor)
//    live in the HOST (editor scaffold), not here.
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
// =============================================================================
import 'dart:async';

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
  bool _searching = false;

  // Resume-where-you-left-off state.
  int _lastPage = 1;
  int? _pendingPage;
  Timer? _saveTimer;
  // Page callbacks that fire before the viewer is ready describe the initial
  // jump, not the user reading, so they must not overwrite the saved page.
  bool _viewerReady = false;

  // Distinct prefix from the annotation store's `ink:<fingerprint>` keys.
  String get _pageKey => 'reader_last_page_${widget.fileFingerprint}';

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
      return KnowledgebaseApi.readFile(widget.fileFingerprint, null);
    }();
    _store.drawingListenable.addListener(_onDrawingChanged);
    _searchFocus.onKeyEvent = _onSearchKey;
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
    // Flush the debounced page so leaving right after a scroll isn't lost.
    _saveTimer?.cancel();
    final pending = _pendingPage;
    if (pending != null) _savePage(pending); // fire and forget
    _searcher?.dispose();
    _searchField.dispose();
    _searchFocus.dispose();
    _ownFocus?.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Links
  // ---------------------------------------------------------------------------

  Future<void> _onLinkTap(PdfLink link) async {
    // Don't navigate while the user is annotating.
    if (_store.drawing) return;

    final dest = link.dest;
    if (dest != null) {
      await _controller.goToDest(dest);
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

  Widget _outlineTile(PdfOutlineNode node, {double indent = 0}) {
    void jump() {
      Navigator.of(context).pop(); // close the end drawer
      final dest = node.dest;
      if (dest != null) _controller.goToDest(dest);
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
    final field = TextEditingController();
    final result = await showDialog<int>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Go to page'),
            content: TextField(
              controller: field,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(hintText: '1 – $pageCount'),
              onSubmitted:
                  (v) => Navigator.of(context).pop(int.tryParse(v.trim())),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed:
                    () => Navigator.of(
                      context,
                    ).pop(int.tryParse(field.text.trim())),
                child: const Text('Go'),
              ),
            ],
          ),
    );
    field.dispose();
    if (result != null && result >= 1 && result <= pageCount) {
      _controller.goToPage(pageNumber: result);
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

  // ---------------------------------------------------------------------------
  // Vim keys
  // ---------------------------------------------------------------------------

  static const _scrollStep = 80.0; // px per j/k/h/l press

  // Count prefix ("5j", "41G") and the pending first key of "gg".
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

  void _goToPage(int page) {
    if (!_controller.isReady) return;
    _controller.goToPage(
      pageNumber: page.clamp(1, _controller.pageCount).toInt(),
    );
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

    // Was a lone "g" pressed just before this key? (for gg)
    final pendingG =
        _pendingKey == 'g' &&
        _pendingAt != null &&
        DateTime.now().difference(_pendingAt!) <
            const Duration(milliseconds: 600);
    _pendingKey = null;
    _pendingAt = null;

    // Esc: peel back one layer per press.
    if (key == LogicalKeyboardKey.escape) {
      final scaffold = _scaffoldKey.currentState;
      if (scaffold?.isEndDrawerOpen ?? false) {
        scaffold?.closeEndDrawer();
      } else if (_hasCount || pendingG) {
        _count = '';
      } else if (_store.drawing) {
        _toggleDrawing();
      } else if (_searching) {
        _closeSearch();
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
        _goToPage((_controller.pageNumber ?? 1) + _takeCount());
        return handled;
      }
      if (key == LogicalKeyboardKey.keyB) {
        _goToPage((_controller.pageNumber ?? 1) - _takeCount());
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
      (':', 'go to page'),
      ('/', 'search   (Enter = jump, Esc = close)'),
      ('n / N', 'next / previous match'),
      ('o', 'contents'),
      ('a', 'annotate on / off'),
      ('u / Ctrl+r', 'undo / redo annotation'),
      ('+ / -', 'zoom'),
      ('Esc', 'clear, leave search / drawing, then back to editor'),
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
  // Toolbar
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
                if (_outline.isNotEmpty)
                  IconButton(
                    tooltip: 'Contents',
                    icon: const Icon(Icons.toc),
                    onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
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

          return Scaffold(
            key: _scaffoldKey,
            // endDrawer, not drawer: a start drawer would replace the back button.
            endDrawer: _outline.isEmpty ? null : _outlineDrawer(),
            appBar: AppBar(
              title:
                  _searching
                      ? _searchTitle()
                      : Text(title, overflow: TextOverflow.ellipsis),
              actions: _toolbar(),
            ),
            body: switch (snapshot.connectionState) {
              ConnectionState.waiting => const Center(
                child: CircularProgressIndicator(),
              ),
              _ when snapshot.hasError || !snapshot.hasData => Center(
                child: Text('Error preparing reader: ${snapshot.error}'),
              ),
              _ => SafeArea(
                child: Stack(
                  children: [
                    _onlineReader(pdfData!.url, pdfData.headers, _lastPage),

                    // The dial exists only IN drawing mode and is re-pointed at
                    // the ACTIVE page's notifier. Positioned must stay the direct
                    // Stack child. This builder wraps ONLY ToolDialHub.
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
              ),
            },
          );
        },
      ),
    );
  }
}
