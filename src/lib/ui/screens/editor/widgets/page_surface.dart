import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:cerebrum/ui/themes/theme_access.dart';
import 'package:flutter/material.dart';
import 'package:cerebrum/ui/screens/editor/blocks/table/table_page_bounds.dart';
import 'package:cerebrum/ui/screens/editor/controllers/note_editor_controller.dart';
import 'package:cerebrum/ui/screens/editor/controllers/appflowy_text_driver.dart';
import 'package:cerebrum/ui/screens/editor/helpers/flow_executor.dart'
    show kUseSingleDocumentPagination;
import 'package:cerebrum/ui/screens/editor/widgets/drawing_layer.dart';
import 'package:cerebrum/ui/screens/editor/widgets/page_space.dart';
import 'package:cerebrum/ui/screens/editor/widgets/paged_editor.dart'
    show BlockAnalysisLookup;

/// One page of a note: a fixed-aspect "sheet" (A4 portrait) holding the text
/// editor + ink layer, stacked — the paged equivalent of EditorSurface, bounded
/// to a page instead of filling the screen.
///
/// **Fixed document space, fitted view.** The page's content is laid out
/// ONCE, at the canonical size ([kDocSheetWidth] wide, A4 aspect — see
/// page_space.dart), and a [FittedBox] paints it scaled to whatever space the
/// window gives this page. That single transform is the whole scaling story:
/// text, ink, block chrome and popovers are laid out in document units, so the
/// same amount of text occupies the same fraction of a page at any window
/// size, layout mode, or DPI — the FittedBox cannot change layout, only paint.
/// (An earlier attempt scaled font sizes per-widget instead; one clamped or
/// unscaled metric reintroduced spills, and resize/mode-switch frame races
/// against the overflow detector force-created pages.)
///
/// FittedBox applies the inverse transform to hit tests, so pointer positions
/// arriving in the editor and in the ink layer are already in CANONICAL
/// document coordinates — strokes are captured and stored at their document
/// position, independent of the zoom they were drawn at. (Strokes recorded
/// before this change carry whatever sheet-pixel coordinates the capturing
/// window had and are NOT migratable: there is no draw-time width to rescale
/// from.)
///
/// **Why the overflow detection lives HERE, not in the controller.** The
/// controller decides *what* to move on overflow ([PagedNoteController.pushOverflow]),
/// but it can't tell *whether* the page overflows — that's a rendered-layout
/// question, and only the widget can see the layout. So this widget measures each
/// block's rect against the sheet's bottom edge and reports the first
/// block that spills over (via [onOverflow]). The measurement runs in a
/// post-frame callback (a block's rect only exists after layout) and is coalesced
/// to once per frame (typing fires many notifications). Because a rebuild remounts
/// this widget (`ObjectKey(controller)`), the check re-runs on the new page and
/// naturally *cascades* forward until every page fits. All measurements are in
/// document units (rects from the engine arrive global — screen px including
/// the zoom — and are mapped back through the page's box), so a window resize
/// or a zoom change CANNOT disturb them: nothing about the document layout
/// changed.
///
/// **Why the sheet is fixed-height even though content can exceed it.** Keeping
/// the A4 `AspectRatio` is what makes "the page fills → spill forward" meaningful;
/// the alternative (let the sheet grow) isn't a paged model. Overflow beyond the
/// sheet is transient — it's detected and pushed to the next page next frame.
///
/// In analysis-review mode ([analysisForBlock] non-null), the caret landing in a
/// block that has analysis tints the block and shows an inline popover of its
/// findings, anchored to the block. Chunks are looked up by the block's STABLE id
/// (`selectedBlockId`), which round-trips save/load, so the mapping survives
/// edits/reorders; the block index is kept only to position the highlight rect.
///
/// UNVERIFIED (no device run here) — the overflow measurement and the analysis
/// overlay geometry (globalToLocal positioning under the fitted zoom) need a
/// smoke test on a real page.
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
    this.aspectRatio = kPageAspectRatio, // A4 portrait
  });

  final NoteEditorController controller;
  final bool drawingEnabled;

  /// Eraser mode (partial vs whole-stroke), forwarded to this page's ink layer.
  final ValueNotifier<bool>? partialEraser;

  /// Eraser diameter (logical px), forwarded to this page's ink layer.
  final ValueListenable<double>? eraserWidth;

  final int? pageNumber;
  final String? pageId;
  final BlockAnalysisLookup? analysisForBlock;

  /// Called with the index of the first top-level block that spills past the
  /// bottom of the sheet, so the controller can move that block (and everything
  /// after it) onto the next page. Null disables overflow flow.
  ///
  /// For a TABLE block, [tableAvailableHeight] carries the measured vertical
  /// space the table head may occupy (`pageBottom - tableTop`) so the
  /// controller can SPLIT the table at a row boundary instead of moving the
  /// whole block — the piece that keeps a page from becoming scrollable.
  final void Function(int fromBlockIndex, {double? tableAvailableHeight})?
  onOverflow;

  /// Called after EVERY placed-out check in which this page did NOT overflow,
  /// with two locally-measured DOCUMENT-unit numbers that feed the controller's
  /// backward reflow:
  ///  * [freeHeight] — spare space below this page's last block; how much a
  ///    PREVIOUS page could hand up.
  ///  * [headHeight] — this page's own first block's height (what a PREVIOUS
  ///    page would receive if it pulled from here). Null when the first block
  ///    never laid out.
  /// Both sides of the move measure on their own page at the same canonical
  /// width, so heights are directly comparable without cross-page math. Null
  /// disables backward reflow. Reports are silent (never notify): the
  /// controller re-checks on a settle timer instead — see its reflow comment.
  final void Function(double freeHeight, double? headHeight)? onUnderfill;

  final double aspectRatio;

  @override
  State<PageSurface> createState() => _PageSurfaceState();
}

