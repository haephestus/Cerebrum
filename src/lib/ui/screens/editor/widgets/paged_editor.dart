import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:cerebrum/ui/screens/editor/controllers/appflowy_text_driver.dart';
import 'package:cerebrum/ui/screens/editor/controllers/paged_note_controller.dart';
import 'package:cerebrum/ui/screens/editor/widgets/page_surface.dart';

/// Looks up the analysis chunks (if any) covering the block with id [blockId] on
/// the page with id [pageId]. Null/empty means that block has no analysis.
/// Supplied by EditorScaffold while the analysis panel is open; drives
/// PageSurface's inline per-block analysis popover. Keyed by STABLE block id
/// (not position) so the mapping survives edits/reorders.
typedef BlockAnalysisLookup =
    List<Map<String, dynamic>>? Function(String pageId, String blockId);

/// Renders a note's pages as either a **vertical** continuous scroll (default,
/// document feel) or a **horizontal** PageView (slideshow), switchable at
/// runtime via [PagedNoteController.layout]. Both iterate the same [PageSurface],
/// so the layout is just a scroll-widget choice. A trailing "add page" tile
/// appends a blank page.
///
/// UNVERIFIED (no flutter tooling here) — run `flutter analyze`.
class PagedEditor extends StatefulWidget {
  const PagedEditor({
    super.key,
    required this.controller,
    this.analysisForBlock,
    this.partialEraser,
    this.eraserWidth,
  });

  final PagedNoteController controller;

  /// When non-null, each page shows an inline analysis popover for blocks this
  /// resolves to findings for (analysis-review mode). Null → no popovers.
  final BlockAnalysisLookup? analysisForBlock;

  /// Eraser mode (partial vs whole-stroke), forwarded to each page's ink layer.
  final ValueNotifier<bool>? partialEraser;

  /// Eraser diameter (logical px), forwarded to each page's ink layer.
  final ValueListenable<double>? eraserWidth;

  @override
  State<PagedEditor> createState() => _PagedEditorState();
}

class _PagedEditorState extends State<PagedEditor> {
  final PageController _pageViewController = PageController();

  /// Scroll controller for the VERTICAL layout only. The horizontal PageView
  /// keeps using [PageController] (page-snapping semantics differ).
  ///
  /// This is what lets the caret be scrolled back into view. The drivers
  /// deliberately set `disableAutoScroll: true` — AppFlowy's own
  /// scroll-into-view chases the caret by scrolling the nearest Scrollable,
  /// which here is THIS list, and that produced the view lurching to the
  /// previous page after a backspace-merge. Doing it here instead means we
  /// own the decision: we know which page owns the caret and we only move
  /// when that page is genuinely off-screen.
  final ScrollController _verticalScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // One listener per page driver: the caret moving onto a DIFFERENT page is
    // the only signal that can require scrolling the outer list. A caret move
    // within the page that already owns it is handled inside that page (and is
    // a no-op for us — that page is by definition on screen).
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

  /// Each page driver we're listening to, with the closure we registered.
  /// Storing the closure is what lets dispose/removeListener actually detach —
  /// `addListener(() => ...)` creates a fresh closure each call, so a
  /// tear-down that only had the driver reference could never remove it, and
  /// every page rebuild would stack up another live listener on a dead driver.
  final Map<AppFlowyTextDriver, VoidCallback> _listening = {};

