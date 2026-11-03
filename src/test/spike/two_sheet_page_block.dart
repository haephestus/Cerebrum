import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cerebrum/ui/screens/editor/widgets/page_space.dart';

/// SPIKE (two-sheet single-document pagination — Strategy B probe).
///
/// NOT for production: no measurement engine, no overflow detection, no
/// interaction with PagedNoteController. This exists to answer five
/// questions (see two_sheet_spike_test.dart) about ONE AppFlowyEditor whose
/// root 'page' block lays its children out as TWO fixed paper sheets:
///
///   1. Does mouse drag-selection cross the sheet boundary?
///   2. Does an insert+delete splice at the seam re-group and keep the
///      caret sane (the §8 "block spills forward" shape)?
///   3. Do ids and interactions survive a save/reload round trip?
///   4. Does the caret rect resolve correctly for the sheet the caret
///      moved onto (vim j/k follow machinery)?
///   5. Does tapping a block in the second sheet hit the right node?
///
/// Group rule (§8): which sheet a block belongs to is the node's OWN
/// `pageId` attribute; children order decides sheet order. The stock
/// page block builds ONE Column of `renderer.build` children (that is
/// literally all the shrinkWrap branch is); this builder builds that same
/// shape with N sheet-wrapped Columns.
class SpikeTwoSheetPageBuilder extends BlockComponentBuilder {
  SpikeTwoSheetPageBuilder({this.sheetWidth, this.sheetHeight});

  /// Paper size overrides. The tests run small sheets so everything fits
  /// inside the default test viewport WITHOUT touching the test view's
  /// metrics — a metrics reset after dispose trips a debounce bug in the
  /// package's desktop_selection_service (timer fires on a disposed state).
  final double? sheetWidth;
  final double? sheetHeight;

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    return SpikePageComponent(
      key: blockComponentContext.node.key,
      node: blockComponentContext.node,
      sheetWidth: sheetWidth,
      sheetHeight: sheetHeight,
    );
  }
}

class SpikePageComponent extends BlockComponentStatelessWidget {
  const SpikePageComponent({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.actionTrailingBuilder,
    super.configuration = const BlockComponentConfiguration(),
    this.sheetWidth,
    this.sheetHeight,
  });

  final double? sheetWidth;
  final double? sheetHeight;

  /// Paper geometry straight out of [page_space.dart] unless overridden
  /// (tests use small sheets; see the builder's comment).
  double get width => sheetWidth ?? kDocSheetWidth;
  double get height => sheetHeight ?? kDocSheetWidth / kPageAspectRatio;

  @override
  Widget build(BuildContext context) {
    final editorState = context.read<EditorState>();
    final items = node.children;

    // Group into runs by each node's pageId attribute; order of runs ==
    // order of first appearance in the child list.
    final sheets = <List<Node>>[];
    String current = 'sheet-1';
    var run = <Node>[];
    for (final child in items) {
      final pageId =
          child.attributes['pageId']?.toString() ?? 'sheet-1';
      if (pageId != current && run.isNotEmpty) {
        sheets.add(run);
        run = <Node>[];
        current = pageId;
      }
      run.add(child);
    }
    if (run.isNotEmpty) sheets.add(run);

    // Same SingleChildScrollView + auto-scroller handoff as the stock
    // shrinkWrap branch, so scroll behavior matches the app's configuration.
    return SingleChildScrollView(
      child: Builder(
        builder: (context) {
          final scroller = Scrollable.maybeOf(context);
          if (scroller != null) {
            editorState.updateAutoScroller(scroller);
          }
          return Column(
            children: [
              for (final sheet in sheets)
                _SpikeSheet(
                  key: ValueKey('spike-${sheet.first.id}'),
                  editorState: editorState,
                  nodes: sheet,
                  width: width,
                  height: height,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _SpikeSheet extends StatelessWidget {
  const _SpikeSheet({
    super.key,
    required this.editorState,
    required this.nodes,
    required this.width,
    required this.height,
  });

  final EditorState editorState;
  final List<Node> nodes;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      margin: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.symmetric(horizontal: kBaseHorizontalPadding),
      // Deliberately NOT clipped (Clip.none is the default for overflow
      // off a plain Column here): the real engine will clip/ink-associate;
      // the spike wants overflowing content visible, not hidden.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final node in nodes) editorState.renderer.build(context, node),
        ],
      ),
    );
  }
}
