import 'package:flutter/foundation.dart';

/// Selection state for a 2-D grid of navigable items laid out in row-major
/// order (index 0..itemCount-1, left-to-right then top-to-bottom).
///
/// Column count is supplied by the page from its layout (e.g. the same
/// responsive column calculation used by the `GridView`) so movement matches
/// what the user sees. When [columnCount] changes (resize), call
/// [setLayout]; the index is clamped, not re-mapped by row/col, to avoid
/// surprising jumps.
///
/// Use `LinearNavController` for 1-D surfaces.
class GridNavController extends ChangeNotifier {
  GridNavController({int index = 0, int itemCount = 0, int columnCount = 1})
    : _index = index,
      _itemCount = itemCount,
      _columnCount = columnCount < 1 ? 1 : columnCount;

  int _index;
  int _itemCount;
  int _columnCount;
  bool _enabled = true;

  int get index => _index;
  int get itemCount => _itemCount;
  int get columnCount => _columnCount;
  bool get enabled => _enabled;

  bool get isEmpty => _itemCount <= 0;

  int get row => isEmpty ? 0 : _index ~/ _columnCount;
  int get col => isEmpty ? 0 : _index % _columnCount;
  int get rowCount => isEmpty ? 0 : ((_itemCount - 1) ~/ _columnCount) + 1;

  set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    notifyListeners();
  }

  /// Update item/column counts together (typical on rebuild/filter/resize).
  void setLayout({required int itemCount, required int columnCount}) {
    if (itemCount < 0) itemCount = 0;
    if (columnCount < 1) columnCount = 1;
    final changed = _itemCount != itemCount || _columnCount != columnCount;
    _itemCount = itemCount;
    _columnCount = columnCount;
    final next = _clamp(_index);
    if (_index != next) {
      _index = next;
      notifyListeners();
      return;
    }
    if (changed) {
      // Count/shape changed even if clamped index didn't; listeners that
      // derive row/col or scroll targets may need to react.
      notifyListeners();
    }
  }

  void setItemCount(int count) =>
      setLayout(itemCount: count, columnCount: _columnCount);

  void setIndex(int value) {
    final next = _clamp(value);
    if (_index == next) return;
    _index = next;
    notifyListeners();
  }

  void moveLeft() => moveHorizontal(-1);
  void moveRight() => moveHorizontal(1);
  void moveUp() => moveVertical(-1);
  void moveDown() => moveVertical(1);

  void moveHorizontal(int delta) {
    if (!_enabled || isEmpty) return;
    setIndex(_index + delta);
  }

  void moveVertical(int rowDelta) {
    if (!_enabled || isEmpty) return;
    final target = _index + rowDelta * _columnCount;
    // Moving past the last (possibly partial) row clamps to the last item
    // rather than jumping to an invalid cell.
    setIndex(target);
  }

  void first() {
    if (!_enabled || isEmpty) return;
    setIndex(0);
  }

  void last() {
    if (!_enabled || isEmpty) return;
    setIndex(_itemCount - 1);
  }

  int _clamp(int value) {
    if (isEmpty) return 0;
    return value.clamp(0, _itemCount - 1);
  }
}