  void _attachSelectionListeners() {
    final pages = widget.controller.pages;
    for (final page in pages) {
      final d = page.controller.driver;
      if (d is! AppFlowyTextDriver) continue;
      if (_listening.containsKey(d)) continue;
      late final VoidCallback cb;
      // Resolve the page's CURRENT index at fire time, never capture it. A
      // captured index goes stale the moment pages shift: PagedNoteController
      // does `_pages.removeAt(index)` when a page empties out, which slides
      // every later page down one. `_syncSelectionListeners` is attach-only, so
      // those drivers keep their existing (now wrong) closure and the caret on
      // real page 3 would scroll real page 4.
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

  /// Pages are added/removed/rebuilt by the controller (overflow flow, merge,
  /// add page), so re-sync the listener set whenever it notifies. Attach-only:
  /// existing listeners stay put, and any driver no longer in the list is
  /// detached. Tearing everything down and rebuilding each time would work too
  /// but churns listener registrations on a notifier that fires constantly.
  void _syncSelectionListeners() {
    final live = <AppFlowyTextDriver>{};
    for (final page in widget.controller.pages) {
      final d = page.controller.driver;
      if (d is AppFlowyTextDriver) live.add(d);
    }
    // Drop anchors for pages that no longer exist. Deleting a page leaves the
    // index-keyed GlobalKey behind forever; it is never re-looked-up (the live
    // index is always < pages.length) but it keeps the key — and the element it
    // points at — alive for the lifetime of the editor.
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
        final itemCount = pages.length + 1; // + trailing "add page" tile

        Widget itemAt(int i) {
          if (i == pages.length) {
            return _AddPageTile(onAdd: c.addPage);
          }
          return Padding(
            // Anchor for caret-follow (see _followCaretToPage): this page's
            // wrapper is what we measure to decide whether the page the caret
            // moved onto is already on screen.
            key: _anchorFor(i),
            padding: const EdgeInsets.all(12),
            // Touching a page makes it the ACTIVE page. In vertical scroll mode
            // nothing else tracks which page you're on, and the single
            // screen-level drawing dial drives the active page's notifier — so
            // without this, drawing / undo / redo would target the wrong page.
            // A passive Listener observes pointer-down without entering the
            // gesture arena, so it doesn't interfere with drawing or text input.
            child: Listener(
              behavior: HitTestBehavior.deferToChild,
              onPointerDown: (_) => c.setActive(i),
              // Key by controller identity: pages keep the same element across
              // normal rebuilds (preserving editor/scroll state), but a page
              // whose controller was REPLACED — the backspace-merge seam, or the
              // two pages an overflow flow rebuilds — gets a new key and
              // remounts, so the focus request that page's `autoFocus` made at
              // construction (see PagedNoteController._makePage) lands on the
              // fresh editor and the caret shows where it was seeded. This
              // remount is the whole mechanism behind cross-page focus/caret
              // hand-off; it's also why those paths must seed the caret onto
              // exactly one page (see PagedNoteController.pushOverflow).
              child: PageSurface(
                key: ObjectKey(pages[i].controller),
                controller: pages[i].controller,
                drawingEnabled: c.drawingEnabled,
                pageNumber: i + 1,
                pageId: pages[i].pageId,
                analysisForBlock: widget.analysisForBlock,
                partialEraser: widget.partialEraser,
                eraserWidth: widget.eraserWidth,
                // When this page's content spills past the sheet, move the
                // overflowing tail (from block `fromIndex`) onto the next page.
                // A table reports a measured height budget so the controller
                // can split it at a row boundary (see PagedNoteController).
                onOverflow:
                    (fromIndex, {tableAvailableHeight}) => c.pushOverflow(
                      i,
                      fromIndex,
                      tableAvailableHeight: tableAvailableHeight,
                    ),
              ),
            ),
          );
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

  /// Suppresses caret-follow while the USER is scrolling the page list.
  ///
  /// Without this, a scroll gesture and a caret-follow both drive the same
  /// controller: the caret-follow fires mid-drag and yanks the list back to
  /// the caret, so the user's own scroll fights an animation and the list
  /// snaps. Set on ScrollStart with a drag (user-initiated) and cleared on
  /// ScrollEnd. Programmatic scrolls report no `dragDetails`, so a
  /// caret-follow never disables itself.
  bool _userScrolling = false;

  bool _onScrollNotification(ScrollNotification n) {
    if (n is ScrollStartNotification && n.dragDetails != null) {
      _userScrolling = true;
    } else if (n is ScrollEndNotification) {
      _userScrolling = false;
    }
    // Never consume: the list must keep scrolling normally.
    return false;
  }

  /// Scrolls [pageIndex] into view when the caret moves onto a page that isn't
  /// already showing.
  ///
  /// The driver-level alternative is deliberately off: every page's editor sets
  /// `disableAutoScroll: true`, because AppFlowy's own scroll-into-view chases
  /// the caret by scrolling the NEAREST Scrollable — which here is this outer
  /// list, not the page — and that is what made the view lurch to the previous
  /// page after a backspace-merge. Owning it here means we scroll only when we
  /// can prove the caret's page is off-screen, and only in the vertical layout
  /// (the horizontal PageView follows the caret via its own controller).
  ///
  /// Coalesced to one check per frame: a caret move, a transaction rebuild and
  /// an overflow flow can land in the same frame, and each would otherwise
  /// start its own animation and fight for the controller.
  void _followCaretToPage(int pageIndex) {
    if (!mounted || _followScheduled) return;
    _followScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _followScheduled = false;
      if (!mounted) return;
      // A user drag owns the list until they lift off.
      if (_userScrolling) return;
      if (widget.controller.layout != PageLayoutMode.vertical) return;
      if (!_verticalScrollController.hasClients) return;

      final pages = widget.controller.pages;
      // -1 means the driver's page was deleted between the caret moving and
      // this frame; nothing to follow.
      if (!isFollowTargetValid(pageIndex, pages.length)) return;
      final driver = pages[pageIndex].controller.driver;
      if (driver is! AppFlowyTextDriver) return;

      // The CARET's rect, in global coordinates — not the page's.
      //
      // `EditorState.selectionRects()` is already global (verified against a
      // real laid-out editor: caret at x=413 with the editor's origin at x=250),
      // so it must NOT be offset again by the page's position. Doing that is
      // what made the list fly to `maxScrollExtent`.
      final rects = driver.editorState.selectionRects();
      if (rects.isEmpty) return; // no selection, or the page isn't laid out
      // Last rect is the caret end of the selection.
      final caretRect = rects.last;

      // Where the viewport currently shows.
      final listBox = _verticalScrollController.position.context.notificationContext
          ?.findRenderObject();
      if (listBox is! RenderBox || !listBox.hasSize) return;
      final viewportRect = listBox.localToGlobal(Offset.zero) & listBox.size;

      final delta = followScrollDelta(
        caretRect: caretRect,
        viewportRect: viewportRect,
      );
      if (delta == null) return; // caret already comfortably visible
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

  /// Ignore sub-pixel/rounding differences so a settled page doesn't keep
  /// re-triggering a follow.
  static const double _followTolerance = 8.0;

  bool _followScheduled = false;

  /// Anchor GlobalKeys, one per page index, attached to each page's wrapper so
  /// its on-screen rect can be measured. Rebuilt each frame from the page list
  /// so indices stay aligned with `pages` (an overflow flow can replace the
  /// controller at an index; the key is looked up fresh each time, so it keeps
  /// tracking whatever page now lives there).
  final Map<int, GlobalKey> _pageAnchors = {};

  GlobalKey _anchorFor(int index) =>
      _pageAnchors.putIfAbsent(index, () => GlobalKey(debugLabel: 'page$index'));
}

/// Whether [pageIndex] names a page that still exists, given [pageCount].
///
/// Split out because the bound is load-bearing and easy to get subtly wrong: a
/// caret move on a deleted page resolves to -1, and `-1 >= 0` is false but
/// `(-1).clamp(0, pageCount - 1)` is 0 — clamping turns "this page is gone"
/// into "scroll to the first page".
bool isFollowTargetValid(int pageIndex, int pageCount) =>
    pageIndex >= 0 && pageIndex < pageCount;

/// How far the page list must scroll to bring the CARET into view, or null when
/// the caret is already comfortably inside the viewport.
///
/// This measures the CARET, not the page. That distinction is the whole feature:
/// a page is frequently taller than the viewport, so "scroll the page into view"
/// cannot be satisfied by any offset and degenerates into either a no-op or a
/// jump to `maxScrollExtent`. Only the caret has a position small enough to
/// bring into view.
///
/// * Caret fully inside the [margin] band → null. This is what stops a follow
///   firing on every caret tick while typing: the caret is already visible, so
///   the list must not move.
/// * Caret below the band → scroll down just enough to raise it to the band's
///   bottom edge. Never align the page's top: on a tall page that overshoots by
///   the whole overflow and reads as a lurch.
/// * Caret above the band → the symmetric upward move.
///
/// [tolerance] absorbs sub-pixel rounding so a settled caret doesn't re-trigger.
double? followScrollDelta({
  required Rect caretRect,
  required Rect viewportRect,
  double margin = 48.0,
  double tolerance = 2.0,
}) {
  // A caret rect of zero size means the editor hasn't laid the line out yet
  // (or the page isn't built). Following on that would scroll somewhere blind.
  if (caretRect.height <= 0 || caretRect.width <= 0) return null;
  if (viewportRect.height <= 0) return null;

  // The band must leave room for the CARET itself, not just fit inside the
  // viewport. Clamping only against height/2 is not enough: on a 60px viewport
  // with a 24px caret, band = 30 makes topEdge == bottomEdge == 30, leaving 6px
  // of usable space — no caret can ever be "inside" the band, so the follow
  // fires on every tick and walks the list to maxScrollExtent.
  final slack = viewportRect.height - caretRect.height;
  final band = margin <= 0 || slack <= 0
      ? 0.0
      : margin.clamp(0.0, slack / 2).toDouble();
  final topEdge = viewportRect.top + band;
  final bottomEdge = viewportRect.bottom - band;

  // Below the band: raise it to bottomEdge.
  if (caretRect.bottom > bottomEdge + tolerance) {
    return caretRect.bottom - bottomEdge;
  }
  // Above the band: drop it to topEdge.
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
