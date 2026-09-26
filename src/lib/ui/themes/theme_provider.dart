import 'package:cerebrum/models/theme_family.dart';
import 'package:cerebrum/ui/themes/default.dart';
import 'package:cerebrum/ui/themes/gruvbox.dart';
import 'package:cerebrum/ui/themes/tokyo_night.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Owns the active theme family and brightness, and persists both.
///
/// Themes are registered as [ThemeFamily] entries. To add one, drop a
/// `buildDefaultTheme`-shaped file next to `default.dart` and list it in
/// [families]; the provider needs no changes.
class ThemeProvider extends ChangeNotifier {
  ThemeProvider({List<ThemeFamily>? families})
    : families = List.unmodifiable(
        families ??
            [defaultThemeFamily, gruvboxThemeFamily, tokyoNightThemeFamily],
      );

  /// Every selectable theme, in display order. Never empty.
  final List<ThemeFamily> families;

  static const _kSelectedTheme = 'selected_theme';
  static const _kDarkMode = 'dark_mode';

  String _selectedThemeId = defaultThemeFamily.id;
  bool _darkMode = false;

  String get selectedThemeId => _selectedThemeId;
  bool get darkMode => _darkMode;

  /// The family for [id], falling back to the first registered family when
  /// [id] is unknown.
  ///
  /// A persisted id can outlive its family -- the theme was renamed or
  /// removed between launches -- so this must never throw.
  ThemeFamily familyFor(String id) =>
      families.firstWhere((f) => f.id == id, orElse: () => families.first);

  /// The [ThemeData] for [id] at the current brightness.
  ThemeData themeFor(String id) =>
      _darkMode ? familyFor(id).dark : familyFor(id).light;

  /// The active theme.
  ThemeData get theme => themeFor(_selectedThemeId);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final storedId = prefs.getString(_kSelectedTheme);
    // Drop a stale id rather than carrying it, so `selectedThemeId` always
    // names a family that actually exists.
    if (storedId != null && families.any((f) => f.id == storedId)) {
      _selectedThemeId = storedId;
    }
    _darkMode = prefs.getBool(_kDarkMode) ?? false;
    notifyListeners();
  }

  Future<void> setSelectedTheme(String id) async {
    if (!families.any((f) => f.id == id)) return;
    if (_selectedThemeId == id) return;
    _selectedThemeId = id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSelectedTheme, id);
    notifyListeners();
  }

  Future<void> setDarkMode(bool value) async {
    if (_darkMode == value) return;
    _darkMode = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kDarkMode, value);
    notifyListeners();
  }
}
