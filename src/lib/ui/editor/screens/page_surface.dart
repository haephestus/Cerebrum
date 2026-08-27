import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:cerebrum/ui/editor/controllers/note_editor_controller.dart';
import 'package:cerebrum/ui/editor/controllers/appflowy_text_driver.dart';
import 'package:cerebrum/ui/editor/screens/drawing_layer.dart';
import 'package:cerebrum/ui/editor/screens/paged_editor.dart'
    show BlockAnalysisLookup;

/// One page of a note: a fixed-aspect "sheet" (A4 portrait) holding the text
/// editor + ink layer, stacked — the paged equivalent of EditorSurface, bounded
/// to a page instead of filling the screen.
///
/// Ink is naturally page-LOCAL: each page has its own bounded scribble widget,
/// so strokes are relative to this sheet, not a global surface.
///
/// **Why the overflow detection lives HERE, not in the controller.** The
/// controller decides *what* to move on overflow ([PagedNoteController.pushOverflow]),
/// but it can't tell *whether* the page overflows — that's a rendered-layout
/// question, and only the widget can see the layout. So this widget measures each
/// block's on-screen rect against the sheet's bottom edge and reports the first
/// block that spills over (via [onOverflow]). The measurement runs in a
/// post-frame callback (a block's rect only exists after layout) and is coalesced
/// to once per frame (typing fires many notifications). Because a rebuild remounts
/// this widget (`ObjectKey(controller)`), the check re-runs on the new page and
/// naturally *cascades* forward until every page fits.
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
/// overlay geometry (globalToLocal, popover placement) need a smoke test on a
/// real page.
class PageSurface extends StatefulWidget {
  const PageSurface({
    super.key,
    required this.controller,
    required this.drawingEnabled,
    this.pageNumber,
    this.pageId,
    this.analysisForBlock,
    this.onOverflow,
    this.partialEraser,
    this.eraserWidth,
    this.aspectRatio = 1 / 1.414, // A4 portrait
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
  final void Function(int fromBlockIndex)? onOverflow;

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

  /// Measure once per frame, after layout, whether this page overflows the sheet.
  void _scheduleOverflowCheck() {
    if (_overflowCheckScheduled || widget.onOverflow == null) return;
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
    if (onOverflow == null || driver == null) return;

    final stackBox = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (stackBox == null || !stackBox.hasSize) return;
    final pageBottom =
        stackBox.localToGlobal(Offset(0, stackBox.size.height)).dy;

    final blocks =
        (widget.controller.documentJson['children'] as List?) ?? const [];
    // Start at 1: always keep at least the first block on the page. A lone block
    // taller than the whole sheet can't be moved off without splitting (which
    // this model doesn't do), so it's left to overflow rather than loop forever.
    // TODO(tables): an oversized TABLE hits exactly this case and overflows its
    // own sheet — see PagedNoteController.pushOverflow for the follow-up options.
    const tolerance = 0.5;
    for (var i = 1; i < blocks.length; i++) {
      final rect = driver.rectOfBlock(i);
      if (rect == null) continue;
      if (rect.bottom > pageBottom + tolerance) {
        onOverflow(i);
        return;
      }
    }
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
    return Center(
      child: AspectRatio(
        aspectRatio: widget.aspectRatio,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: AnimatedBuilder(
              animation: widget.controller,
              builder: (context, _) {
                return Stack(
                  key: _stackKey,
                  children: [
                    // Text layer — absorbs pointers while drawing so strokes
                    // don't also move the caret (same pattern as EditorSurface).
                    AbsorbPointer(
                      absorbing: widget.drawingEnabled,
                      child: widget.controller.driver.buildEditor(context),
                    ),
                    // Ink layer — only receptive to pointers while drawing.
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
                            style: const TextStyle(
                              color: Colors.black38,
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
    );
  }

  List<Widget> _analysisOverlay() {
    final idx = _activeBlockIndex;
    if (idx == null || widget.drawingEnabled || _driver == null) {
      return const [];
    }
    final globalRect = _driver!.rectOfBlock(idx);
    final stackBox = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (globalRect == null || stackBox == null) return const [];

    // Global → page-local. The editor lays out 1:1 within the page (no scaling),
    // so the block's size carries over unchanged.
    final localTopLeft = stackBox.globalToLocal(globalRect.topLeft);
    final blockRect = localTopLeft & globalRect.size;
    final pageSize = stackBox.size;

    const popoverWidth = 300.0;
    const gap = 6.0;
    // Prefer below the block; flip above if it would overflow the sheet bottom.
    final estPopoverHeight = 220.0;
    final belowSpace = pageSize.height - blockRect.bottom;
    final placeBelow = belowSpace >= estPopoverHeight || belowSpace >= blockRect.top;
    final left =
        blockRect.left.clamp(0.0, (pageSize.width - popoverWidth).clamp(0.0, double.infinity));
    final top = placeBelow
        ? (blockRect.bottom + gap)
        : (blockRect.top - gap - estPopoverHeight).clamp(0.0, double.infinity);

    return [
      // Block tint.
      Positioned.fromRect(
        rect: blockRect,
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.18),
              border: Border.all(
                color: Colors.amber.withValues(alpha: 0.7),
                width: 1.2,
              ),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
      ),
      // Findings popover.
      Positioned(
        left: left,
        top: top,
        width: popoverWidth,
        child: _AnalysisPopover(
          chunks: _activeChunks,
          maxHeight: estPopoverHeight,
          onClose: _dismiss,
        ),
      ),
    ];
  }
}

/// Compact inline card listing the findings for the tapped block's chunk(s).
class _AnalysisPopover extends StatelessWidget {
  const _AnalysisPopover({
    required this.chunks,
    required this.maxHeight,
    required this.onClose,
  });

  final List<Map<String, dynamic>> chunks;
  final double maxHeight;
  final VoidCallback onClose;

  static Color _severityColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'high':
      case 'critical':
        return Colors.red;
      case 'medium':
      case 'moderate':
        return Colors.orange;
      case 'low':
      case 'minor':
        return Colors.amber;
      default:
        return Colors.blueGrey;
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
      borderRadius: BorderRadius.circular(10),
      color: Colors.white,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.insights_rounded, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    'Block analysis',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const Spacer(),
                  InkResponse(
                    onTap: onClose,
                    child: const Icon(Icons.close, size: 16),
                  ),
                ],
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
                    itemBuilder: (context, i) => _finding(findings[i]),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _finding(Map<String, dynamic> finding) {
    final severity = (finding['severity'] ?? 'unknown').toString();
    final type =
        (finding['type'] ?? 'finding').toString().replaceAll('_', ' ');
    final gap = finding['gap_explanation'] as String?;
    final claim = finding['student_claim'] as String?;
    final detail = gap ?? claim;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(radius: 5, backgroundColor: _severityColor(severity)),
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
                color: _severityColor(severity),
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
