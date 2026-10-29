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
import 'package:pdfrx/pdfrx.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cerebrum/api/knowledgebase_api.dart';
import 'package:cerebrum/ui/screens/editor/widgets/radial_tool_dial.dart';
import 'package:cerebrum/ui/screens/readings/annotations.dart';
import 'package:cerebrum/ui/screens/readings/reader_ink_layer.dart';

class Reader extends StatefulWidget {
  final String fileFingerprint;
  final int? page;

  const Reader({super.key, required this.fileFingerprint, this.page});

  @override
  State<Reader> createState() => _ReaderState();
}

class _ReaderState extends State<Reader> {
  final _controller = PdfViewerController();
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _searchField = TextEditingController();
  final _searchFocus = FocusNode();

  late final AnnotationStore _store;
  // Created in onViewerReady: PdfTextSearcher needs a controller that is
  // already attached to a viewer, so it can't be built in initState.
  PdfTextSearcher? _searcher;
  late Future<AuthenticatedPdfData> _pdfDataFuture;

  List<PdfOutlineNode> _outline = const [];
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
      if (mounted) setState(() => _outline = outline);
    } catch (_) {
      // A broken outline shouldn't stop the document from being readable.
    }
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
      onSubmitted: (_) => _searcher?.goToNextMatch(),
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

  Widget _pageIndicator() {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        if (!_controller.isReady) return const SizedBox.shrink();
        final page = _controller.pageNumber;
        final count = _controller.pageCount;
        if (page == null) return const SizedBox.shrink();
        final scheme = Theme.of(context).colorScheme;
        return Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Material(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: _promptJumpToPage,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: Text('$page / $count'),
                ),
              ),
            ),
          ),
        );
      },
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
      scrollByMouseWheel: 0.6,
      scrollByArrowKey: 50,
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
              thumbBuilder:
                  (context, thumbSize, pageNumber, controller) => Container(
                    color: Colors.black.withValues(alpha: 0.6),
                    alignment: Alignment.center,
                    child: Text(
                      pageNumber.toString(),
                      style: const TextStyle(color: Colors.white),
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
    return FutureBuilder<AuthenticatedPdfData>(
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

                  // Page indicator (tap to jump). Hidden while drawing so it
                  // doesn't compete with the tool dial.
                  if (!_store.drawing)
                    Positioned.fill(
                      child: IgnorePointer(
                        ignoring: false,
                        child: _pageIndicator(),
                      ),
                    ),

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
    );
  }
}
