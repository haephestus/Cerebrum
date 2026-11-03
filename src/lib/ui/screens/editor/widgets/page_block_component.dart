import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
/// the GLOBAL top-level block index (position in root.children, not the
/// sheet-local position) because that is what the flow executor addresses.
///
/// UNVERIFIED on device — executor wiring (transaction-based flows) is the
/// next phase; with null callbacks this renders and measures silently.
class PageBlockComponentBuilder extends BlockComponentBuilder {
  // Not const-constructible: BlockComponentBuilder has mutable fields
  // (validate) — same constraint EquationBlockComponentBuilder documents.
  PageBlockComponentBuilder();

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return PageBlockComponent(
      key: node.key,
      node: node,
      configuration: configuration,
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
  });

  /// First GLOBAL top-level block index that spills past the sheet bottom.
  /// [tableAvailableHeight] is set only when the overflowing block is a
  /// table — the vertical room the table head may keep on this sheet, so
  /// the executor can split at a row boundary instead of moving the whole
  /// block.
  final void Function(int fromBlockIndex, {double? tableAvailableHeight})?
  onOverflow;

  /// Fired when the sheet did NOT overflow: [freeHeight] is spare space
  /// below the last block, [headBlockHeight] the first block's height —
  /// the underfill pair the backward reflow pulls on. Null head means the
  /// first block never laid out.
  final void Function(double freeHeight, double? headBlockHeight)? onUnderfill;

  @override
  Widget build(BuildContext context) {
    final editorState = context.read<EditorState>();
    final runs = _groupByPageId(node.children);

    return Column(
      children: [
        for (final run in runs)
          _PageSheet(
            key: ValueKey('cerebrum-sheet-${run.nodes.first.id}'),
            editorState: editorState,
            nodes: run.nodes,
            globalStartIndex: run.start,
            sheetWidth: kDocSheetWidth,
            sheetHeight: kDocSheetWidth / kPageAspectRatio,
            onOverflow: onOverflow,
            onUnderfill: onUnderfill,
          ),
      ],
    );
  }

  /// Group children by their `pageId` attribute; also record each run's
  /// starting index in [node.children] so measurements can report GLOBAL
  /// block indexes (the currency pushOverflow/planForwardOverflow speak).
  /// Missing pageId defaults to the first page.
  List<({String pageId, int start, List<Node> nodes})> _groupByPageId(
    Iterable<Node> children,
  ) {
    final runs = <({String pageId, int start, List<Node> nodes})>[];
    var currentId = 'sheet-1';
    var start = 0;
    var run = <Node>[];
    var index = 0;
    for (final child in children) {
      final pageId = child.attributes['pageId']?.toString() ?? 'sheet-1';
      if (pageId != currentId && run.isNotEmpty) {
        runs.add((pageId: currentId, start: start, nodes: run));
        run = <Node>[];
        currentId = pageId;
        start = index;
      }
      run.add(child);
      index++;
    }
    if (run.isNotEmpty) {
      runs.add((pageId: currentId, start: start, nodes: run));
    }
    return runs;
  }
}

/// One paper sheet: fixed canonical size, laid out ONCE in document units.
/// Carries the per-sheet measurement pass (overflow + underfill reports).
class _PageSheet extends StatefulWidget {
  const _PageSheet({
    super.key,
    required this.editorState,
    required this.nodes,
    required this.globalStartIndex,
    required this.sheetWidth,
    required this.sheetHeight,
    required this.onOverflow,
    required this.onUnderfill,
  });

  final EditorState editorState;
  final List<Node> nodes;
  final int globalStartIndex;
  final double sheetWidth;
  final double sheetHeight;
  final void Function(int fromBlockIndex, {double? tableAvailableHeight})?
  onOverflow;
  final void Function(double freeHeight, double? headBlockHeight)? onUnderfill;

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final node in widget.nodes)
            widget.editorState.renderer.build(context, node),
        ],
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
    widget.onUnderfill?.call(free, headHeight);
  }
}
