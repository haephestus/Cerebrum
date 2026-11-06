import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cerebrum/ui/themes/theme_access.dart';
import 'package:cerebrum/ui/screens/editor/blocks/table/table_page_bounds.dart';
import 'package:cerebrum/ui/screens/editor/controllers/note_editor_controller.dart';
import 'package:cerebrum/ui/screens/editor/controllers/appflowy_text_driver.dart';
import 'package:cerebrum/ui/screens/editor/helpers/flow_executor.dart'
    show kUseSingleDocumentPagination;
import 'package:cerebrum/ui/screens/editor/widgets/drawing_layer.dart';
import 'package:cerebrum/ui/screens/editor/widgets/page_block_component.dart'
    show kSheetVerticalMargin;
import 'package:cerebrum/ui/screens/editor/widgets/page_space.dart';
import 'package:cerebrum/ui/screens/editor/widgets/paged_editor.dart'
    show BlockAnalysisLookup, followScrollDelta;

class PageSurface extends StatefulWidget {
  const PageSurface({
    super.key,
    required this.controller,
    required this.drawingEnabled,
    this.pageNumber,
    this.pageId,
    this.analysisForBlock,
    this.onOverflow,
    this.onUnderfill,
    this.partialEraser,
    this.eraserWidth,
    this.aspectRatio = kPageAspectRatio,
    this.zoomController,
    this.onViewportChanged,
  });

  final NoteEditorController controller;
  final bool drawingEnabled;
  final ValueNotifier<bool>? partialEraser;
  final ValueListenable<double>? eraserWidth;
  final int? pageNumber;
  final String? pageId;
  final BlockAnalysisLookup? analysisForBlock;
  final void Function(int fromBlockIndex, {double? tableAvailableHeight})?
  onOverflow;
  final void Function(double freeHeight, double? headHeight)? onUnderfill;
  final double aspectRatio;
  final TransformationController? zoomController;
  final void Function(double fitWidth, double fitHeight, Size viewport)?
  onViewportChanged;

  @override
  State<PageSurface> createState() => _PageSurfaceState();
}

class _PageSurfaceState extends State<PageSurface> {
  final GlobalKey _stackKey = GlobalKey();

  AppFlowyTextDriver? _driver;
  int? _activeBlockIndex;
  List<Map<String, dynamic>> _activeChunks = const [];

  bool _overflowCheckScheduled = false;
  bool _initialTransformSet = false;

  Size? _lastReportedSize;
  double? _lastReportedFitW;

  /// B-branch content metrics, refreshed per build — the zoomable canvas's
  /// pan/zoom clamp and the caret follow read these.
  Size? _contentSize;
  Size? _viewportSize;
  final GlobalKey _canvasKey = GlobalKey(debugLabel: 'strategy-b-canvas');
  bool _followScheduled = false;

  @override
  void initState() {
    super.initState();
    final d = widget.controller.driver;
    if (d is AppFlowyTextDriver) {
      _driver = d;
      d.selectionChanges.addListener(_onSelectionChanged);
    }
    widget.controller.addListener(_scheduleOverflowCheck);
    // PageUp / PageDown scroll the canvas like the mouse wheel (see _onKey).
    // A HardwareKeyboard handler, not a focus-tree one: the editor owns
    // keyboard focus, so a Focus widget up here would never see the key.
    if (kUseSingleDocumentPagination) {
      HardwareKeyboard.instance.addHandler(_onKey);
    }
    _scheduleOverflowCheck();
  }

