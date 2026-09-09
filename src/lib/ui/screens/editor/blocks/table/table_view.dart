import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

import 'table_action.dart';
import 'table_add_button.dart';
import 'table_block_component.dart';
import 'table_col.dart';
import 'table_page_bounds.dart';

/// Fork of AppFlowy's `TableView` with page-bounds guards on the + buttons:
///  * add-column is a no-op when the new column would push the row (columns +
///    add button) past the sheet's content width;
///  * add-row is a no-op when the new row would push the whole table block past
///    the sheet's bottom (measured live against the page at tap time).
/// If the table isn't inside a paged sheet (no PagedTableBounds ancestor), the
/// guards are skipped and the fork behaves like the stock table — the overflow
/// splitter (helpers/table_splitter.dart) remains the correctness backstop for
/// row growth either way.
class TableView extends StatefulWidget {
  const TableView({
    super.key,
    required this.editorState,
    required this.tableNode,
    required this.tableStyle,
    this.menuBuilder,
    this.tableAnchorKey,
  });

  final EditorState editorState;
  final TableNode tableNode;
  final GlobalKey? tableAnchorKey;

  final CerebrumTableBlockComponentMenuBuilder? menuBuilder;
  final CerebrumTableStyle tableStyle;

  @override
  State<TableView> createState() => _TableViewState();
}

class _TableViewState extends State<TableView> {
  TablePageBounds? get _pageBounds =>
      snapshotTablePageBounds(context, tableAnchorKey: widget.tableAnchorKey);

  bool _canAddColumn() {
    final bounds = _pageBounds;
    if (bounds == null) {
      return true; // no paged context → stock behaviour
    }
    final tn = widget.tableNode;
    return bounds.canAddCol(
      tableWidth: tn.tableWidth,
      newColWidth: tn.config.colDefaultWidth,
    );
  }

  bool _canAddRow() {
    final bounds = _pageBounds;
    if (bounds == null) {
      return true; // no paged context → stock behaviour
    }
    final tn = widget.tableNode;
    return bounds.canAddRow(
      colsHeight: tn.colsHeight,
      newRowHeight: tn.config.rowDefaultHeight,
      borderWidth: tn.config.borderWidth,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Column(
          children: [
            Row(
              children: [
                ..._buildColumns(context),
                TableActionButton(
                  padding: const EdgeInsets.only(left: 0),
                  icon: widget.tableStyle.addIcon,
                  width: 28,
                  height: widget.tableNode.colsHeight,
                  onPressed: () {
                    if (_canAddColumn()) {
                      CerebrumTableActions.add(
                        widget.tableNode.node,
                        widget.tableNode.colsLen,
                        widget.editorState,
                        TableDirection.col,
                      );
                    }
                  },
                ),
              ],
            ),
            TableActionButton(
              padding: const EdgeInsets.only(top: 1, right: 30),
              icon: widget.tableStyle.addIcon,
              height: 28,
              width: widget.tableNode.tableWidth,
              onPressed: () {
                if (_canAddRow()) {
                  CerebrumTableActions.add(
                    widget.tableNode.node,
                    widget.tableNode.rowsLen,
                    widget.editorState,
                    TableDirection.row,
                  );
                }
              },
            ),
          ],
        ),
      ],
    );
  }

  List<Widget> _buildColumns(BuildContext context) {
    return List.generate(
      widget.tableNode.colsLen,
      (i) => TableCol(
        colIdx: i,
        editorState: widget.editorState,
        tableNode: widget.tableNode,
        menuBuilder: widget.menuBuilder,
        tableStyle: widget.tableStyle,
        tableAnchorKey: widget.tableAnchorKey,
      ),
    );
  }
}