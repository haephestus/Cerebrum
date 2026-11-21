import 'package:shared_preferences/shared_preferences.dart';

/// Client-side reading progress, shared by the reader and the file library.
///
/// The daemon stores the document registry but not per-user reading position,
/// so this is the single source of truth for the SharedPreferences keys. Both
/// widgets must go through here: a private key getter in either one would let
/// the library show a page the reader never wrote.
class ReadingProgress {
  ReadingProgress._();

  static String pageKey(String fingerprint) => 'reader_last_page_$fingerprint';

  static String openedKey(String fingerprint) =>
      'reader_last_opened_$fingerprint';

  /// Record that the document was opened, even if the user never turns a page.
  static Future<void> markOpened(String fingerprint) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      openedKey(fingerprint),
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Persist the current page. Also bumps the opened timestamp so "recently
  /// read" reflects actual reading, not just the moment the reader launched.
  static Future<void> savePage(String fingerprint, int page) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(pageKey(fingerprint), page);
    await prefs.setInt(
      openedKey(fingerprint),
      DateTime.now().millisecondsSinceEpoch,
    );
  }
}