  @override
  void didUpdateWidget(PageSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.analysisForBlock, oldWidget.analysisForBlock)) {
      final next = _resolveActive();
      _activeBlockIndex = next?.$1;
      _activeChunks = next?.$2 ?? const [];
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _driver?.selectionChanges.removeListener(_onSelectionChanged);
    widget.controller.removeListener(_scheduleOverflowCheck);
    super.dispose();
  }

  /// PageDown / PageUp: pan the canvas by ~90% of the viewport height — the
  /// same matrix write the mouse wheel does, so it is independent of the
  /// caret and can walk past the last block into the empty paper below
  /// (j/k only ever move between blocks). Returns true to consume the key so
  /// AppFlowy's own page-up/down command doesn't also act on it.
  bool _onKey(KeyEvent event) {
    if (event is KeyUpEvent) return false;
    final key = event.logicalKey;
    final down = key == LogicalKeyboardKey.pageDown;
    if (!down && key != LogicalKeyboardKey.pageUp) return false;
    final hk = HardwareKeyboard.instance;
    if (hk.isControlPressed || hk.isAltPressed || hk.isMetaPressed) {
      return false;
    }
    if (!mounted) return false;
    // Only the visible route reacts (a pushed screen/dialog keeps this
    // surface mounted underneath).
    if (ModalRoute.of(context)?.isCurrent == false) return false;
    final tc = widget.zoomController;
    final viewport = _viewportSize;
    final content = _contentSize;
    if (tc == null || viewport == null || content == null) return false;

    final dy = viewport.height * 0.9 * (down ? 1 : -1);
    final moved =
        Matrix4.identity()
          ..translate(0.0, -dy)
          ..multiply(tc.value);
    tc.value = _ZoomableCanvas.clampCanvasMatrix(
      moved,
      viewport: viewport,
      content: content,
    );
    return true;
  }

  void _scheduleOverflowCheck() {
    if (_overflowCheckScheduled ||
        (widget.onOverflow == null && widget.onUnderfill == null)) {
      return;
    }
    _overflowCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _overflowCheckScheduled = false;
      _checkOverflow();
    });
  }

  void _checkOverflow() {
    if (!mounted || widget.drawingEnabled) return;
    final onOverflow = widget.onOverflow;
    final driver = _driver;
    if ((onOverflow == null && widget.onUnderfill == null) || driver == null) {
      return;
    }
    final stackBox = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (stackBox == null || !stackBox.hasSize) return;
    final pageBottomLocal = stackBox.size.height;
    final blocks =
        (widget.controller.documentJson['children'] as List?) ?? const [];
    const tolerance = 0.5;
    double? headHeight;
    double? lastBottomLocal;
    for (var i = 0; i < blocks.length; i++) {
      final rect = driver.rectOfBlock(i);
      if (rect == null) continue;
      final topLocal = stackBox.globalToLocal(rect.topLeft);
      final bottomLocal = stackBox.globalToLocal(rect.bottomLeft).dy;
      if (i == 0) headHeight = bottomLocal - topLocal.dy;
      lastBottomLocal = bottomLocal;
      if (bottomLocal > pageBottomLocal + tolerance) {
        final isTable = (blocks[i] as Map?)?['type'] == 'table';
        if (i == 0 && !isTable) continue;
        onOverflow?.call(
          i,
          tableAvailableHeight: isTable ? pageBottomLocal - topLocal.dy : null,
        );
        return;
      }
    }
    final onUnderfill = widget.onUnderfill;
    if (onUnderfill == null || lastBottomLocal == null) return;
    final free = pageBottomLocal - lastBottomLocal;
    if (free <= 0) return;
    onUnderfill(free, headHeight);
  }

  (int, List<Map<String, dynamic>>)? _resolveActive() {
    final lookup = widget.analysisForBlock;
    final pageId = widget.pageId;
    final driver = _driver;
    if (lookup == null || pageId == null || driver == null) return null;
    final idx = driver.selectedBlockIndex;
    final blockId = driver.selectedBlockId;
    if (idx == null || blockId == null) return null;
    final chunks = lookup(pageId, blockId);
    if (chunks == null || chunks.isEmpty) return null;
    return (idx, chunks);
  }

  void _onSelectionChanged() {
    _scheduleFollow();
    final next = _resolveActive();
    if (next?.$1 == _activeBlockIndex) return;
    if (!mounted) return;
    setState(() {
      _activeBlockIndex = next?.$1;
      _activeChunks = next?.$2 ?? const [];
    });
  }

  /// If the view was sitting at fit-width, stay at fit-width for the new
  /// viewport (keeping roughly the same vertical position). If the user had
  /// zoomed to something else, keep their zoom and just re-clamp.
  void _refitAfterResize(double? previousFit, double newFit, Size viewport) {
    final tc = widget.zoomController;
    final content = _contentSize;
    if (tc == null || content == null) return;
    final current = tc.value;
    final scale = current.getMaxScaleOnAxis();
    Matrix4 next = current;
    if (previousFit != null && (scale - previousFit).abs() < 0.001) {
      next = Matrix4.identity()..scale(newFit);
      next.storage[13] = current.storage[13] * (newFit / scale);
    }
    tc.value = _ZoomableCanvas.clampCanvasMatrix(
      next,
      viewport: viewport,
      content: content,
    );
  }

  /// Strategy-B caret follow. Under Strategy A the outer ListView owns the
  /// viewport and PagedEditor scrolls it; under B the zoomable canvas owns
  /// it — the follow lives here, one bounded transform write per caret move.
  void _scheduleFollow() {
    if (_followScheduled) return;
    _followScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _followScheduled = false;
      _followCaretIntoView();
    });
  }

  void _followCaretIntoView() {
    if (!mounted) return;
    if (widget.drawingEnabled) return;
    final tc = widget.zoomController;
    final viewport = _viewportSize;
    final contentSize = _contentSize;
    if (tc == null || viewport == null || contentSize == null) return;
    final driver = _driver;
    if (driver == null) return;
    final rects = driver.editorState.selectionRects();
    if (rects.isEmpty) return;
    final caretRect = rects.last;

    final box = _canvasKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final viewportRect = box.localToGlobal(Offset.zero) & box.size;

    final delta = followScrollDelta(
      caretRect: caretRect,
      viewportRect: viewportRect,
    );
    if (delta == null) return;
    final moved =
        Matrix4.identity()
          ..translate(0.0, -delta)
          ..multiply(tc.value);
    tc.value = _ZoomableCanvas.clampCanvasMatrix(
      moved,
      viewport: viewport,
      content: contentSize,
    );
  }

  void _dismiss() {
    if (_activeBlockIndex == null) return;
    setState(() {
      _activeBlockIndex = null;
      _activeChunks = const [];
    });
  }

  @override
  Widget build(BuildContext context) {
    if (kUseSingleDocumentPagination) {
      final doc = widget.controller.documentJson;
      final children = (doc['children'] as List?) ?? const [];

      // Count CONTIGUOUS RUNS, not unique pageIds. PageBlockComponent stacks
      // one _PageSheet per contiguous run of same-pageId blocks (see
      // groupRunsByPageId in page_block_component.dart) — so an interleaved
      // pattern like `main, main, p1, p1, main, main` (a block pushed forward
      // by overflow, then more content typed at the original page's tail)
      // produces 3 SHEETS from 2 UNIQUE ids. Counting ids understated
      // totalHeight by exactly one sheet's worth and overflowed the outer
      // Column by ~1014px. Mirroring the run-grouping here keeps the two
      // measurements in exact agreement — no cross-file coupling to
      // groupRunsByPageId's internal shape, just the same counting rule.
      final runCount = _countPageRuns(children);
      final pageCount = math.max(1, runCount);
      final sheetHeight = kDocSheetWidth / kPageAspectRatio;
      final totalHeight = pageCount * (sheetHeight + kSheetVerticalMargin * 2);
      _contentSize = Size(kDocSheetWidth, totalHeight);

      final editorContent = SizedBox(
        width: kDocSheetWidth,
        height: totalHeight,
        child: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedBuilder(
              animation: widget.controller,
              // No AbsorbPointer here: under Strategy B the ink layers live
              // INSIDE the editor (one per sheet), so absorbing at this level
              // also blocks the strokes. Each _PageSheet already absorbs
              // pointers on its own text layer while drawing.
              builder:
                  (context, _) => widget.controller.driver.buildEditor(context),
            ),
          ],
        ),
      );

      return LayoutBuilder(
        builder: (context, viewport) {
          if (!viewport.hasBoundedHeight || !viewport.maxHeight.isFinite) {
            return Center(
              child: FittedBox(
                fit: BoxFit.fitWidth,
                alignment: Alignment.topCenter,
                clipBehavior: Clip.none,
                child: editorContent,
              ),
            );
          }

          final size = Size(viewport.maxWidth, viewport.maxHeight);
          final fitWidthScale = viewport.maxWidth / kDocSheetWidth;
          final fitHeightScale = viewport.maxHeight / totalHeight;
          final minScale = math.min(fitHeightScale, fitWidthScale);
          final maxScale = fitWidthScale * 5.0;

          if (_lastReportedSize != size || _lastReportedFitW != fitWidthScale) {
            final previousFit = _lastReportedFitW;
            _lastReportedSize = size;
            _lastReportedFitW = fitWidthScale;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              widget.onViewportChanged?.call(
                fitWidthScale,
                fitHeightScale,
                size,
              );
              _refitAfterResize(previousFit, fitWidthScale, size);
            });
          }

          final tc = widget.zoomController;
          if (tc != null && !_initialTransformSet) {
            _initialTransformSet = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              tc.value = Matrix4.identity()..scale(fitWidthScale);
            });
          }

          if (tc == null) {
            return Center(
              child: FittedBox(
                fit: BoxFit.fitWidth,
                alignment: Alignment.topCenter,
                clipBehavior: Clip.none,
                child: editorContent,
              ),
            );
          }

          _viewportSize = size;
          return _ZoomableCanvas(
            key: _canvasKey,
            controller: tc,
            viewportSize: size,
            contentSize: Size(kDocSheetWidth, totalHeight),
            minScale: minScale,
            maxScale: maxScale,
            child: editorContent,
          );
        },
      );
    }
    return Center(
      child: AspectRatio(
        aspectRatio: widget.aspectRatio,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: context.cerebrum.surface.raised,
            borderRadius: BorderRadius.circular(4),
            boxShadow: [
              BoxShadow(
                color: context.cerebrum.editor.pageShadow,
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: FittedBox(
              alignment: Alignment.topLeft,
              clipBehavior: Clip.none,
              child: SizedBox(
                width: kDocSheetWidth,
                height: kDocSheetWidth / widget.aspectRatio,
                child: AnimatedBuilder(
                  animation: widget.controller,
                  builder: (context, _) {
                    return Stack(
                      key: _stackKey,
                      children: [
                        PagedTableBounds(
                          sheetKey: _stackKey,
                          child: AbsorbPointer(
                            absorbing: widget.drawingEnabled,
                            child: widget.controller.driver.buildEditor(
                              context,
                            ),
                          ),
                        ),
                        IgnorePointer(
                          ignoring: !widget.drawingEnabled,
                          child: NoteDrawingLayer(
                            notifier: widget.controller.drawingNotifier,
                            partialEraser: widget.partialEraser,
                            eraserWidth: widget.eraserWidth,
                          ),
                        ),
                        if (widget.pageNumber != null)
                          Positioned(
                            right: 8,
                            bottom: 6,
                            child: IgnorePointer(
                              child: Text(
                                '${widget.pageNumber}',
                                style: TextStyle(
                                  color: context.cerebrum.text.disabled,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ),
                        ..._analysisOverlay(),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Mirror of `groupRunsByPageId`'s counting logic on the JSON side.
  ///
  /// A "run" is a maximal contiguous block of top-level children sharing the
  /// same `data.pageId`. The outer Column in PageBlockComponent stacks one
  /// _PageSheet per run — so this is the unit its natural height is measured
  /// in, and the unit totalHeight in build() must be computed in.
  ///
  /// Missing `pageId` falls back to 'main', matching stampPageIds' default
  /// before it has run on a freshly-inserted block.
  int _countPageRuns(List<dynamic> children) {
    var runs = 0;
    String? prev;
    for (final c in children) {
      final id = ((c as Map?)?['data'] as Map?)?['pageId'] as String? ?? 'main';
      if (id != prev) {
        runs++;
        prev = id;
      }
    }
    return runs;
  }

  List<Widget> _analysisOverlay() {
    final idx = _activeBlockIndex;
    if (idx == null || widget.drawingEnabled || _driver == null) {
      return const [];
    }
    final inAnalysis = _driver!.vimMode.isAnalysis;
    final chunks = _activeChunks;
    final coveredIds = <String>{
      for (final chunk in chunks)
        for (final id
            in (chunk['blockIds'] as List?)?.cast<String>() ?? const [])
          id,
    };
    Rect? sectionRect;
    var staleCount = 0;
    if (inAnalysis) {
      sectionRect = _chunkGroupRect(chunks);
      staleCount = _countMissingOnPage(coveredIds);
    } else {
      final walk = _sectionWalk(idx);
      sectionRect = walk.$1;
      final walkedIds = walk.$2;
      staleCount = _countMissingOnPage(coveredIds);
      if (coveredIds.isNotEmpty) {
        staleCount += walkedIds.where((id) => !coveredIds.contains(id)).length;
      }
    }
    if (sectionRect == null) return const [];
    final stackBox = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (stackBox == null) return const [];
    final localTopLeft = stackBox.globalToLocal(sectionRect.topLeft);
    final localBottomRight = stackBox.globalToLocal(sectionRect.bottomRight);
    const double leftInset = kBaseHorizontalPadding;
    const double contentWidth = kDocSheetWidth - (2 * kBaseHorizontalPadding);
    final blockRect = Rect.fromLTWH(
      leftInset,
      localTopLeft.dy,
      contentWidth,
      (localBottomRight.dy - localTopLeft.dy).clamp(1.0, double.infinity),
    );
    final pageSize = stackBox.size;
    const gap = 6.0;
    const estPopoverHeight = 220.0;
    final belowSpace = pageSize.height - blockRect.bottom;
    final placeBelow =
        belowSpace >= estPopoverHeight || belowSpace >= blockRect.top;
    final popoverWidth = blockRect.width;
    final left = blockRect.left;
    final top =
        placeBelow
            ? (blockRect.bottom + gap)
            : (blockRect.top - gap - estPopoverHeight).clamp(
              0.0,
              double.infinity,
            );
    final stale = staleCount > 0;
    return [
      Positioned.fromRect(
        rect: blockRect,
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color:
                  stale
                      ? context.cerebrum.editor.staleTint
                      : context.cerebrum.editor.analysisTint,
              border: Border.all(
                color: (stale
                        ? context.cerebrum.editor.unsavedBadge
                        : context.cerebrum.editor.analysisBadge)
                    .withValues(alpha: 0.75),
                width: stale ? 1.6 : 1.2,
              ),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
      ),
      Positioned(
        left: left,
        top: top,
        width: popoverWidth,
        child: _AnalysisPopover(
          chunks: chunks,
          maxHeight: estPopoverHeight,
          onClose: _dismiss,
          staleCount: staleCount,
        ),
      ),
    ];
  }

  Rect? _chunkGroupRect(List<Map<String, dynamic>> chunks) {
    final driver = _driver;
    if (driver == null) return null;
    final blocks =
        (widget.controller.documentJson['children'] as List?) ?? const [];
    final ids = <String>{
      for (final chunk in chunks)
        for (final id
            in (chunk['blockIds'] as List?)?.cast<String>() ?? const [])
          id,
    };
    if (ids.isEmpty) return null;
    Rect? result;
    for (var i = 0; i < blocks.length; i++) {
      final id = (blocks[i] as Map?)?['id']?.toString();
      if (id == null || !ids.contains(id)) continue;
      final rect = driver.rectOfBlock(i);
      if (rect == null) continue;
      result = result == null ? rect : result.expandToInclude(rect);
    }
    return result;
  }

  int _countMissingOnPage(Set<String> ids) {
    if (ids.isEmpty) return 0;
    final present = <String>{
      for (final b
          in (widget.controller.documentJson['children'] as List?) ?? const [])
        if ((b as Map?)?['id']?.toString() case final String id) id,
    };
    return ids.where((id) => !present.contains(id)).length;
  }

  (Rect?, List<String>) _sectionWalk(int startIdx) {
    final driver = _driver;
    if (driver == null) return (null, const []);
    final blocks =
        (widget.controller.documentJson['children'] as List?) ?? const [];
    Rect? result;
    final ids = <String>[];
    for (var i = startIdx; i < blocks.length; i++) {
      if (i > startIdx) {
        final type = (blocks[i] as Map?)?['type']?.toString() ?? '';
        if (type == 'heading') break;
      }
      final id = (blocks[i] as Map?)?['id']?.toString();
      if (id != null) ids.add(id);
      final rect = driver.rectOfBlock(i);
      if (rect == null) continue;
      result = result == null ? rect : result.expandToInclude(rect);
    }
    return (result, ids);
  }
}

/// Custom zoomable/scrollable canvas.
///
/// Why not `InteractiveViewer`: InteractiveViewer's internal scroll handling
/// runs deeper than any wrapper we can put above it, so `PointerSignalResolver`
/// always hands it the pan — Ctrl+wheel would pan like a plain wheel. This
/// canvas owns the scroll handler directly so Ctrl+wheel → zoom.
class _ZoomableCanvas extends StatelessWidget {
  const _ZoomableCanvas({
    super.key,
    required this.controller,
    required this.viewportSize,
    required this.contentSize,
    required this.minScale,
    required this.maxScale,
    required this.child,
  });

  final TransformationController controller;
  final Size viewportSize;

  /// Document size in document units (pre-transform). The pan/zoom clamp
  /// uses it to keep the content covering the viewport — walking the
  /// Unclamped matrix far enough scrolled the sheets out from under the
  /// cursor, and the wheel died with the clipped-away page.
  final Size contentSize;
  final double minScale;
  final double maxScale;
  final Widget child;

  static const double _zoomScrollSensitivity = 0.0015;

  /// Clamp [m] so the content stays covering the viewport along each axis
  /// (content larger than the viewport), or slides within it (smaller —
  /// e.g. ctrl-wheel-zooming way out). Applied everywhere the matrix is
  /// written, so no code path can park the paper off-screen.
  static Matrix4 clampCanvasMatrix(
    Matrix4 m, {
    required Size viewport,
    required Size content,
  }) {
    final scale = m.getMaxScaleOnAxis();
    final store = List<double>.from(m.storage);
    store[12] = _clampAxis(
      store[12],
      content.width * scale,
      viewport.width,
      centerWhenSmaller: true,
    );
    store[13] = _clampAxis(store[13], content.height * scale, viewport.height);
    return Matrix4.fromList(store);
  }

  static double _clampAxis(
    double t,
    double span,
    double viewport, {
    bool centerWhenSmaller = false,
  }) {
    if (span >= viewport) {
      return t.clamp(viewport - span, 0.0);
    }
    if (centerWhenSmaller) return (viewport - span) / 2;
    return t.clamp(0.0, viewport - span);
  }

  static Matrix4 _clampedPan(
    Offset delta,
    Matrix4 current,
    Size viewport,
    Size content,
  ) {
    final panned =
        Matrix4.identity()
          ..translate(-delta.dx, -delta.dy)
          ..multiply(current);
    return clampCanvasMatrix(panned, viewport: viewport, content: content);
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final hk = HardwareKeyboard.instance;
    final ctrl = hk.isControlPressed || hk.isMetaPressed;

    GestureBinding.instance.pointerSignalResolver.register(event, (e) {
      final scroll = e as PointerScrollEvent;
      if (ctrl) {
        _zoomCentered(scroll.scrollDelta.dy);
      } else {
        _panBy(scroll.scrollDelta);
      }
    });
  }

  void _onPointerPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    _panBy(event.panDelta);
  }

  void _zoomCentered(double scrollDeltaDy) {
    final factor = math.exp(-scrollDeltaDy * _zoomScrollSensitivity);
    _zoomAroundPoint(viewportSize.center(Offset.zero), factor);
  }

  void _panBy(Offset delta) {
    controller.value = _clampedPan(
      delta,
      controller.value,
      viewportSize,
      contentSize,
    );
  }

  void _zoomAroundPoint(Offset focal, double factor) {
    final current = controller.value;
    final currentScale = current.getMaxScaleOnAxis();
    final target = (currentScale * factor).clamp(minScale, maxScale);
    if ((target - currentScale).abs() < 0.0001) return;
    final f = target / currentScale;
    final zoomed =
        Matrix4.identity()
          ..translate(focal.dx, focal.dy)
          ..multiply(Matrix4.identity()..scale(f))
          ..multiply(Matrix4.identity()..translate(-focal.dx, -focal.dy))
          ..multiply(current);
    controller.value = clampCanvasMatrix(
      zoomed,
      viewport: viewportSize,
      content: contentSize,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerSignal: _onPointerSignal,
      onPointerPanZoomUpdate: _onPointerPanZoomUpdate,
      child: ClipRect(
        // The Stack reports viewport size to its parent (so pointer events
        // inside the viewport reach us). Positioned gives its child TIGHT
        // document-size constraints regardless of the viewport, which a plain
        // SizedBox can't do under a tight parent (it was being forced to
        // viewport size, squeezing the editor into ~612px and overflowing the
        // sheet Column). Transform doesn't bounds-check hit tests, so taps map
        // through the matrix into the full document.
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              top: 0,
              width: contentSize.width,
              height: contentSize.height,
              child: AnimatedBuilder(
                animation: controller,
                builder: (context, child) {
                  return Transform(
                    transform: clampCanvasMatrix(
                      controller.value,
                      viewport: viewportSize,
                      content: contentSize,
                    ),
                    alignment: Alignment.topLeft,
                    child: child,
                  );
                },
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnalysisPopover extends StatelessWidget {
  const _AnalysisPopover({
    required this.chunks,
    required this.maxHeight,
    required this.onClose,
    this.staleCount = 0,
  });

  final List<Map<String, dynamic>> chunks;
  final double maxHeight;
  final VoidCallback onClose;
  final int staleCount;

  static Color _severityColor(BuildContext context, String severity) {
    final status = context.cerebrum.status;
    switch (severity.toLowerCase()) {
      case 'high':
      case 'critical':
        return status.danger;
      case 'medium':
      case 'moderate':
        return status.warning;
      case 'low':
      case 'minor':
        return status.warning;
      default:
        return status.neutral;
    }
  }

  @override
  Widget build(BuildContext context) {
    final findings = <Map<String, dynamic>>[
      for (final chunk in chunks)
        for (final f in (chunk['findings'] as List? ?? const []))
          if (f is Map<String, dynamic>) f,
    ];

    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(6),
      color: context.cerebrum.surface.cardSurfaceSelected,
      shadowColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 8, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (staleCount > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 14,
                        color: context.cerebrum.editor.staleBadge,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          staleCount == 1
                              ? '1 referenced block no longer matches the note — '
                                  'this analysis may be out of date.'
                              : '$staleCount referenced blocks no longer match the '
                                  'note — this analysis may be out of date.',
                          style: TextStyle(
                            fontSize: 11,
                            color: context.cerebrum.editor.staleBadge,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const Divider(height: 12),
              if (findings.isEmpty)
                const Text(
                  'This block is covered by analysis, but has no specific findings.',
                  style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: findings.length,
                    separatorBuilder: (_, __) => const Divider(height: 12),
                    itemBuilder: (context, i) => _finding(context, findings[i]),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _finding(BuildContext context, Map<String, dynamic> finding) {
    final severity = (finding['severity'] ?? 'unknown').toString();
    final type = (finding['type'] ?? 'finding').toString().replaceAll('_', ' ');
    final gap = finding['gap_explanation'] as String?;
    final claim = finding['student_claim'] as String?;
    final detail = gap ?? claim;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 5,
              backgroundColor: _severityColor(context, severity),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                type,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              severity.toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                color: _severityColor(context, severity),
              ),
            ),
          ],
        ),
        if (detail != null) ...[
          const SizedBox(height: 3),
          Text(detail, style: const TextStyle(fontSize: 12)),
        ],
      ],
    );
  }
}
