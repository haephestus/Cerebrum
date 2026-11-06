import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:cerebrum/ui/themes/theme_access.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cerebrum/ui/screens/editor/helpers/page_runs.dart';
import 'package:cerebrum/ui/screens/editor/helpers/page_ink_surface.dart';
import 'package:cerebrum/ui/screens/editor/widgets/heading_level_tag.dart';
import 'package:cerebrum/ui/screens/editor/widgets/drawing_layer.dart';
import 'package:cerebrum/ui/screens/editor/widgets/page_space.dart';

/// Vertical margin applied ABOVE and BELOW every sheet. Also factored into
/// PageSurface's outer SizedBox height (see `totalHeight` there) so the
/// container exactly fits the stack of sheets — if you change this, the
/// outer Column stops overflowing only as long as the two stay in sync,
/// which is why it lives here as a single named constant.
const double kSheetVerticalMargin = 12.0;

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
  final void Function(
    String pageId,
    int fromBlockIndex, {
    double? tableAvailableHeight,
  })?
  onOverflow;
  final void Function(
    String pageId,
    double freeHeight,
    double? headBlockHeight,
  )?
  onUnderfill;

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
  final void Function(
    String pageId,
    int fromBlockIndex, {
    double? tableAvailableHeight,
  })?
  onOverflow;

  /// Fired when the sheet did NOT overflow: [freeHeight] is spare space
  /// below the last block, [headBlockHeight] the first block's height —
  /// the underfill pair the backward reflow pulls on. Null head means the
  /// first block never laid out.
  final void Function(
    String pageId,
    double freeHeight,
    double? headBlockHeight,
  )?
  onUnderfill;

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

    return Column(
      // The column is the single scroll surface — the OUTER paged ScrollView
      // is the only scrollable involving the user. No inner ListView, no
      // inner scrollbar. Each sheet stays fixed at its canonical height and
      // the column grows to fit however many sheets exist.
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Page numbers follow SHEET ORDER (1-based run position), not the
        // pageId string — pageIds are stable identities ('p3' can sit second
        // after a reflow), the number a reader sees must be positional.
        for (final (i, run) in runs.indexed)
          _PageSheet(
            key: ValueKey('cerebrum-sheet-${run.nodes.first.id}'),
            inkSurface: inkSurface,
            editorState: editorState,
            nodes: run.nodes,
            pageId: run.pageId,
            pageNumber: i + 1,
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
    required this.pageNumber,
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

  /// 1-based position of this sheet in the note, painted in the bottom
  /// margin. Chrome only — never part of the document.
  final int pageNumber;
  final int globalStartIndex;
  final double sheetWidth;
  final double sheetHeight;

  /// Strategy-B ink rail shared with the component; null → no ink layer.
  final PageInkSurface? inkSurface;
  final void Function(
    String pageId,
    int fromBlockIndex, {
    double? tableAvailableHeight,
  })?
  onOverflow;
  final void Function(
    String pageId,
    double freeHeight,
    double? headBlockHeight,
  )?
  onUnderfill;

  @override
  State<_PageSheet> createState() => _PageSheetState();
}

class _PageSheetState extends State<_PageSheet> {
  bool _measureScheduled = false;

  // Clipped to the sheet rect (clipBehavior on the Container) so an
  // overflowing tail never paints outside the page chrome; the executor
  // still moves the tail on the next settle — the clip only hides it for
  // the one frame it's in flux.
  @override
  Widget build(BuildContext context) {
    // Every document transaction rebuilds the subtree; each rebuild is a
    // chance for heights to have changed → re-check after this frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    return Container(
      width: widget.sheetWidth,
      height: widget.sheetHeight,
      // Uses kSheetVerticalMargin (top-of-file constant) — the SAME value
      // PageSurface.build factors into its totalHeight calculation, so the
      // outer Column and the outer SizedBox stay in agreement. Hardcoding
      // here once already broke that contract (48px overflow in the outer
      // Column) when PageSurface was tightened. Keep them tied.
      margin: const EdgeInsets.symmetric(vertical: kSheetVerticalMargin),
      clipBehavior: Clip.hardEdge,
      // Themed paper sheet: fill from the app surface/raised (matches the
      // A-branch and the rest of the app chrome), border from the editor
      // page colour, soft shadow. No hard-coded white/black that ignores
      // the selected theme.
      decoration: BoxDecoration(
        color: context.cerebrum.surface.raised,
        border: Border.all(color: context.cerebrum.editor.pageBorder),
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(
            color: context.cerebrum.editor.pageShadowSoft,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      // NOTE: no `padding:` on this Container any more. The paper margins are
      // applied to the TEXT layer only (see the Padding below) so the ink
      // layer and the page number can span the WHOLE sheet — with the padding
      // here, strokes were confined to the content box and the number had no
      // margin to live in.
      child: AnimatedBuilder(
        animation:
            widget.inkSurface?.drawingEnabled ??
            const AlwaysStoppedAnimation<bool>(false),
        builder: (context, _) {
          final drawing = widget.inkSurface?.drawingEnabled.value ?? false;
          return Stack(
            // expand: every layer is sized to the full sheet box. The text
            // layer insets itself with Padding; the ink layer and page number
            // use the whole sheet, margins included.
            fit: StackFit.expand,
            children: [
              // Text layer — absorbs pointers while drawing so strokes
              // don't also move the caret (same pattern as PageSurface).
              // Padded by the paper margins, and CLIPPED to the padded area
              // so a transient overflowing tail (between "content grew" and
              // "executor pushed it") never paints into the bottom margin
              // where the page number sits.
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  kBaseHorizontalPadding,
                  kBaseVerticalPadding,
                  kBaseHorizontalPadding,
                  kBaseVerticalPadding,
                ),
                child: ClipRect(
                  child: AbsorbPointer(
                    absorbing: drawing,
                    // OverflowBox: the sheet is FIXED-SIZE (one A4 page).
                    // While the flow executor is between "content grew" and
                    // "pushed the tail to the next sheet", the content Column
                    // genuinely needs to be taller than the sheet. Without
                    // this wrapper, RenderFlex asserts on that transient
                    // frame; with it, the Column lays out to its natural
                    // height, the OverflowBox reports the CONSTRAINED size up
                    // to the Stack, the ClipRect above crops the overflow
                    // visually, and the executor pushes the tail on the next
                    // frame as usual.
                    child: OverflowBox(
                      alignment: Alignment.topCenter,
                      minHeight: 0,
                      maxHeight: double.infinity,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final node in widget.nodes)
                            if (node.type == 'heading' &&
                                (node.delta?.isNotEmpty ?? false))
                              HeadingLevelTag(
                                level:
                                    (node.attributes['level'] as num?)
                                        ?.toInt() ??
                                    1,
                                child: widget.editorState.renderer.build(
                                  context,
                                  node,
                                ),
                              )
                            else
                              widget.editorState.renderer.build(context, node),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // Ink layer — only receptive to pointers while drawing. Keyed
              // strictly by pageId, so a stroke follows [widget.pageId]'s
              // run wherever the document decides that run lives. Spans the
              // FULL sheet (margins included).
              if (widget.inkSurface != null)
                IgnorePointer(
                  ignoring: !drawing,
                  child: NoteDrawingLayer(
                    notifier: widget.inkSurface!.notifierFor(widget.pageId),
                    partialEraser: widget.inkSurface!.partialEraser,
                    eraserWidth: widget.inkSurface!.eraserWidth,
                  ),
                ),
              // Page number — bottom margin, bottom-right. Painted above the
              // ink layer but ignores pointers so it never blocks drawing.
              Positioned(
                right: kBaseHorizontalPadding,
                bottom: 4,
                child: IgnorePointer(
                  child: Text(
                    '${widget.pageNumber}',
                    style: TextStyle(
                      color: context.cerebrum.text.disabled,
                      fontSize: kBaseFontSize,
                    ),
                  ),
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
    // Content area boundary — anything below this crosses into the
    // footer margin and must push to the next page before painting over
    // it.
    //
    // `sheetBox` is this State's OUTERMOST render object, which is the
    // Container's MARGIN box (sheet + kSheetVerticalMargin above and below),
    // and globalToLocal is relative to that box's origin — so the sheet's
    // bottom edge sits at size.height - kSheetVerticalMargin, and the
    // content boundary is the bottom padding above THAT. (Subtracting only
    // the padding let blocks run kSheetVerticalMargin units into the bottom
    // margin before being pushed.)
    final pageBottom =
        sheetBox.size.height - kSheetVerticalMargin - kBaseVerticalPadding;

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
