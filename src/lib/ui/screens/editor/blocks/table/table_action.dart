import 'package:appflowy_editor/appflowy_editor.dart';

import 'table_keys.dart';
import 'table_util.dart';

/// Fork of AppFlowy's `TableActions` (renamed to CerebrumTableActions so it doesn't clash with the 6.0.0 barrel, which now exports the stock one). Behaviour is identical to the original —
/// the page-bounds guards live at the CALL SITES (the + buttons in
/// [TableView] and the context menu), which snapshot [TablePageBounds] at
/// interaction time and simply don't invoke `add` when the new column/row
/// would push the table past the sheet.
class CerebrumTableActions {
  const CerebrumTableActions._();

  static void add(
    Node node,
    int position,
    EditorState editorState,
    TableDirection dir,
  ) {
    if (dir == TableDirection.col) {
      _addCol(node, position, editorState);
    } else {
      _addRow(node, position, editorState);
    }
  }

  static void delete(
    Node node,
    int position,
    EditorState editorState,
    TableDirection dir,
  ) {
    if (dir == TableDirection.col) {
      _deleteCol(node, position, editorState);
    } else {
      _deleteRow(node, position, editorState);
    }
  }

  static void duplicate(
    Node node,
    int position,
    EditorState editorState,
    TableDirection dir,
  ) {
    if (dir == TableDirection.col) {
      _duplicateCol(node, position, editorState);
    } else {
      _duplicateRow(node, position, editorState);
    }
  }

  static void clear(
    Node node,
    int position,
    EditorState editorState,
    TableDirection dir,
  ) {
    if (dir == TableDirection.col) {
      _clearCol(node, position, editorState);
    } else {
      _clearRow(node, position, editorState);
    }
  }

  static void setBgColor(
    Node node,
    int position,
    EditorState editorState,
    String? color,
    TableDirection dir,
  ) {
    if (dir == TableDirection.col) {
      _setColBgColor(node, position, editorState, color);
    } else {
      _setRowBgColor(node, position, editorState, color);
    }
  }
}

void _addCol(Node tableNode, int position, EditorState editorState) {
  assert(position >= 0);

  final transaction = editorState.transaction;

  List<Node> cellNodes = [];
  final int rowsLen = tableNode.attributes[CerebrumTableBlockKeys.rowsLen],
      colsLen = tableNode.attributes[CerebrumTableBlockKeys.colsLen];

  if (position != colsLen) {
    for (var i = position; i < colsLen; i++) {
      for (var j = 0; j < rowsLen; j++) {
        final node = getCellNode(tableNode, i, j)!;
        transaction.updateNode(node, {
          CerebrumTableCellKeys.colPosition: i + 1,
        });
      }
    }
  }

  for (var i = 0; i < rowsLen; i++) {
    final node = Node(
      type: CerebrumTableCellKeys.type,
      attributes: {
        CerebrumTableCellKeys.colPosition: position,
        CerebrumTableCellKeys.rowPosition: i,
      },
    );
    node.insert(paragraphNode());
    final firstCellInRow = getCellNode(tableNode, 0, i);
    if (firstCellInRow?.attributes
            .containsKey(CerebrumTableCellKeys.rowBackgroundColor) ??
        false) {
      node.updateAttributes({
        CerebrumTableCellKeys.rowBackgroundColor:
            firstCellInRow!.attributes[
                CerebrumTableCellKeys.rowBackgroundColor],
      });
    }

    cellNodes.add(newCellNode(tableNode, node));
  }

  late Path insertPath;
  if (position == 0) {
    insertPath = getCellNode(tableNode, 0, 0)!.path;
  } else {
    insertPath = getCellNode(tableNode, position - 1, rowsLen - 1)!.path.next;
  }
  transaction.insertNodes(insertPath, cellNodes);
  transaction.updateNode(tableNode, {
    CerebrumTableBlockKeys.colsLen: colsLen + 1,
  });

  editorState.apply(transaction, withUpdateSelection: false);
}

