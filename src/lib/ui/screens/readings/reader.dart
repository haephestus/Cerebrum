// =============================================================================
// READER: STATUS + TODO (for a coding agent)
//
// Rewritten from syncfusion_flutter_pdfviewer to pdfrx so we own the annotation
// layer (Syncfusion's Flutter viewer has no ink support, and its xml ^7
// requirement conflicts with appflowy_editor). Remove
// `syncfusion_flutter_pdfviewer` from pubspec.yaml. See annotations.dart for
// the full annotation roadmap.
//
// Not compiled or tested yet. Run `flutter analyze` first.
//
// TODO:
//  - API CHECKED against pdfrx docs: PdfViewer.uri(headers:, initialPageNumber:),
//    PdfViewerParams.textSelectionParams (PdfTextSelectionParams.enabled),
//    panEnabled/scaleEnabled, pageOverlaysBuilder. PdfViewerController is a
//    plain ValueListenable<Matrix4>, so it is not disposed here.
//  - STILL UNVERIFIED (runtime behaviour): that pageOverlaysBuilder's widgets
//    are laid out at page size and scale with zoom (the ink layer relies on
//    this), and that `widget.page` lands on the right page.
//  - ERROR HANDLING: Syncfusion had onDocumentLoadFailed -> SnackBar. Add the
//    pdfrx equivalent (e.g. loading/error banner builders in PdfViewerParams).
//  - COORDINATES: see the COORDINATE MODEL note in annotations.dart (overlay
//    sizing assumption, page rotation/crop box, PDF-space conversion, and what
//    `fileFingerprint` means for annotation identity). Test alignment with
//    zoom, resize, and rotated/cropped PDFs before building more on top.
//  - SCRIBBLE: see the SCRIBBLE note in annotations.dart; evaluating it may
//    change how input is wired here (it may remove the need for the lock below).
//  - PAN/ZOOM LOCK: while a tool is active, panEnabled/scaleEnabled are false so
//    strokes don't fight the viewer. Replace with stylus-only drawing so touch
//    can still scroll/zoom (annotations.dart header item 2). Also consider a
//    visible "drawing mode" indicator and an easy way out.
//  - TEXT SELECTION: enabled only when no tool is active. Wire selection into
//    text-snapped highlight/underline once that API is verified (header item 4).
//  - TOOLBAR UX: currently icon buttons in the AppBar, which will overflow on
//    narrow screens. Move to a collapsible bottom/side toolbar; add clear-page,
//    stroke width preview, and persist the last used tool/color/width.
//  - EXPORT / SHARE: add an "export annotated copy" action (annotations.dart
//    header item 6).
//  - Anything else that used SfPdfViewer / PdfViewerController from Syncfusion
//    elsewhere in the app (search, thumbnails, jump-to-page callers) must be
//    ported too; grep for `syncfusion_flutter_pdfviewer`.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:cerebrum/api/knowledgebase_api.dart';
import 'annotations.dart'; // adjust path to wherever you put it

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

  static const _palette = [
    Color(0xFF1565C0), // blue
    Color(0xFFC62828), // red
    Color(0xFF2E7D32), // green
    Color(0xFFF9A825), // yellow
    Color(0xFF212121), // black
  ];

  @override
  void initState() {
    super.initState();
    _store = AnnotationStore(widget.fileFingerprint)..load();
    _pdfDataFuture = KnowledgebaseApi.readFile(
      widget.fileFingerprint,
      widget.page,
    );
  }

  @override
  void dispose() {
    _store.dispose();
    super.dispose();
  }

  List<Widget> _toolbar() => [
    ListenableBuilder(
      listenable: _store,
      builder: (context, _) {
        Widget tool(IconData icon, String tip, AnnotationTool t) => IconButton(
          tooltip: tip,
          icon: Icon(icon),
          isSelected: _store.tool == t,
          onPressed: () => _store.setTool(t),
        );
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            tool(Icons.edit, 'Pen', AnnotationTool.pen),
            tool(Icons.highlight, 'Highlighter', AnnotationTool.highlighter),
            tool(Icons.cleaning_services, 'Eraser', AnnotationTool.eraser),
            PopupMenuButton<Color>(
              tooltip: 'Color',
              icon: Icon(Icons.circle, color: _store.color),
              onSelected: _store.setColor,
              itemBuilder:
                  (_) => [
                    for (final c in _palette)
                      PopupMenuItem(
                        value: c,
                        child: Icon(Icons.circle, color: c),
                      ),
                  ],
            ),
            PopupMenuButton<double>(
              tooltip: 'Pen width',
              icon: const Icon(Icons.line_weight),
              onSelected: _store.setPenWidth,
              itemBuilder:
                  (_) => const [
                    PopupMenuItem(value: 0.0015, child: Text('Fine')),
                    PopupMenuItem(value: 0.003, child: Text('Medium')),
                    PopupMenuItem(value: 0.006, child: Text('Thick')),
                  ],
            ),
            IconButton(
              tooltip: 'Undo',
              icon: const Icon(Icons.undo),
              onPressed: _store.canUndo ? _store.undo : null,
            ),
            IconButton(
              tooltip: 'Redo',
              icon: const Icon(Icons.redo),
              onPressed: _store.canRedo ? _store.redo : null,
            ),
          ],
        );
      },
    ),
  ];

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
              // Rebuild params when the tool changes so pan/zoom lock while drawing.
              child: ListenableBuilder(
                listenable: _store,
                builder:
                    (context, _) => PdfViewer.uri(
                      Uri.parse(pdfData!.url),
                      headers: pdfData.headers,
                      controller: _controller,
                      initialPageNumber: widget.page ?? 1,
                      params: PdfViewerParams(
                        // TODO(input): temporary lock, see header notes.
                        // TODO(errors): add loading/error banners (replaces
                        // Syncfusion's onDocumentLoadFailed snackbar).
                        panEnabled: !_store.drawing,
                        scaleEnabled: !_store.drawing,
                        // pdfrx 2.x: text selection is configured here, not via
                        // an enableTextSelection flag.
                        textSelectionParams: PdfTextSelectionParams(
                          enabled: !_store.drawing,
                        ),
                        pageOverlaysBuilder:
                            (context, pageRect, page) => [
                              InkPageLayer(
                                store: _store,
                                pageNumber: page.pageNumber,
                              ),
                            ],
                      ),
                    ),
              ),
            ),
          },
        );
      },
    );
  }
}
