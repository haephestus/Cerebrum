import 'dart:math' as math;

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'table_keys.dart';
import 'table_page_bounds.dart';

/// Fork of AppFlowy's `TableColBorder` with ONE difference: dragging a column
/// wider clamps against the sheet's content width, so a table can't be resized
/// past the page boundary the way the stock editor lets it.
class TableColBorder extends StatefulWidget {
  const TableColBorder({
    super.key,
    required this.tableNode,
    required this.editorState,
    required this.colIdx,
    required this.resizable,
    required this.borderColor,
    required this.borderHoverColor,
  });

  final bool resizable;
  final int colIdx;
  final TableNode tableNode;
  final EditorState editorState;

  final Color borderColor;
  final Color borderHoverColor;

  @override
  State<TableColBorder> createState() => _TableColBorderState();
}

class _TableColBorderState extends State<TableColBorder> {
  final GlobalKey _borderKey = GlobalKey();
  bool _borderHovering = false;
  bool _borderDragging = false;

  Offset initialOffset = const Offset(0, 0);

  @override
  Widget build(BuildContext context) {
    return widget.resizable
        ? buildResizableBorder(context)
        : buildFixedBorder(context);
  }

  MouseRegion buildResizableBorder(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      onEnter: (_) => setState(() => _borderHovering = true),
      onExit: (_) => setState(() => _borderHovering = false),
      child: GestureDetector(
        onHorizontalDragStart: (DragStartDetails details) {
          setState(() => _borderDragging = true);
          initialOffset = details.globalPosition;
        },
        onHorizontalDragEnd: (_) {
          final transaction = widget.editorState.transaction;
          widget.tableNode.setColWidth(
            widget.colIdx,
            widget.tableNode.getColWidth(widget.colIdx),
            transaction: transaction,
            force: true,
          );
          transaction.afterSelection = transaction.beforeSelection;
          widget.editorState.apply(transaction);
          setState(() => _borderDragging = false);
        },
        onHorizontalDragUpdate: (DragUpdateDetails details) {
          final colWidth = widget.tableNode.getColWidth(widget.colIdx);
          var nextWidth = colWidth + details.delta.dx;
          // Page-bounds clamp: the whole row (all columns + add button) must
          // stay within the sheet. Null bounds (no paged context) → no clamp.
          final bounds = snapshotTablePageBounds(context);
          final maxWidth = bounds?.maxResizedColWidth(
            tableWidth: widget.tableNode.tableWidth,
            colWidth: colWidth,
          );
          if (maxWidth != null) {
            nextWidth = math.min(nextWidth, maxWidth);
          }
          widget.tableNode.setColWidth(widget.colIdx, nextWidth);
        },
        child: Container(
          key: _borderKey,
          width: widget.tableNode.config.borderWidth,
          height: context.select(
            (Node n) => n.attributes[CerebrumTableBlockKeys.colsHeight],
          ),
          color: _borderHovering || _borderDragging
              ? widget.borderHoverColor
              : widget.borderColor,
        ),
      ),
    );
  }

  Container buildFixedBorder(BuildContext context) {
    return Container(
      width: widget.tableNode.config.borderWidth,
      height: context.select(
        (Node n) => n.attributes[CerebrumTableBlockKeys.colsHeight],
      ),
      color: Colors.grey,
    );
  }
}