class _PageSurfaceState extends State<PageSurface> {
  // On the Stack so we can convert a block's GLOBAL rect (from the driver) into
  // this page's local coordinates to position the highlight + popover.
  final GlobalKey _stackKey = GlobalKey();

  AppFlowyTextDriver? _driver;
  int? _activeBlockIndex;
  List<Map<String, dynamic>> _activeChunks = const [];

  // Coalesce overflow checks to one per frame (edits fire many notifications).
  bool _overflowCheckScheduled = false;

  @override
  void initState() {
    super.initState();
    final d = widget.controller.driver;
    if (d is AppFlowyTextDriver) {
      _driver = d;
      d.selectionChanges.addListener(_onSelectionChanged);
    }
    // Content changes (typing, paste) can push the last block past the sheet —
    // re-check overflow after the resulting layout settles.
    widget.controller.addListener(_scheduleOverflowCheck);
    _scheduleOverflowCheck(); // also catch content that's already too tall on open
  }

  @override
  void didUpdateWidget(PageSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Panel toggled or lookup swapped: recompute WITHOUT setState (a rebuild is
    // already in flight from the parent).
    if (!identical(widget.analysisForBlock, oldWidget.analysisForBlock)) {
      final next = _resolveActive();
      _activeBlockIndex = next?.$1;
      _activeChunks = next?.$2 ?? const [];
    }
  }

  @override
  void dispose() {
    _driver?.selectionChanges.removeListener(_onSelectionChanged);
    widget.controller.removeListener(_scheduleOverflowCheck);
    super.dispose();
  }

  /// Measure once per frame, after layout, whether this page overflows the
  /// sheet — and if not, publish the fill stats the backward reflow pairs on.
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
    // Document units. The Stack is laid out inside the fitted document space,
    // so its LOCAL size IS the sheet's canonical content bounds — a constant
    // that no window size or layout mode can influence. `rectOfBlock` returns
    // GLOBAL rects (screen px, carrying the fitted zoom), so each block is
    // mapped back through the page's box; because the zoom is a uniform
    // axis-aligned scale, converting top-left and bottom-left pins the
    // document-space height exactly, and the pageBottom comparison is stable
    // across resizes rather than racing the FittedBox against the editor.
    final pageBottomLocal = stackBox.size.height;

    final blocks =
        (widget.controller.documentJson['children'] as List?) ?? const [];
    // A rasterized table taller than the sheet is now split at the row level
    // (via the tableAvailableHeight budget → the controller's splitter), so a
    // TABLE at index 0 is handled too. A NON-table block at index 0 that's
    // taller than the whole sheet can't be divided by this model, so it's left
    // to overflow rather than loop forever.
    const tolerance = 0.5; // document pixels
    // Fill stats gathered in the same pass — no overflow means ONE extra
    // local-vs-local subtraction per pair, all in document units.
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

    // No overflow → publish the fill stats for the backward reflow. An empty
    // document still lays out its filler paragraph, so lastBottom exists
    // whenever there's anything at all; skip the report on a non-laid-out
    // page (no lastBottom = nothing to receive on either side).
    final onUnderfill = widget.onUnderfill;
    if (onUnderfill == null || lastBottomLocal == null) return;
    final free = pageBottomLocal - lastBottomLocal;
    if (free <= 0) return; // full page; nothing to receive happens either way
    onUnderfill(free, headHeight);
  }

  /// The (blockIndex, chunks) the caret currently implies, or null when there's
  /// no analysis to show (not in review mode, no caret, or the block has none).
  (int, List<Map<String, dynamic>>)? _resolveActive() {
    final lookup = widget.analysisForBlock;
    final pageId = widget.pageId;
    final driver = _driver;
    if (lookup == null || pageId == null || driver == null) return null;
    final idx = driver.selectedBlockIndex;
    final blockId = driver.selectedBlockId;
    if (idx == null || blockId == null) return null;
    // Look up by the STABLE block id; keep idx only to draw the highlight rect.
    final chunks = lookup(pageId, blockId);
    if (chunks == null || chunks.isEmpty) return null;
    return (idx, chunks);
  }