void _addRow(Node tableNode, int position, EditorState editorState) async {
  assert(position >= 0);

  final int rowsLen = tableNode.attributes[CerebrumTableBlockKeys.rowsLen];
  final int colsLen = tableNode.attributes[CerebrumTableBlockKeys.colsLen];

  // insert new rows
  var error = false;

  // generate new table cell nodes & update node attributes
  for (var i = 0; i < colsLen; i++) {
    final firstCellInCol = getCellNode(tableNode, i, 0);
    final colBgColor =
        firstCellInCol?.attributes[CerebrumTableCellKeys.colBackgroundColor];
    final containsColBgColor = colBgColor != null;

    final node = Node(
      type: CerebrumTableCellKeys.type,
      attributes: {
        CerebrumTableCellKeys.colPosition: i,
        CerebrumTableCellKeys.rowPosition: position,
        if (containsColBgColor)
          CerebrumTableCellKeys.colBackgroundColor: colBgColor,
      },
      children: [paragraphNode()],
    );

    late Path insertPath;
    if (position == 0) {
      final firstCellInCol = getCellNode(tableNode, i, 0);
      if (firstCellInCol == null) {
        error = true;
        break;
      }
      insertPath = firstCellInCol.path;
    } else {
      final cellInPrevRow = getCellNode(tableNode, i, position - 1);
      if (cellInPrevRow == null) {
        error = true;
        break;
      }
      insertPath = cellInPrevRow.path.next;
    }

    final transaction = editorState.transaction;

    if (position != rowsLen) {
      for (var j = position; j < rowsLen; j++) {
        final cellNode = getCellNode(tableNode, i, j);
        if (cellNode == null) {
          error = true;
          break;
        }
        transaction.updateNode(
          cellNode,
          {
            CerebrumTableCellKeys.rowPosition: j + 1,
          },
        );
      }
    }

    transaction.insertNode(insertPath, node);

    await editorState.apply(transaction, withUpdateSelection: false);
  }

  if (error) {
    AppFlowyEditorLog.editor.debug('unable to insert row');
    return;
  }

  final transaction = editorState.transaction;

  // update the row length
  transaction.updateNode(tableNode, {
    CerebrumTableBlockKeys.rowsLen: rowsLen + 1,
  });

  await editorState.apply(transaction, withUpdateSelection: false);
}

void _deleteCol(Node tableNode, int col, EditorState editorState) {
  final transaction = editorState.transaction;

  final int rowsLen = tableNode.attributes[CerebrumTableBlockKeys.rowsLen],
      colsLen = tableNode.attributes[CerebrumTableBlockKeys.colsLen];

  if (colsLen == 1) {
    if (editorState.document.root.children.length == 1) {
      final emptyParagraph = paragraphNode();
      transaction.insertNode(tableNode.path, emptyParagraph);
    }
    transaction.deleteNode(tableNode);
    tableNode.dispose();
  } else {
    List<Node> nodes = [];
    for (var i = 0; i < rowsLen; i++) {
      nodes.add(getCellNode(tableNode, col, i)!);
    }
    transaction.deleteNodes(nodes);

    _updateCellPositions(tableNode, editorState, col + 1, 0, -1, 0);

    transaction.updateNode(tableNode, {
      CerebrumTableBlockKeys.colsLen: colsLen - 1,
    });
  }

  editorState.apply(transaction, withUpdateSelection: false);
}

void _deleteRow(Node tableNode, int row, EditorState editorState) {
  final transaction = editorState.transaction;

  final int rowsLen = tableNode.attributes[CerebrumTableBlockKeys.rowsLen],
      colsLen = tableNode.attributes[CerebrumTableBlockKeys.colsLen];

  if (rowsLen == 1) {
    if (editorState.document.root.children.length == 1) {
      final emptyParagraph = paragraphNode();
      transaction.insertNode(tableNode.path, emptyParagraph);
    }
    transaction.deleteNode(tableNode);
    tableNode.dispose();
  } else {
    List<Node> nodes = [];
    for (var i = 0; i < colsLen; i++) {
      nodes.add(getCellNode(tableNode, i, row)!);
    }
    transaction.deleteNodes(nodes);

    _updateCellPositions(tableNode, editorState, 0, row + 1, 0, -1);

    transaction.updateNode(tableNode, {
      CerebrumTableBlockKeys.rowsLen: rowsLen - 1,
    });
  }

  editorState.apply(transaction, withUpdateSelection: false);
}

void _duplicateCol(Node tableNode, int col, EditorState editorState) {
  final transaction = editorState.transaction;

  final int rowsLen = tableNode.attributes[CerebrumTableBlockKeys.rowsLen],
      colsLen = tableNode.attributes[CerebrumTableBlockKeys.colsLen];
  List<Node> nodes = [];
  for (var i = 0; i < rowsLen; i++) {
    final node = getCellNode(tableNode, col, i)!;
    nodes.add(
      node.copyWith(
        attributes: {
          ...node.attributes,
          CerebrumTableCellKeys.colPosition: col + 1,
          CerebrumTableCellKeys.rowPosition: i,
        },
      ),
    );
  }
  transaction.insertNodes(
    getCellNode(tableNode, col, rowsLen - 1)!.path.next,
    nodes,
  );

  _updateCellPositions(tableNode, editorState, col + 1, 0, 1, 0);

  transaction.updateNode(tableNode, {CerebrumTableBlockKeys.colsLen: colsLen + 1});

  editorState.apply(transaction, withUpdateSelection: false);
}

