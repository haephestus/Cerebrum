/// Fork of AppFlowy's table block: the page-bounds guards live here.
///
/// The cells themselves are still rendered by the package's own
/// `TableCellBlockComponentBuilder` (registered in standardBlockComponentBuilderMap),
/// so these keys MUST stay byte-identical to the package's constants — the
/// document JSON interchanges between the two. They're plain string literals
/// either way.
class CerebrumTableBlockKeys {
  const CerebrumTableBlockKeys._();

  static const String type = 'table';

  static const String colDefaultWidth = 'colDefaultWidth';

  static const String rowDefaultHeight = 'rowDefaultHeight';

  static const String colMinimumWidth = 'colMinimumWidth';

  static const String borderWidth = 'borderWidth';

  static const String colsLen = 'colsLen';

  static const String rowsLen = 'rowsLen';

  static const String colsHeight = 'colsHeight';
}

class CerebrumTableCellKeys {
  const CerebrumTableCellKeys._();

  static const String type = 'table/cell';

  static const String rowPosition = 'rowPosition';

  static const String colPosition = 'colPosition';

  static const String height = 'height';

  static const String width = 'width';

  static const String rowBackgroundColor = 'rowBackgroundColor';

  static const String colBackgroundColor = 'colBackgroundColor';
}