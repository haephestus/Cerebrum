import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cerebrum/ui/screens/editor/helpers/page_runs.dart';
import 'package:cerebrum/ui/screens/editor/helpers/page_ink_surface.dart';
import 'package:cerebrum/ui/screens/editor/widgets/drawing_layer.dart';
import 'package:cerebrum/ui/screens/editor/widgets/page_space.dart';

/// Production "page" block component for Strategy B (single-document
/// pagination).
///
/// The root 'page' node's children each carry a `pageId` attribute; this
/// component groups consecutive children by that attribute and lays each
/// group out inside a fixed-height paper sheet ([kDocSheetWidth] wide, A4
/// aspect). Child ORDER decides sheet order — same rule the spike
/// (test/spike/two_sheet_page_block.dart) validated 5/5.
///
/// Measurement: each sheet measures its blocks post-frame via `node.rect`
/// (the AppFlowy node's own render box — global coordinates) mapped back
/// through the sheet's box, so all numbers are document units and
/// window-independent, exactly like PageSurface's pre-Strategy-B checks.
/// Reports go to the optional [onOverflow] / [onUnderfill] callbacks with
/// the sheet's `pageId` plus the GLOBAL top-level block index (position in
/// root.children, not the sheet-local position) because that is what the
/// flow executor addresses — see helpers/flow_executor.dart.
///
/// UNVERIFIED on device — executor is transaction-wired but the Strategy-B
/// note model (single EditorState per NOTE) is still behind the
/// [kUseSingleDocumentPagination] flag; with null callbacks this renders
/// and measures silently.
class PageBlockComponentBuilder extends BlockComponentBuilder {
  // Not const-constructible: BlockComponentBuilder has mutable fields
  // (validate) — same constraint EquationBlockComponentBuilder documents.
  PageBlockComponentBuilder({
    this.onOverflow,
    this.onUnderfill,
    this.inkSurface,
    this.sheetWidth,
    this.sheetHeight,
  });

  /// Forwarded to every sheet the component builds. Tests inject small
  /// sheet metrics so everything fits the default test viewport; production
  /// leaves both null → canonical page_space.dart geometry.
  final void Function(String pageId, int fromBlockIndex,
      {double? tableAvailableHeight})? onOverflow;
  final void Function(String pageId, double freeHeight,
      double? headBlockHeight)? onUnderfill;

  /// Strategy-B ink rail (notifiers keyed by pageId, seeded from the
  /// per-pageId ink store; drawing-enabled toggled by the controller).
  /// Null: no ink layer renders (pre-note-model, and the flag stays off).
  final PageInkSurface? inkSurface;
  final double? sheetWidth;
  final double? sheetHeight;

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return PageBlockComponent(
      key: node.key,
      node: node,
      configuration: configuration,
      onOverflow: onOverflow,
      onUnderfill: onUnderfill,
      inkSurface: inkSurface,
      sheetWidth: sheetWidth,
      sheetHeight: sheetHeight,
    );
  }
}

class PageBlockComponent extends BlockComponentStatelessWidget {
  const PageBlockComponent({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.actionTrailingBuilder,
    super.configuration = const BlockComponentConfiguration(),
    this.onOverflow,
    this.onUnderfill,
    this.inkSurface,
    this.sheetWidth,
    this.sheetHeight,
  });

  /// First GLOBAL top-level block index that spills past [pageId]'s sheet
  /// bottom. [tableAvailableHeight] is set only when the overflowing block
  /// is a table — the vertical room the table head may keep on this sheet,
  /// so the executor can split at a row boundary instead of moving the
  /// whole block.
  final void Function(String pageId, int fromBlockIndex,
      {double? tableAvailableHeight})? onOverflow;

  /// Fired when the sheet did NOT overflow: [freeHeight] is spare space
  /// below the last block, [headBlockHeight] the first block's height —
  /// the underfill pair the backward reflow pulls on. Null head means the
  /// first block never laid out.
  final void Function(String pageId, double freeHeight,
      double? headBlockHeight)? onUnderfill;

  /// Strategy-B ink rail shared with the builder (see
  /// [PageBlockComponentBuilder.inkSurface]). Forwarded to every sheet.
  final PageInkSurface? inkSurface;

  /// Paper geometry overrides (tests use small sheets). Null → canonical
  /// [kDocSheetWidth] / A4 aspect from page_space.dart.
  final double? sheetWidth;
  final double? sheetHeight;

  @override
  Widget build(BuildContext context) {
    final editorState = context.read<EditorState>();
    final runs = groupRunsByPageId(node.children);
    final width = sheetWidth ?? kDocSheetWidth;
    final height = sheetHeight ?? kDocSheetWidth / kPageAspectRatio;

    return ListView(
      // The notes canvas is one bounded-height A4 viewport under Strategy B;
      // consecutive sheets can outgrow it (some notes are hundreds of
      // paragraphs), so the sheet column must be scrollable. shrinkWrap:
      // the ListView reports the full document height to shrink-wrap
      // parent layouts (the AppFlowy engine measures the Column as a
      // shrink-wrapped scrollable child) — children keep their fixed
      // canonical heights regardless.
      shrinkWrap: true,
      physics: const ClampingScrollPhysics(),
      children: [
        for (final run in runs)
          _PageSheet(
            key: ValueKey('cerebrum-sheet-${run.nodes.first.id}'),
            inkSurface: inkSurface,
            editorState: editorState,
            nodes: run.nodes,
            pageId: run.pageId,
            globalStartIndex: run.start,
            sheetWidth: width,
            sheetHeight: height,
            onOverflow: onOverflow,
            onUnderfill: onUnderfill,
          ),
      ],
    );
  }
}

