import 'package:flutter/foundation.dart';

/// Selection state for a linear (1-D) list of navigable items.
///
/// Holds a focused/selected index and clamps movement to `[0, itemCount)`.
/// Pages wire activation, scrolling, and "what is itemCount right now" to
/// this controller; the controller itself does not know about widgets.
///
/// Use for sidebars, vertical lists, and single-row strips. For 2-D layouts
/// (responsive grids) use `GridNavController`.
class LinearNavController extends ChangeNotifier {
  LinearNavController({int index = 0, int itemCount = 0})
    : _index = index,
      _itemCount = itemCount;

  int _index;
  int _itemCount;
  bool _enabled = true;

  int get index => _index;
  int get itemCount => _itemCount;
  bool get enabled => _enabled;

  /// No selectable items.
  bool get isEmpty => _itemCount <= 0;

  set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    notifyListeners();
  }

  /// Update the item count (e.g. after async load/filter). Clamps [index].
  void setItemCount(int count) {
    if (count < 0) count = 0;
    if (_itemCount == count) return;
    _itemCount = count;
    _clampIndex(notifyIfChanged: true);
  }

  /// Set selection directly (e.g. mouse/tap sync). Clamped when count > 0.
  void setIndex(int value) {
    final next = _clamp(value);
    if (_index == next) return;
    _index = next;
    notifyListeners();
  }

  void move(int delta) {
    if (!_enabled || isEmpty) return;
    setIndex(_index + delta);
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

  void _clampIndex({required bool notifyIfChanged}) {
    final next = _clamp(_index);
    if (_index == next) return;
    _index = next;
    if (notifyIfChanged) notifyListeners();
  }
}
