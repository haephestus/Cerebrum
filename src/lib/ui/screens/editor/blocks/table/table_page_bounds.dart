import 'package:flutter/widgets.dart';

/// The page's sheet geometry, provided by PageSurface to widgets deep inside
/// the page's editor (e.g. the forked table block) so they can bound their own
/// growth against the A4 sheet instead of letting the page become scrollable.
///
/// Only a [GlobalKey] to the sheet's Stack is carried — the actual sheet size
/// and the table's offset within it are measured at INTERACTION time (a tap on
/// a + button, a column drag) from the key's render boxes, so there is no
/// layout-time coupling and no extra rebuilds. A widget with no ancestor
/// [PagedTableBounds] is not inside a page (rare) and behaves like the stock
/// AppFlowy table (no caps; the overflow splitter is still the backstop).
class PagedTableBounds extends InheritedWidget {
  const PagedTableBounds({
    super.key,
    required this.sheetKey,
    required super.child,
  });

  final GlobalKey sheetKey;

  static PagedTableBounds? maybeOf(BuildContext context) => context
      .getInheritedWidgetOfExactType<PagedTableBounds>();

  @override
  bool updateShouldNotify(PagedTableBounds oldWidget) =>
      sheetKey != oldWidget.sheetKey;
}

/// A snapshot of the page geometry a table can grow into, taken right before an
/// add/resize action runs. Null fields mean "unknown / not in a paged context"
/// — the caller then falls back to the stock behaviour (and the overflow
/// splitter still enforces the page bound on row growth).
class TablePageBounds {
  const TablePageBounds({
    this.sheetWidth,
    this.sheetHeight,
    this.tableTop,
  });

  final double? sheetWidth;
  final double? sheetHeight;

  /// The table block's top edge, measured from the sheet's top.
  final double? tableTop;

  /// Chrome that renders around the row/column grid inside the table block:
  /// the add-row button (28px) sits below the rows, and the add-col button
  /// (28px) sits to the right of the last column. Kept in sync with
  /// table_block_component.dart / table_view.dart.
  static const double addButtonSize = 28.0;

  bool get isBounded => sheetWidth != null || sheetHeight != null;

  /// True when adding a column of [newColWidth] keeps the table row
  /// (columns + add button) within the sheet's content width.
  bool canAddCol({
    required double tableWidth,
    required double newColWidth,
  }) {
    final w = sheetWidth;
    if (w == null) return true;
    return tableWidth + newColWidth + addButtonSize <= w;
  }

  /// True when adding a row of [newRowHeight] (plus its border) keeps the whole
  /// table block within the sheet's height: the table starts at [tableTop],
  /// currently renders [colsHeight] of rows, and the + button chrome follows.
  bool canAddRow({
    required double colsHeight,
    required double newRowHeight,
    required double borderWidth,
  }) {
    final h = sheetHeight;
    final top = tableTop;
    if (h == null || top == null) return true; // no vertical bound available
    return top + colsHeight + newRowHeight + borderWidth + addButtonSize <= h;
  }

  /// The widest [colWidth] can grow to without the whole row (all columns +
  /// add button) exceeding the sheet's content width.
  double? maxResizedColWidth({
    required double tableWidth,
    required double colWidth,
  }) {
    final w = sheetWidth;
    if (w == null) return null;
    return (w - addButtonSize - (tableWidth - colWidth)).clamp(
      colWidth,
      double.infinity,
    );
  }
}

/// Snapshot the page bounds for a table anchored by [tableAnchorKey] (the
/// block widget's table Key, see table_block_component.dart). Reads
/// [PagedTableBounds] from [context]'s ancestors; the sheet's render box is
/// looked up live, so this is only meaningful inside a laid-out page.
TablePageBounds? snapshotTablePageBounds(
  BuildContext context, {
  GlobalKey? tableAnchorKey,
}) {
  final bounds = PagedTableBounds.maybeOf(context);
  if (bounds == null) return null;
  final sheet = bounds.sheetKey.currentContext?.findRenderObject();
  if (sheet is! RenderBox || !sheet.hasSize) return null;

  double? top;
  final anchor = tableAnchorKey?.currentContext?.findRenderObject();
  if (anchor is RenderBox && anchor.hasSize) {
    top = sheet.globalToLocal(anchor.localToGlobal(Offset.zero)).dy;
  }

  return TablePageBounds(
    sheetWidth: sheet.size.width,
    sheetHeight: sheet.size.height,
    tableTop: top,
  );
}