import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'table_keys.dart';
import 'table_view.dart';

/// Fork of AppFlowy's table block component.
///
/// Registered against `CerebrumTableBlockKeys.type` ('table') in the app's
/// editor driver, replacing the stock `TableBlockComponentBuilder`. Behaviour
/// is identical to the original except:
///   * the + buttons / context menu / column resize are capped so the table
///     can never grow past the sheet (see table_view.dart / table_action_menu.dart
///     / table_col_border.dart);
///   * the block still renders inside a horizontal scroll view as a safety net
///     for pre-existing tables that are already wider than the sheet — NEW
///     growth is prevented by the caps above.
class CerebrumTableBlockComponentBuilder extends BlockComponentBuilder {
  CerebrumTableBlockComponentBuilder({
    super.configuration,
    this.tableStyle = const CerebrumTableStyle(),
    this.menuBuilder,
  });

  final CerebrumTableBlockComponentMenuBuilder? menuBuilder;
  final CerebrumTableStyle tableStyle;

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    CerebrumTableDefaults.colWidth = tableStyle.colWidth;
    CerebrumTableDefaults.rowHeight = tableStyle.rowHeight;
    CerebrumTableDefaults.colMinimumWidth = tableStyle.colMinimumWidth;
    CerebrumTableDefaults.borderWidth = tableStyle.borderWidth;
    return CerebrumTableBlockComponentWidget(
      key: node.key,
      tableNode: TableNode(node: node),
      node: node,
      configuration: configuration,
      menuBuilder: menuBuilder,
      tableStyle: tableStyle,
      showActions: showActions(node),
      actionBuilder: (context, state) => actionBuilder(
        blockComponentContext,
        state,
      ),
      actionTrailingBuilder: (context, state) => actionTrailingBuilder(
        blockComponentContext,
        state,
      ),
    );
  }

  @override
  BlockComponentValidate get validate => (node) {
        // check the node is valid
        if (node.attributes.isEmpty) {
          AppFlowyEditorLog.editor
              .debug('CerebrumTableBlockComponentBuilder: node is empty');
          return false;
        }

        // check the node has colLen and rowsLen
        if (!node.attributes.containsKey(CerebrumTableBlockKeys.colsLen) ||
            !node.attributes.containsKey(CerebrumTableBlockKeys.rowsLen)) {
          AppFlowyEditorLog.editor.debug(
            'CerebrumTableBlockComponentBuilder: node has no colsLen or rowsLen',
          );
          return false;
        }

        final colsLen = node.attributes[CerebrumTableBlockKeys.colsLen];
        final rowsLen = node.attributes[CerebrumTableBlockKeys.rowsLen];

        // check its children
        final children = node.children;
        if (children.isEmpty) {
          AppFlowyEditorLog.editor
              .debug('CerebrumTableBlockComponentBuilder: children is empty');
          return false;
        }

        if (children.length != colsLen * rowsLen) {
          AppFlowyEditorLog.editor.debug(
            'CerebrumTableBlockComponentBuilder: children length(${children.length}) is not equal to colsLen * rowsLen($colsLen * $rowsLen)',
          );
          return false;
        }

        // all children should contain rowPosition and colPosition
        for (var i = 0; i < colsLen; i++) {
          for (var j = 0; j < rowsLen; j++) {
            final child = children.where(
              (n) =>
                  n.attributes[CerebrumTableCellKeys.colPosition] == i &&
                  n.attributes[CerebrumTableCellKeys.rowPosition] == j,
            );
            if (child.isEmpty) {
              AppFlowyEditorLog.editor.debug(
                'CerebrumTableBlockComponentBuilder: child($i, $j) is empty',
              );
              return false;
            }

            // should only contains one child
            if (child.length != 1) {
              AppFlowyEditorLog.editor.debug(
                'CerebrumTableBlockComponentBuilder: child($i, $j) is not unique',
              );
              return false;
            }
          }
        }

        return true;
      };
}

class CerebrumTableStyle {
  final double colWidth;
  final double rowHeight;
  final double colMinimumWidth;
  final double borderWidth;
  final Widget addIcon;
  final Widget handlerIcon;
  final Color borderColor;
  final Color borderHoverColor;

  const CerebrumTableStyle({
    this.colWidth = 160,
    this.rowHeight = 40,
    this.colMinimumWidth = 40,
    this.borderWidth = 2,
    this.addIcon = CerebrumTableDefaults.addIcon,
    this.handlerIcon = CerebrumTableDefaults.handlerIcon,
    this.borderColor = CerebrumTableDefaults.borderColor,
    this.borderHoverColor = CerebrumTableDefaults.borderHoverColor,
  });
}

