import 'package:cerebrum/ui/screens/editor/helpers/flow_executor.dart'
    show kUseSingleDocumentPagination;
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:cerebrum/ui/screens/editor/controllers/appflowy_text_driver.dart';
import 'package:cerebrum/ui/screens/editor/controllers/paged_note_controller.dart';
import 'package:cerebrum/ui/screens/editor/widgets/page_surface.dart';

typedef BlockAnalysisLookup =
    List<Map<String, dynamic>>? Function(String pageId, String blockId);

class PagedEditor extends StatefulWidget {
  const PagedEditor({
    super.key,
    required this.controller,
    this.analysisForBlock,
    this.partialEraser,
    this.eraserWidth,
    this.zoomController,
    this.onViewportChanged,
  });

  final PagedNoteController controller;
  final BlockAnalysisLookup? analysisForBlock;
  final ValueNotifier<bool>? partialEraser;
  final ValueListenable<double>? eraserWidth;
  final TransformationController? zoomController;
  final void Function(double fitWidth, double fitHeight, Size viewport)?
  onViewportChanged;

  @override
  State<PagedEditor> createState() => _PagedEditorState();
}

class _PagedEditorState extends State<PagedEditor> {
  final PageController _pageViewController = PageController();
  final ScrollController _verticalScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _attachSelectionListeners();
    widget.controller.addListener(_syncSelectionListeners);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncSelectionListeners);
    _detachSelectionListeners();
    _pageViewController.dispose();
    _verticalScrollController.dispose();
    super.dispose();
  }

  final Map<AppFlowyTextDriver, VoidCallback> _listening = {};

  void _attachSelectionListeners() {
    final pages = widget.controller.pages;
    for (final page in pages) {
      final d = page.controller.driver;
      if (d is! AppFlowyTextDriver) continue;
      if (_listening.containsKey(d)) continue;
      late final VoidCallback cb;
      cb = () => _followCaretToPage(_indexOfDriver(d));
      _listening[d] = cb;
      d.selectionChanges.addListener(cb);
    }
  }

  int _indexOfDriver(AppFlowyTextDriver driver) {
    final pages = widget.controller.pages;
    for (var i = 0; i < pages.length; i++) {
      if (identical(pages[i].controller.driver, driver)) return i;
    }
    return -1;
  }

  void _detachSelectionListeners() {
    for (final entry in _listening.entries) {
      entry.key.selectionChanges.removeListener(entry.value);
    }
    _listening.clear();
  }

  void _syncSelectionListeners() {
    final live = <AppFlowyTextDriver>{};
    for (final page in widget.controller.pages) {
      final d = page.controller.driver;
      if (d is AppFlowyTextDriver) live.add(d);
    }
    final pageCount = widget.controller.pages.length;
    _pageAnchors.removeWhere((index, _) => index >= pageCount);
    for (final d in _listening.keys.toList()) {
      if (!live.contains(d)) {
        d.selectionChanges.removeListener(_listening[d]!);
        _listening.remove(d);
      }
    }
    _attachSelectionListeners();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final c = widget.controller;
        final pages = c.pages;
        final itemCount =
            kUseSingleDocumentPagination ? pages.length : pages.length + 1;

        Widget itemAt(int i) {
          if (i == pages.length) {
            return _AddPageTile(onAdd: c.addPage);
          }
          return Padding(
            key: _anchorFor(i),
            padding: const EdgeInsets.all(12),
            child: Listener(
              behavior: HitTestBehavior.deferToChild,
              onPointerDown: (_) => c.setActive(i),
              child: PageSurface(
                key: ObjectKey(pages[i].controller),
                controller: pages[i].controller,
                drawingEnabled: c.drawingEnabled,
                pageNumber: i + 1,
                pageId: pages[i].pageId,
                analysisForBlock:
                    kUseSingleDocumentPagination
                        ? null
                        : widget.analysisForBlock,
                partialEraser: widget.partialEraser,
                eraserWidth: widget.eraserWidth,
                zoomController: widget.zoomController,
                onViewportChanged: widget.onViewportChanged,
                onOverflow:
                    kUseSingleDocumentPagination
                        ? null
                        : (fromIndex, {tableAvailableHeight}) => c.pushOverflow(
                          i,
                          fromIndex,
                          tableAvailableHeight: tableAvailableHeight,
                        ),
                onUnderfill:
                    kUseSingleDocumentPagination
                        ? null
                        : (freeHeight, headHeight) =>
                            c.onPageMeasured(i, freeHeight, headHeight),
              ),
            ),
          );
        }

        // Strategy B: ONE PageSurface, filling the bounded editor area.
        //
        // No ListView wrapper — SliverList gives its children UNBOUNDED
        // height (`0..Infinity`), which made PageSurface's LayoutBuilder
        // see `viewport.hasBoundedHeight == false` and silently fall back to
        // the static FittedBox (no zoom). That's the "Ctrl+= doesn't zoom"
        // bug: the InteractiveViewer branch was never taken. Bypassing the
        // list gives PageSurface the Scaffold.body constraints directly, so
        // its LayoutBuilder sees `viewport.maxHeight.isFinite == true` and
        // mounts the zoomable canvas.
        //
        // No loss of function: under B there's only one page (`'main'`), so
        // the outer list had itemCount 1 and nothing to scroll. All panning
        // lives inside the zoomable canvas.
        if (kUseSingleDocumentPagination) {
          return itemAt(0);
        }

        if (c.layout == PageLayoutMode.horizontal) {
          return PageView.builder(
            controller: _pageViewController,
            itemCount: itemCount,
            onPageChanged: c.setActive,
            itemBuilder: (context, i) => itemAt(i),
          );
        }
        return NotificationListener<ScrollNotification>(
          onNotification: _onScrollNotification,
          child: ListView.builder(
            controller: _verticalScrollController,
            itemCount: itemCount,
            itemBuilder: (context, i) => itemAt(i),
          ),
        );
      },
    );
  }

  bool _userScrolling = false;

  bool _onScrollNotification(ScrollNotification n) {
    if (n is ScrollStartNotification && n.dragDetails != null) {
      _userScrolling = true;
    } else if (n is ScrollEndNotification) {
      _userScrolling = false;
    }
    return false;
  }

  void _followCaretToPage(int pageIndex) {
    if (!mounted || _followScheduled) return;
    _followScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _followScheduled = false;
      if (!mounted) return;
      if (_userScrolling) return;
      if (widget.controller.layout != PageLayoutMode.vertical) return;
      // Under Strategy B there is no outer ListView — the zoomable canvas
      // owns the viewport, and follow has nothing to scroll. Also true in
      // single-page Strategy A (hasClients false).
      if (!_verticalScrollController.hasClients) return;

      final pages = widget.controller.pages;
      if (!isFollowTargetValid(pageIndex, pages.length)) return;
      final driver = pages[pageIndex].controller.driver;
      if (driver is! AppFlowyTextDriver) return;

      final rects = driver.editorState.selectionRects();
      if (rects.isEmpty) return;
      final caretRect = rects.last;

      final listBox =
          _verticalScrollController.position.context.notificationContext
              ?.findRenderObject();
      if (listBox is! RenderBox || !listBox.hasSize) return;
      final viewportRect = listBox.localToGlobal(Offset.zero) & listBox.size;

      final delta = followScrollDelta(
        caretRect: caretRect,
        viewportRect: viewportRect,
      );
      if (delta == null) return;
      _animateTo(_verticalScrollController.position.pixels + delta);
    });
  }

  void _animateTo(double offset) {
    final pos = _verticalScrollController.position;
    final clamped = offset.clamp(pos.minScrollExtent, pos.maxScrollExtent);
    if ((clamped - pos.pixels).abs() <= _followTolerance) return;
    _verticalScrollController.animateTo(
      clamped,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  static const double _followTolerance = 8.0;
  bool _followScheduled = false;

  final Map<int, GlobalKey> _pageAnchors = {};

  GlobalKey _anchorFor(int index) => _pageAnchors.putIfAbsent(
    index,
    () => GlobalKey(debugLabel: 'page$index'),
  );
}

bool isFollowTargetValid(int pageIndex, int pageCount) =>
    pageIndex >= 0 && pageIndex < pageCount;

double? followScrollDelta({
  required Rect caretRect,
  required Rect viewportRect,
  double margin = 48.0,
  double tolerance = 2.0,
}) {
  if (caretRect.height <= 0 || caretRect.width <= 0) return null;
  if (viewportRect.height <= 0) return null;

  final slack = viewportRect.height - caretRect.height;
  final band =
      margin <= 0 || slack <= 0 ? 0.0 : margin.clamp(0.0, slack / 2).toDouble();
  final topEdge = viewportRect.top + band;
  final bottomEdge = viewportRect.bottom - band;

  if (caretRect.bottom > bottomEdge + tolerance) {
    return caretRect.bottom - bottomEdge;
  }
  if (caretRect.top < topEdge - tolerance) {
    return caretRect.top - topEdge;
  }
  return null;
}

class _AddPageTile extends StatelessWidget {
  const _AddPageTile({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: OutlinedButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add),
          label: const Text('Add page'),
        ),
      ),
    );
  }
}
