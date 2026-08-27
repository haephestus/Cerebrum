import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path_provider/path_provider.dart';

/// Resolves where Cerebrum keeps its on-device data.
///
/// All persistent app state — the drift database, the local note mirror, and
/// editor settings — lives under one root:
///
/// ```
/// <appSupport>/cerebrum/           # canonical root (all platforms)
///     cerebrum.db                  # drift database
///     bubbles/<bubbleId>/notes/…   # local note files
///     editor/…                     # editor settings / palette / themes
/// ```
///
/// The root was historically `<appDocs>/cerebrum` (the user's Documents
/// folder). That location is a landmine on Linux desktop: path_provider's
/// getApplicationDocumentsDirectory() shells out to the `xdg-user-dir`
/// executable, and when that binary isn't installed (common on minimal/NixOS
/// setups) it throws MissingPlatformDirectoryException instead of returning a
/// path — so the database never opens and UI code crashes on null results.
/// The application-support directory resolves via `$XDG_DATA_HOME` (default
/// `~/.local/share`) without relying on any external tools, so it works
/// everywhere. Legacy Documents-dir data is moved here once on first access.
class StoragePaths {
  StoragePaths._();

  static Future<Directory>? _rootFuture;

  /// The canonical data root, creating it if needed. Resolved once; the same
  /// directory is shared by the database, note store, and editor settings.
  static Future<Directory> cerebrumRoot() {
    return _rootFuture ??= _resolve().catchError((Object e, StackTrace st) {
      // Don't cache a failure — let the next caller retry the resolution.
      _rootFuture = null;
      throw e;
    });
  }

  /// Test hook: drop the memoized root so the next call re-resolves. The real
  /// app never needs this — the root is resolved once per process on purpose.
  @visibleForTesting
  static void resetForTest() {
    _rootFuture = null;
  }

  static Future<Directory> _resolve() async {
    final support = await getApplicationSupportDirectory();
    final target = Directory('${support.path}/cerebrum');

    await _migrateLegacyDocumentsLocation(target);

    await target.create(recursive: true);
    return target;
  }

  /// Moves old `<documents>/cerebrum` data into [target] once, when the new
  /// location is empty. Best-effort: the legacy probe itself throws on Linux
  /// without `xdg-user-dir`, which is exactly the failure this replaces.
  static Future<void> _migrateLegacyDocumentsLocation(Directory target) async {
    if (target.existsSync()) return; // already migrated / fresh install
    try {
      final documents = await getApplicationDocumentsDirectory();
      final legacy = Directory('${documents.path}/cerebrum');
      if (!legacy.existsSync()) return;

      await target.parent.create(recursive: true);
      try {
        await legacy.rename(target.path);
      } on FileSystemException {
        // Cross-device move (e.g. Documents on a different mount) — copy
        // instead, then drop the originals.
        await _copyRecursively(legacy, target);
        await legacy.delete(recursive: true);
      }
    } catch (_) {
      // No legacy location resolvable (or readable) — nothing to migrate.
    }
  }

  static Future<void> _copyRecursively(Directory source, Directory target) async {
    for (final entity in source.listSync(recursive: true)) {
      final relative = entity.path.substring(source.path.length + 1);
      final destination = '${target.path}/$relative';
      if (entity is Directory) {
        await Directory(destination).create(recursive: true);
      } else if (entity is File) {
        await File(entity.path).copy(destination);
      }
    }
  }
}