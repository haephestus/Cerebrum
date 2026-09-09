import 'package:appflowy_editor/appflowy_editor.dart';

import 'table_block_component.dart';
import 'table_keys.dart';

Node? getCellNode(Node tableNode, int col, int row) {
  for (final n in tableNode.children) {
    if (n.attributes[CerebrumTableCellKeys.colPosition] == col &&
        n.attributes[CerebrumTableCellKeys.rowPosition] == row) {
      return n;
    }
  }
  return null;
}

extension CerebrumTableCellNodeDynamicExtension on dynamic {
  double toDouble({double defaultValue = 0.0}) {
    if (this is int) {
      return this.toDouble();
    } else if (this is double) {
      return this;
    } else {
      return double.tryParse(toString()) ?? defaultValue;
    }
  }
}

extension CerebrumTableCellNodeAttributesExtension on Node {
  double get cellWidth {
    assert(type == CerebrumTableCellKeys.type);
    return attributes[CerebrumTableCellKeys.width]?.toDouble() ??
        CerebrumTableDefaults.colWidth;
  }

  double get cellHeight {
    assert(type == CerebrumTableCellKeys.type);
    return attributes[CerebrumTableCellKeys.height]?.toDouble() ??
        CerebrumTableDefaults.rowHeight;
  }

  double get colHeight {
    assert(type == CerebrumTableBlockKeys.type);
    return attributes[CerebrumTableBlockKeys.colsHeight]?.toDouble() ??
        CerebrumTableDefaults.rowHeight;
  }
}