/// One paper sheet: fixed canonical size, laid out ONCE in document units.
/// Carries the per-sheet measurement pass (overflow + underfill reports).
class _PageSheet extends StatefulWidget {
  const _PageSheet({
    super.key,
    required this.editorState,
    required this.nodes,
    required this.pageId,
    required this.globalStartIndex,
    required this.sheetWidth,
    required this.sheetHeight,
    this.inkSurface,
    this.onOverflow,
    this.onUnderfill,
  });

  final EditorState editorState;
  final List<Node> nodes;
  final String pageId;
  final int globalStartIndex;
  final double sheetWidth;
  final double sheetHeight;
  /// Strategy-B ink rail shared with the component; null → no ink layer.
  final PageInkSurface? inkSurface;
  final void Function(String pageId, int fromBlockIndex,
      {double? tableAvailableHeight})? onOverflow;
  final void Function(String pageId, double freeHeight,
      double? headBlockHeight)? onUnderfill;

  @override
  State<_PageSheet> createState() => _PageSheetState();
}

class _PageSheetState extends State<_PageSheet> {
  bool _measureScheduled = false;

  // Deliberately NOT clipped: overflowing content stays visible for the
  // frame(s) before the executor moves it, matching the spike's choice —
  // content that silently vanishes reads as a bug during a flow.
  @override
  Widget build(BuildContext context) {
    // Every document transaction rebuilds the subtree; each rebuild is a
    // chance for heights to have changed → re-check after this frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    return Container(
      width: widget.sheetWidth,
      height: widget.sheetHeight,
      margin: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.symmetric(horizontal: kBaseHorizontalPadding),
      child: AnimatedBuilder(
        animation: widget.inkSurface?.drawingEnabled ??
            const AlwaysStoppedAnimation<bool>(false),
        builder: (context, _) {
          final drawing = widget.inkSurface?.drawingEnabled.value ?? false;
          return Stack(
            fit: StackFit.expand,
            children: [
              // Text layer — absorbs pointers while drawing so strokes
              // don't also move the caret (same pattern as PageSurface).
              AbsorbPointer(
                absorbing: drawing,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final node in widget.nodes)
                      widget.editorState.renderer.build(context, node),
                  ],
                ),
              ),
              // Ink layer — only receptive to pointers while drawing. Keyed
              // strictly by pageId, so a stroke follows [widget.pageId]'s
              // run wherever the document decides that run lives.
              if (widget.inkSurface != null)
                IgnorePointer(
                  ignoring: !drawing,
                  child: NoteDrawingLayer(
                    notifier: widget.inkSurface!.notifierFor(widget.pageId),
                    partialEraser: widget.inkSurface!.partialEraser,
                    eraserWidth: widget.inkSurface!.eraserWidth,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  void _measure() {
    if (!mounted || _measureScheduled) return;
    _measureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureScheduled = false;
      if (!mounted) return;
      _check();
    });
  }

  void _check() {
    if (widget.onOverflow == null && widget.onUnderfill == null) return;
    final sheetBox = context.findRenderObject();
    if (sheetBox is! RenderBox || !sheetBox.hasSize) return;

    const tolerance = 0.5; // document pixels
    final pageBottom = sheetBox.size.height;

    Rect? firstRect;
    Rect? lastRect;
    for (var i = 0; i < widget.nodes.length; i++) {
      final node = widget.nodes[i];
      if (node.renderBox == null) continue; // not laid out (yet)
      final rect = node.rect;
      final topLocal = sheetBox.globalToLocal(rect.topLeft);
      final bottomLocal = sheetBox.globalToLocal(rect.bottomLeft).dy;
      firstRect ??= rect;
      lastRect = rect;
      if (bottomLocal > pageBottom + tolerance) {
        final isTable = node.type == 'table';
        widget.onOverflow?.call(
          widget.pageId,
          widget.globalStartIndex + i,
          tableAvailableHeight: isTable ? pageBottom - topLocal.dy : null,
        );
        return; // first spill decides; cascade handles the rest
      }
    }

    // No overflow → publish the underfill pair for backward reflow.
    if (widget.onUnderfill == null || lastRect == null) return;
    final lastBottom = sheetBox.globalToLocal(lastRect.bottomLeft).dy;
    final free = pageBottom - lastBottom;
    if (free <= 0) return;
    double? headHeight;
    if (firstRect != null) {
      final firstTop = sheetBox.globalToLocal(firstRect.topLeft).dy;
      final firstBottom = sheetBox.globalToLocal(firstRect.bottomLeft).dy;
      headHeight = firstBottom - firstTop;
    }
    widget.onUnderfill?.call(widget.pageId, free, headHeight);
  }
}
