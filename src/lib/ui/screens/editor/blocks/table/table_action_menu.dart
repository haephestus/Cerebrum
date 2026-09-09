import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

import 'table_action.dart';
import 'table_overlay_util.dart';
import 'table_page_bounds.dart';

/// Fork of AppFlowy's table context menu. Difference from the original: every
/// ADD/DUP entry is guarded by the page bounds the forked table lives in, so
/// the "add column/row past the sheet" invariant holds for the context menu
/// exactly as it does for the + buttons.
///
/// NOTE: the original menu also has a "background color" item (its color
/// picker is package-internal and was not forked). That item is intentionally
/// absent here — see blocks/table/README.md for the diff list.
void showActionMenu(
  BuildContext context,
  Node node,
  EditorState editorState,
  int position,
  TableDirection dir, {
  TablePageBounds? pageBounds,
}) {
  final Offset pos =
      (context.findRenderObject() as RenderBox).localToGlobal(Offset.zero);
  final rect = Rect.fromLTWH(
    pos.dx,
    pos.dy,
    context.size?.width ?? 0,
    context.size?.height ?? 0,
  );
  OverlayEntry? overlay;

  var (top, bottom, left) = positionFromRect(rect, editorState);
  top = top != null ? top - 35 : top;

  void dismissOverlay() {
    overlay?.remove();
    overlay = null;
  }

  final tableNode = TableNode(node: node);

  overlay = FullScreenOverlayEntry(
    top: top,
    bottom: bottom,
    left: left,
    builder: (context) {
      return basicOverlay(
        context,
        width: 200,
        height: 200,
        children: [
          _menuItem(
              context,
              dir == TableDirection.col
                  ? AppFlowyEditorL10n.current.colAddBefore
                  : AppFlowyEditorL10n.current.rowAddBefore,
              dir == TableDirection.col
                  ? Icons.first_page
                  : Icons.vertical_align_top, () {
            if (_canAddRowOrCol(pageBounds, tableNode, position, dir)) {
              CerebrumTableActions.add(node, position, editorState, dir);
            }
            dismissOverlay();
          }),
          _menuItem(
              context,
              dir == TableDirection.col
                  ? AppFlowyEditorL10n.current.colAddAfter
                  : AppFlowyEditorL10n.current.rowAddAfter,
              dir == TableDirection.col
                  ? Icons.last_page
                  : Icons.vertical_align_bottom, () {
            if (_canAddRowOrCol(pageBounds, tableNode, position + 1, dir)) {
              CerebrumTableActions.add(node, position + 1, editorState, dir);
            }
            dismissOverlay();
          }),
          _menuItem(
              context,
              dir == TableDirection.col
                  ? AppFlowyEditorL10n.current.colRemove
                  : AppFlowyEditorL10n.current.rowRemove,
              Icons.delete, () {
            CerebrumTableActions.delete(node, position, editorState, dir);
            dismissOverlay();
          }),
          _menuItem(
              context,
              dir == TableDirection.col
                  ? AppFlowyEditorL10n.current.colDuplicate
                  : AppFlowyEditorL10n.current.rowDuplicate,
              Icons.content_copy, () {
            // Duplicating a column/row also GROWS the table — apply the same
            // page-bounds guard (the copy mirrors the existing col/row size).
            if (_canAddRowOrCol(pageBounds, tableNode, position, dir)) {
              CerebrumTableActions.duplicate(node, position, editorState, dir);
            }
            dismissOverlay();
          }),
          _menuItem(
              context,
              dir == TableDirection.col
                  ? AppFlowyEditorL10n.current.colClear
                  : AppFlowyEditorL10n.current.rowClear,
              Icons.clear, () {
            CerebrumTableActions.clear(node, position, editorState, dir);
            dismissOverlay();
          }),
        ],
      );
    },
  ).build();
  Overlay.of(context, rootOverlay: true).insert(overlay!);
}

/// True when adding/duplicating a col/row at [position] keeps the table within
/// the page. Null bounds (no paged context) → always allowed.
bool _canAddRowOrCol(
  TablePageBounds? bounds,
  TableNode tableNode,
  int position,
  TableDirection dir,
) {
  if (bounds == null) return true;
  if (dir == TableDirection.col) {
    // A new column mirrors the existing column's width (add/duplicate before
    // an existing position) or the table default (add at the very end).
    final newWidth = position < tableNode.colsLen
        ? tableNode.getColWidth(position)
        : tableNode.config.colDefaultWidth;
    return bounds.canAddCol(
      tableWidth: tableNode.tableWidth,
      newColWidth: newWidth,
    );
  }
  final newHeight = position < tableNode.rowsLen
      ? tableNode.getRowHeight(position)
      : tableNode.config.rowDefaultHeight;
  return bounds.canAddRow(
    colsHeight: tableNode.colsHeight,
    newRowHeight: newHeight,
    borderWidth: tableNode.config.borderWidth,
  );
}

Widget _menuItem(
  BuildContext context,
  String text,
  IconData icon,
  Function() action,
) {
  return SizedBox(
    height: 36,
    child: TextButton.icon(
      onPressed: () {
        action();
      },
      icon: Icon(icon, color: Theme.of(context).iconTheme.color),
      style: buildOverlayButtonStyle(context),
      label: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              text,
              softWrap: false,
              maxLines: 1,
              overflow: TextOverflow.fade,
              style: TextStyle(
                color: Theme.of(context).textTheme.labelLarge?.color,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}