void _duplicateRow(Node tableNode, int row, EditorState editorState) async {
  Transaction transaction = editorState.transaction;
  _updateCellPositions(tableNode, editorState, 0, row + 1, 0, 1);
  await editorState.apply(transaction, withUpdateSelection: false);

  final int rowsLen = tableNode.attributes[CerebrumTableBlockKeys.rowsLen],
      colsLen = tableNode.attributes[CerebrumTableBlockKeys.colsLen];
  for (var i = 0; i < colsLen; i++) {
    final node = getCellNode(tableNode, i, row)!;
    transaction = editorState.transaction;
    transaction.insertNode(
      node.path.next,
      node.copyWith(
        attributes: {
          ...node.attributes,
          CerebrumTableCellKeys.rowPosition: row + 1,
          CerebrumTableCellKeys.colPosition: i,
        },
      ),
    );
    await editorState.apply(transaction, withUpdateSelection: false);
  }

  transaction = editorState.transaction;
  transaction.updateNode(tableNode, {CerebrumTableBlockKeys.rowsLen: rowsLen + 1});
  editorState.apply(transaction, withUpdateSelection: false);
}

void _setColBgColor(
  Node tableNode,
  int col,
  EditorState editorState,
  String? color,
) {
  final transaction = editorState.transaction;

  final rowslen = tableNode.attributes[CerebrumTableBlockKeys.rowsLen];
  for (var i = 0; i < rowslen; i++) {
    final node = getCellNode(tableNode, col, i)!;
    transaction.updateNode(
      node,
      {CerebrumTableCellKeys.colBackgroundColor: color},
    );
  }

  editorState.apply(transaction, withUpdateSelection: false);
}

void _setRowBgColor(
  Node tableNode,
  int row,
  EditorState editorState,
  String? color,
) {
  final transaction = editorState.transaction;

  final colsLen = tableNode.attributes[CerebrumTableBlockKeys.colsLen];
  for (var i = 0; i < colsLen; i++) {
    final node = getCellNode(tableNode, i, row)!;
    transaction.updateNode(
      node,
      {CerebrumTableCellKeys.rowBackgroundColor: color},
    );
  }

  editorState.apply(transaction, withUpdateSelection: false);
}

void _clearCol(
  Node tableNode,
  int col,
  EditorState editorState,
) {
  final transaction = editorState.transaction;

  final rowsLen = tableNode.attributes[CerebrumTableBlockKeys.rowsLen];
  for (var i = 0; i < rowsLen; i++) {
    final node = getCellNode(tableNode, col, i)!;
    transaction.insertNode(
      node.children.first.path,
      paragraphNode(text: ''),
    );
  }

  editorState.apply(transaction, withUpdateSelection: false);
}

void _clearRow(
  Node tableNode,
  int row,
  EditorState editorState,
) {
  final transaction = editorState.transaction;

  final colsLen = tableNode.attributes[CerebrumTableBlockKeys.colsLen];
  for (var i = 0; i < colsLen; i++) {
    final node = getCellNode(tableNode, i, row)!;
    transaction.insertNode(
      node.children.first.path,
      paragraphNode(text: ''),
    );
  }

  editorState.apply(transaction, withUpdateSelection: false);
}

dynamic newCellNode(Node tableNode, n) {
  final row = n.attributes[CerebrumTableCellKeys.rowPosition] as int;
  final col = n.attributes[CerebrumTableCellKeys.colPosition] as int;
  final int rowsLen = tableNode.attributes[CerebrumTableBlockKeys.rowsLen];
  final int colsLen = tableNode.attributes[CerebrumTableBlockKeys.colsLen];

  if (!n.attributes.containsKey(CerebrumTableCellKeys.height)) {
    double nodeHeight = double.tryParse(
      tableNode.attributes[CerebrumTableBlockKeys.rowDefaultHeight].toString(),
    )!;
    if (row < rowsLen) {
      nodeHeight = double.tryParse(
            getCellNode(tableNode, 0, row)!
                .attributes[CerebrumTableCellKeys.height]
                .toString(),
          ) ??
          nodeHeight;
    }
    n.updateAttributes({CerebrumTableCellKeys.height: nodeHeight});
  }

  if (!n.attributes.containsKey(CerebrumTableCellKeys.width)) {
    double nodeWidth = double.tryParse(
      tableNode.attributes[CerebrumTableBlockKeys.colDefaultWidth].toString(),
    )!;
    if (col < colsLen) {
      nodeWidth = double.tryParse(
            getCellNode(tableNode, col, 0)!
                .attributes[CerebrumTableCellKeys.width]
                .toString(),
          ) ??
          nodeWidth;
    }
    n.updateAttributes({CerebrumTableCellKeys.width: nodeWidth});
  }

  return n;
}

void _updateCellPositions(
  Node tableNode,
  EditorState editorState,
  int fromCol,
  int fromRow,
  int addToCol,
  int addToRow,
) {
  final transaction = editorState.transaction;

  final int rowsLen = tableNode.attributes[CerebrumTableBlockKeys.rowsLen],
      colsLen = tableNode.attributes[CerebrumTableBlockKeys.colsLen];

  for (var i = fromCol; i < colsLen; i++) {
    for (var j = fromRow; j < rowsLen; j++) {
      transaction.updateNode(getCellNode(tableNode, i, j)!, {
        CerebrumTableCellKeys.colPosition: i + addToCol,
        CerebrumTableCellKeys.rowPosition: j + addToRow,
      });
    }
  }

  editorState.apply(transaction, withUpdateSelection: false);
}