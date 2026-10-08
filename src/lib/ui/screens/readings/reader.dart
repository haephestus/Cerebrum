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
//  - PAN/ZOOM LOCK REMOVED: while drawing mode is on, scribble's
//    GestureCatcher claims only stylus/mouse pointers (store.pointerMode), so
//    touch still scrolls and pinches (annotations.dart item 2; gate a verified
//    from scribble's pan_gesture_catcher.dart supportedDevices).
//  - TOOLBAR = the editor's ToolDialHub, shown ONLY while drawing (same
//    coupling as EditorScaffold's drawingEnabled): the AppBar's Annotate
//    button enters drawing mode, Done leaves it, and the dial appears with it
//    — no separate "show the wheel" state, so the first tap on a chip always
//    lands on an armed canvas. The dial is re-pointed at the active page's
//    notifier by a store listener (a captured one would undo the wrong page).
//    Undo/redo in the AppBar follow the active page's ScribbleNotifier
//    directly: the store no longer broadcasts per-sketch changes (see
//    annotations.dart item 9), so the buttons must listen where the state
//    actually changes.
//  - ERROR HANDLING: pdfrx banners wired (errorBannerBuilder /
//    loadingBannerBuilder) — replaces Syncfusion's onDocumentLoadFailed snack.
//  - PAGE JUMP: KnowledgebaseApi.readFile is called with page: null so the
//    `#page=N` fragment never enters pdfrx's cache key (each fragment caused a
//    separate full download); initialPageNumber covers the jump.
//
// Still TODO (see annotations.dart for details):
//  - Device-verify that pageOverlaysBuilder widgets are laid out at page size
//    and scale with zoom (items a/b), that stylus doesn't also pan the viewer,
//    and rotated/cropped PDFs align.
//  - TEXT SELECTION: enabled only when no tool is active. Wire selection into
//    text-snapped highlight/underline — the model is in place
//    (HighlightAnnotation), the pdfrx hook is item 4 in annotations.dart.
//  - STICKY NOTES UI (model ready: NoteAnnotation) / EXPORT / SYNC / drift
//    persistence (items 1, 5, 6, 7).
//  - Anything else that used SfPdfViewer / PdfViewerController from Syncfusion
//    elsewhere in the app must be ported too; grep for
//    `syncfusion_flutter_pdfviewer`.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
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
  late final AnnotationStore _store;
  late Future<AuthenticatedPdfData> _pdfDataFuture;

  @override
  void initState() {
    super.initState();
    _store = AnnotationStore(widget.fileFingerprint)..load();
    _pdfDataFuture = KnowledgebaseApi.readFile(widget.fileFingerprint, null);
  }

  @override
  void dispose() {
    _store.dispose();
    super.dispose();
  }

  List<Widget> _toolbar() => [
    // Two listeners, deliberately: the OUTER one follows the store (active
    // page / drawing mode / tool broadcast — rare events), the INNER one
    // follows that page's ScribbleNotifier for undo/redo availability. The
    // store does NOT broadcast per-sketch changes any more (it used to rebuild
    // the whole viewer on every pointer move, annotations.dart item 9), so
    // reading canUndo/canRedo off the store would go stale after each stroke.
    ListenableBuilder(
      listenable: _store,
      builder: (context, _) {
        final notifier = _store.activeNotifier;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
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
              onPressed: _store.toggleDrawingMode,
            ),
          ],
        );
      },
    ),
  ];

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

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AuthenticatedPdfData>(
      future: _pdfDataFuture,
      builder: (context, snapshot) {
        final pdfData = snapshot.data;
        final title = pdfData?.filename ?? 'PDF';

        return Scaffold(
          appBar: AppBar(title: Text(title), actions: _toolbar()),
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
                  // Rebuilds params on the store's rare broadcasts — drawing
                  // mode on/off (the overlays' IgnorePointer and text
                  // selection both follow it) and active-page changes. Sketch
                  // edits do NOT reach here any more: the store only debounces
                  // a save on them (annotations.dart item 9), so drawing at
                  // speed no longer rebuilds this subtree per pointer move.
                  ListenableBuilder(
                    listenable: _store,
                    builder:
                        (context, _) => PdfViewer.uri(
                          Uri.parse(pdfData!.url),
                          headers: pdfData.headers,
                          controller: _controller,
                          initialPageNumber: widget.page ?? 1,
                          params: PdfViewerParams(
                            // No pan/zoom lock: scribble's pointer-kind filter
                            // (store.pointerMode) claims only stylus/mouse
                            // while drawing, so touch scrolls/zooms.
                            textSelectionParams: PdfTextSelectionParams(
                              enabled: !_store.drawing,
                            ),
                            onPageChanged: (pageNumber) {
                              if (pageNumber != null) {
                                _store.setActivePage(pageNumber);
                              }
                            },
                            errorBannerBuilder: _errorBanner,
                            loadingBannerBuilder: _loadingBanner,
                            pageOverlaysBuilder:
                                (context, pageRect, page) => [
                                  ReaderInkPage(store: _store, page: page),
                                ],
                          ),
                        ),
                  ),
                  // Mirrors EditorScaffold: the dial exists only IN drawing
                  // mode (Annotate enters it; Done leaves), and the store
                  // listener re-points it at the ACTIVE page's notifier — a
                  // captured notifier would keep sending undo/redo to the page
                  // that was active when the dial opened. Positioned must stay
                  // the direct Stack child (nesting it in the builder would
                  // break parent-data); an empty box while not drawing is
                  // zero-sized, so it can't swallow pointers.
                  Positioned.fill(
                    child: ListenableBuilder(
                      listenable: _store,
                      builder:
                          (context, _) =>
                              _store.drawing
                                  ? ToolDialHub(
                                    notifier: _store.activeNotifier,
                                    // Tool/colour/size selections follow across
                                    // pages (same broadcast pattern as
                                    // PagedNoteController.applyDrawingTool);
                                    // undo/redo stay page-local.
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
