// =============================================================================
// READER INK PAGE: canonical-canvas scribble overlay for one PDF page.
//
// pdfrx's pageOverlaysBuilder wraps each returned widget in a Positioned of the
// page's CURRENT zoom-scaled rect, so the overlay's layout size changes on
// every zoom/pan frame. Scribble records points in its own widget's local
// pixels, so a canvas that fills the overlay would drift the moment the page is
// zoomed. The fix is a FIXED logical canvas inside a FittedBox:
//
//   * the canvas is sized to the page's PDF-point dimensions (PdfPage.width x
//     PdfPage.height — already rotated, see pdfrx_engine's PdfPage);
//   * FittedBox(fit: fill) maps that canvas onto the overlay rect through its
//     paint AND hit-test transforms. RenderFittedBox lays its child out with
//     UNBOUNDED constraints (packages/flutter/.../proxy_box.dart) so the
//     fixed-size canvas keeps its own size, and its hit test maps the pointer
//     through the same transform — `Listener` localPositions (strokes AND the
//     partial eraser) are therefore always in canonical page space;
//   * strokes are glued to the page content at any zoom, pen width scales with
//     the page (correct annotation semantics), and the normalized persistence
//     model is a pure divide by the canvas size.
//
// Pointer routing: this layer only takes pointers while store.drawing is true
// (wrapped in IgnorePointer otherwise), and HitTestPassThrough keeps the hit
// test running PAST this overlay so pdfrx's InteractiveViewer underneath still
// takes part while drawing is armed — otherwise the Stack would stop here and
// wheel/trackpad scrolling over a page would go dead (see HitTestPassThrough).
// Scribble's GestureCatcher claims ONLY the pointer kinds in store.pointerMode
// (stylus/mouse by default), so the gesture arena hands touch pointers to the
// viewer's pan/zoom — the viewer itself never locks pan/zoom (see reader.dart).
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:cerebrum/ui/screens/editor/widgets/drawing_layer.dart';
import 'package:cerebrum/ui/screens/readings/annotations.dart';

/// One PDF page's ink layer: canonical canvas + FittedBox + the editor's
/// NoteDrawingLayer (scribble, with the partial/whole-stroke eraser).
///
/// Registers the page's canonical size with [store] on every build (idempotent)
/// so the store can materialize/save normalized strokes at the right scale, and
/// reports pointer-downs so undo/redo and the tool dial target the page the
/// user last touched.
class ReaderInkPage extends StatelessWidget {
  const ReaderInkPage({super.key, required this.store, required this.page});

  final AnnotationStore store;
  final PdfPage page;

  @override
  Widget build(BuildContext context) {
    // Clamp against degenerate (unloaded) sizes so the FittedBox never divides
    // by zero; pdfrx uses the same values for the overlay rect, so a fixed
    // canvas of this aspect maps onto the page 1:1.
    final size = Size(
      page.width > 0 ? page.width : 1,
      page.height > 0 ? page.height : 1,
    );
    store.setPageSize(page.pageNumber, size);
    final notifier = store.notifierFor(page.pageNumber);

    return ListenableBuilder(
      // Rebuilds this overlay when `drawing` toggles (tool picked / exited).
      // Per-pointer moves repaint only the scribble canvas beneath via its own
      // notifier; the store's notify is coalesced by the save debounce.
      listenable: store,
      builder: (context, _) {
        final drawing = store.drawing;
        return HitTestPassThrough(
          child: Listener(
            // deferToChild: the canvas decides what is hittable underneath; we
            // only observe when something on this page was actually touched.
            behavior: HitTestBehavior.deferToChild,
            onPointerDown: (_) => store.setActivePage(page.pageNumber),
            child: IgnorePointer(
              ignoring: !drawing,
              child: FittedBox(
                fit: BoxFit.fill,
                alignment: Alignment.topLeft,
                clipBehavior: Clip.none,
                child: SizedBox(
                  width: size.width,
                  height: size.height,
                  child: NoteDrawingLayer(
                    notifier: notifier,
                    partialEraser: store.partialEraser,
                    eraserWidth: store.eraserWidth,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Records this subtree in the pointer's hit path WITHOUT ending the hit test,
/// so whatever is painted underneath is hit-tested too.
///
/// pdfrx builds one Stack whose children, in order, are its InteractiveViewer,
/// the link overlay and then the pageOverlaysBuilder overlays (pdfrx
/// pdf_viewer.dart). A Stack hit-tests from its LAST child backwards and stops
/// at the first hit — so once the ink overlay above a page is armed it becomes
/// the hit test's endpoint and the InteractiveViewer beneath never enters the
/// path. Its wheel Listener then gets no signal events at all: wheel and
/// trackpad scrolling over a page silently die while drawing, and touch could
/// not pan either.
///
/// This wrapper reports a miss after letting its children register, so the
/// parent Stack keeps testing the viewer below. Ownership is left entirely to
/// the gesture arena and the pointer-signal resolver, exactly as in the
/// margins around a page:
///
///  * scribble's GestureCatcher claims stylus/mouse (draw);
///  * touch reaches the viewer's pan/zoom recognizer (scroll);
///  * over the page itself the viewer's Listener is the only signal handler, so
///    wheel, trackpad and ctrl-wheel zoom run pdfrx's own code — no scroll math
///    is duplicated here. (Inside the tool dial's hub circle the dial still
///    takes the wheel first, which is its resize gesture.)
class HitTestPassThrough extends SingleChildRenderObjectWidget {
  const HitTestPassThrough({super.key, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPassThroughHit();
}

class _RenderPassThroughHit extends RenderProxyBox {
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    // Children that are hit are added to [result] and keep receiving every
    // event for this pointer; returning false only tells the parent Stack to
    // keep looking behind us, which is the whole point of this widget.
    hitTestChildren(result, position: position);
    return false;
  }
}