  void _onSelectionChanged() {
    final next = _resolveActive();
    // Only rebuild when the highlighted block actually changes — the selection
    // notifier fires on every caret move.
    if (next?.$1 == _activeBlockIndex) return;
    if (!mounted) return;
    setState(() {
      _activeBlockIndex = next?.$1;
      _activeChunks = next?.$2 ?? const [];
    });
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
      // Strategy B: ONE editor per note, paginated by the page block
      // itself (sheets are the paper chrome). This surface is a bare
      // wrapper — the per-sheet pointer absorb + ink live inside the
      // sheets, overlaid on the same document. No onOverflow/onUnderfill
      // measurements here (the driver does its own), no analysis overlay
      // (its geometry anchored to this surface's Stack, which is gone).
      return Center(
      child: AspectRatio(
        // Unbounded heights make appflowy's editor overlay (_Theatre) crash
        // in dry layout — the aspect-ratio'd box is what gave the editor
        // finite constraints in the A branch. NO paper chrome here: no
        // FittedBox, no decoration — the sheets own all of that. This box
        // exists ONLY to hand the editor bounded constraints inside the
        // paged list view's sliver.
        aspectRatio: widget.aspectRatio,
        child: AnimatedBuilder(
          animation: widget.controller,
          builder:
              (context, _) => AbsorbPointer(
                absorbing: widget.drawingEnabled,
                child: widget.controller.driver.buildEditor(context),
              ),
        ),
      ),
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
            // The ASPECT RATIO is set on the on-screen box; the document space
            // has the SAME aspect at its canonical size, so the FittedBox's
            // scale is exactly onScreenWidth/700 both axes — no residual gaps,
            // no letterboxing.
            //
            // FittedBox lays its child out UNCONSTRAINED first (== intrinsic),
            // so the inner SizedBox is what imposes the canonical TIGHT size on
            // the editor subtree: 700 wide, same A4 aspect. Text wraps at 700,
            // ink captures (inverse-transformed hit tests) are in document
            // units, and paint is then scaled to the on-screen box. Clip.none
            // is fine — the outer ClipRRect clips the box, and rounding never
            // overpaints it.
            child: FittedBox(
              fit: BoxFit.contain,
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
                        // Text layer — absorbs pointers while drawing so strokes
                        // don't also move the caret (same pattern as EditorSurface).
                        // The PagedTableBounds exposes this page's sheet geometry to
                        // deep block widgets (the forked table) so they can cap
                        // their own growth against the page — in DOCUMENT units,
                        // which is what makes those caps stable across windows.
                        PagedTableBounds(
                          sheetKey: _stackKey,
                          child: AbsorbPointer(
                            absorbing: widget.drawingEnabled,
                            child: widget.controller.driver.buildEditor(
                              context,
                            ),
                          ),
                        ),
                        // Ink layer — only receptive to pointers while drawing.
                        // Positions here are document units: a stroke drawn at
                        // overview zoom records exactly where it LOOKS in the
                        // page's own space, not where the pointer was on screen.
                        // Chrome sized for the HAND (eraser cursor, scribble
                        // width) therefore looks proportionally smaller at
                        // overview zoom — correct: the page is zoomed out.
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
                        // Analysis-review overlay: tint the block + inline popover.
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

    // Convert vertical bounds from global (screen px with fitted zoom) to local document units
    final localTopLeft = stackBox.globalToLocal(sectionRect.topLeft);
    final localBottomRight = stackBox.globalToLocal(sectionRect.bottomRight);

    // Set horizontal bounds to full content column width
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
      // Highlight tint spanning the full text content area
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
      // Findings popover attached to the block section
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

  /// Union rect of every top-level block on this page whose stable id appears
  /// in the recorded `blockIds` of [chunks]. The recorded ids are the AUTHORITY
  /// for the group — this is why the highlight holds still while the caret moves
  /// within a chunk. Returns null when nothing resolves.
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

  /// How many of [ids] are NOT top-level blocks on the current page — i.e. the
  /// analysis references blocks that have been deleted or moved off this page.
  int _countMissingOnPage(Set<String> ids) {
    if (ids.isEmpty) return 0;
    final present = <String>{
      for (final b
          in (widget.controller.documentJson['children'] as List?) ?? const [])
        if ((b as Map?)?['id']?.toString() case final String id) id,
    };
    return ids.where((id) => !present.contains(id)).length;
  }

  /// Walks the semantic section under [startIdx] — the block and every
  /// subsequent top-level block until the next heading — returning the union
  /// rect (null if nothing laid out) and the walked blocks' stable ids.
  (Rect?, List<String>) _sectionWalk(int startIdx) {
    final driver = _driver;
    if (driver == null) return (null, const []);

    final blocks =
        (widget.controller.documentJson['children'] as List?) ?? const [];
    Rect? result;
    final ids = <String>[];

    for (var i = startIdx; i < blocks.length; i++) {
      // After the first block, stop *before* accumulating the next heading —
      // it starts a new section.  Check first, accumulate second.
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

/// Compact inline card listing the findings for the tapped block's chunk(s).
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

  /// Number of blocks this analysis references that no longer match the note
  /// (recorded blocks deleted / content added since the analysis ran).
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
