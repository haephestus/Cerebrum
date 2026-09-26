import 'package:cerebrum/ui/themes/default.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsProvider extends ChangeNotifier {
  String _username = "";
  bool _darkMode = false;
  bool _stewardEnabled = false;
  String _stewardBaseUrl = '';
  String _stewardToken = '';
  String _selectedTheme = '';
  // This is where the default theme value is set
  ThemeData _defaultTheme = defaultLightTheme;

  String get username => _username;
  bool get darkMode => _darkMode;
  bool get stewardEnabled => _stewardEnabled;
  String get stewardBaseUrl => _stewardBaseUrl;
  String get stewardToken => _stewardToken;
  String get selectedTheme => _selectedTheme;
  ThemeData get defaultTheme => _defaultTheme;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _darkMode = prefs.getBool('dark_mode') ?? false;
    _username = prefs.getString('username') ?? '';
    _defaultTheme = prefs.getString('current_theme') ?? '';
    _selectedTheme = prefs.getString('selected_theme') ?? '';
    _stewardEnabled = prefs.getBool('steward_enabled') ?? false;
    _stewardBaseUrl = prefs.getString('steward_base_url') ?? '';
    _stewardToken = prefs.getString('steward_token') ?? '';
    notifyListeners();
  }

  Future<void> setUsername(String value) async {
    _username = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('username', value);
    notifyListeners();
  }

  Future<void> setSelectedTheme(String value) async {
    _selectedTheme = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_theme', value);
    notifyListeners();
  }

  Future<void> setDarkMode(bool value) async {
    _darkMode = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dark_mode', value);
    notifyListeners();
  }

  Future<void> setStewardEnabled(bool value) async {
    _stewardEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('steward_enabled', value);
    notifyListeners();
  }

  Future<void> setStewardBaseUrl(String value) async {
    _stewardBaseUrl = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('steward_base_url', value);
    notifyListeners();
  }

  Future<void> setStewardToken(String value) async {
    _stewardToken = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('steward_token', value);
    notifyListeners();
  }
}