class CerebrumTableDefaults {
  const CerebrumTableDefaults._();

  static double colWidth = 160.0;

  static double rowHeight = 40.0;

  static double colMinimumWidth = 40.0;

  static double borderWidth = 2.0;

  static const Widget addIcon = Icon(Icons.add, size: 20);

  static const Widget handlerIcon = Icon(Icons.drag_indicator);

  static const Color borderColor = Colors.grey;

  static const Color borderHoverColor = Colors.blue;
}

typedef CerebrumTableBlockComponentMenuBuilder = Widget Function(
  Node,
  EditorState,
  int,
  TableDirection,
  VoidCallback?,
  VoidCallback?,
);

class CerebrumTableBlockComponentWidget extends BlockComponentStatefulWidget {
  const CerebrumTableBlockComponentWidget({
    super.key,
    required this.tableNode,
    required super.node,
    this.tableStyle = const CerebrumTableStyle(),
    this.menuBuilder,
    super.showActions,
    super.actionBuilder,
    super.actionTrailingBuilder,
    super.configuration = const BlockComponentConfiguration(),
  });

  final TableNode tableNode;

  final CerebrumTableBlockComponentMenuBuilder? menuBuilder;
  final CerebrumTableStyle tableStyle;

  @override
  State<CerebrumTableBlockComponentWidget> createState() =>
      _CerebrumTableBlockComponentWidgetState();
}

class _CerebrumTableBlockComponentWidgetState
    extends State<CerebrumTableBlockComponentWidget>
    with SelectableMixin, BlockComponentConfigurable {
  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  late final editorState = Provider.of<EditorState>(context, listen: false);
  final _scrollController = ScrollController();

  @override
  Widget build(BuildContext context) {
    Widget child = Scrollbar(
      controller: _scrollController,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(top: 10, left: 10, bottom: 4),
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        child: TableView(
          tableNode: widget.tableNode,
          editorState: editorState,
          menuBuilder: widget.menuBuilder,
          tableStyle: widget.tableStyle,
          tableAnchorKey: tableKey,
        ),
      ),
    );

    child = Padding(
      key: tableKey,
      padding: padding,
      child: child,
    );

    child = BlockSelectionContainer(
      node: node,
      delegate: this,
      listenable: editorState.selectionNotifier,
      remoteSelection: editorState.remoteSelections,
      blockColor: editorState.editorStyle.selectionColor,
      supportTypes: const [
        BlockSelectionType.block,
      ],
      child: child,
    );

    if (widget.showActions && widget.actionBuilder != null) {
      child = BlockComponentActionWrapper(
        node: node,
        actionBuilder: widget.actionBuilder!,
        actionTrailingBuilder: widget.actionTrailingBuilder,
        child: child,
      );
    }

    return child;
  }

  final tableKey = GlobalKey();

  RenderBox get _renderBox => context.findRenderObject() as RenderBox;

  @override
  Position start() => Position(path: widget.node.path, offset: 0);

  @override
  Position end() => Position(path: widget.node.path, offset: 1);

  @override
  Position getPositionInOffset(Offset start) => end();

  @override
  List<Rect> getRectsInSelection(
    Selection selection, {
    bool shiftWithBaseOffset = false,
  }) {
    final parentBox = context.findRenderObject();
    final tableBox = tableKey.currentContext?.findRenderObject();
    if (parentBox is RenderBox && tableBox is RenderBox) {
      return [
        (shiftWithBaseOffset
                ? tableBox.localToGlobal(Offset.zero, ancestor: parentBox)
                : Offset.zero) &
            tableBox.size,
      ];
    }
    return [Offset.zero & _renderBox.size];
  }

  @override
  Selection getSelectionInRange(Offset start, Offset end) => Selection.single(
        path: widget.node.path,
        startOffset: 0,
        endOffset: 1,
      );

  @override
  bool get shouldCursorBlink => false;

  @override
  CursorStyle get cursorStyle => CursorStyle.cover;

  @override
  Offset localToGlobal(
    Offset offset, {
    bool shiftWithBaseOffset = false,
  }) =>
      _renderBox.localToGlobal(offset);

  @override
  Rect getBlockRect({
    bool shiftWithBaseOffset = false,
  }) {
    return getRectsInSelection(Selection.invalid()).first;
  }

  @override
  Rect? getCursorRectInPosition(
    Position position, {
    bool shiftWithBaseOffset = false,
  }) {
    final size = _renderBox.size;
    return Rect.fromLTWH(-size.width / 2.0, 0, size.width, size.height);
  }
}