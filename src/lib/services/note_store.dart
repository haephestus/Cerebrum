import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cerebrum/services/storage_paths.dart';

/// The single filesystem toucher for offline-first note persistence
/// (offline-first plan, phase 1).
///
/// On-device layout mirrors the daemon note-folder shape so the two are easy to
/// reason about (and eventually diff):
///
/// ```
/// <appSupport>/cerebrum/bubbles/<bubbleId>/notes/
///     _index.json                          # list for the notes screen
///     <noteId>/
///         manifest.json                    # note manifest: title/ids/flags + page order
///         .sync.json                       # {dirty, deleted, last_pushed_at}
///         images/<name>                    # cached image bytes
///         pages/<pageId>/
///             content.json                 # the AppFlowy document json
///             ink.json                     # the scribble/ink json
///             analysis.json                # server-computed analysis (kept when received)
///             manifest.json                # {page_id, page_index}
/// ```
///
/// Content (`content.json`) and ink (`ink.json`) are split per the daemon shape
/// — the scribble ink json in particular is bulky, so keeping it in its own file
/// avoids re-serialising it whenever only text changes. `analysis.json` is
/// server-computed; we only ever *store* what the daemon sends back, never mint
/// it locally.
class NoteStore {
  // -- path helpers ------------------------------------------------------

  static Future<Directory> _cerebrumRoot() => StoragePaths.cerebrumRoot();

  static Future<Directory> _notesDir(String bubbleId) async {
    final root = await _cerebrumRoot();
    return Directory('${root.path}/bubbles/$bubbleId/notes');
  }

  static Future<Directory> _noteDir(String bubbleId, String noteId) async {
    final notes = await _notesDir(bubbleId);
    return Directory('${notes.path}/$noteId');
  }

  static Future<File> _indexFile(String bubbleId) async {
    final notes = await _notesDir(bubbleId);
    return File('${notes.path}/_index.json');
  }

  // -- writes ------------------------------------------------------------

  /// Persist a note locally. Always succeeds regardless of connectivity — this
  /// is what makes writes never-lost offline. `pages` is the whole page set in
  /// `toPagesJson()` shape (`{page_id, page_index, document, ink, [analysis]}`).
  ///
  /// `manifest` carries the note-level fields (`title`, `filename`, `note_id`,
  /// `bubble_id`, `analyse_note`, `version`, …). Page order is stored under
  /// `page_order` so a read reconstructs the pages in the right sequence even
  /// though each page lives in its own folder.
  static Future<void> writeNote({
    required String bubbleId,
    required String noteId,
    required Map<String, dynamic> manifest,
    required List<Map<String, dynamic>> pages,
  }) async {
    final noteDir = await _noteDir(bubbleId, noteId);
    final pagesDir = Directory('${noteDir.path}/pages');
    await pagesDir.create(recursive: true);

    final pageIds = <String>[];
    for (var i = 0; i < pages.length; i++) {
      final page = pages[i];
      final pageId = (page['page_id'] as String?) ?? 'p$i';
      pageIds.add(pageId);
      final pageDir = Directory('${pagesDir.path}/$pageId');
      await pageDir.create(recursive: true);

      await _writeJson(
        File('${pageDir.path}/content.json'),
        (page['document'] as Map?) ?? const {},
      );
      await _writeJson(
        File('${pageDir.path}/ink.json'),
        page['ink'] ?? const [],
      );
      await _writeJson(File('${pageDir.path}/manifest.json'), {
        'page_id': pageId,
        'page_index': (page['page_index'] as num?)?.toInt() ?? i,
      });
      // Analysis is server-owned; only persist it when the daemon supplied one.
      if (page['analysis'] != null) {
        await _writeJson(File('${pageDir.path}/analysis.json'), page['analysis']);
      }
    }

    // Prune page folders that no longer exist (pages deleted/merged away), so a
    // subsequent read can't resurrect them.
    if (await pagesDir.exists()) {
      await for (final entry in pagesDir.list()) {
        if (entry is Directory) {
          final name = entry.path.split(Platform.pathSeparator).last;
          if (!pageIds.contains(name)) {
            await entry.delete(recursive: true);
          }
        }
      }
    }

    final fullManifest = Map<String, dynamic>.from(manifest)
      ..['note_id'] = noteId
      ..['bubble_id'] = bubbleId
      ..['page_order'] = pageIds
      ..['updated_at'] = DateTime.now().toUtc().toIso8601String();
    await _writeJson(File('${noteDir.path}/manifest.json'), fullManifest);

    await _updateIndex(bubbleId, noteId, fullManifest);
  }

  // -- reads -------------------------------------------------------------

  /// Reconstruct a note map (in the server/editor `note` shape) from disk, or
  /// null if it isn't stored locally or is tombstoned.
  static Future<Map<String, dynamic>?> readNote(
    String bubbleId,
    String noteId,
  ) async {
    final noteDir = await _noteDir(bubbleId, noteId);
    final manifestFile = File('${noteDir.path}/manifest.json');
    if (!await manifestFile.exists()) return null;

    final sync = await readSyncState(bubbleId, noteId);
    if (sync['deleted'] == true) return null;

    final manifest = await _readJson(manifestFile) as Map<String, dynamic>?;
    if (manifest == null) return null;

    final order = (manifest['page_order'] as List?)?.cast<String>() ?? const [];
    final pagesDir = Directory('${noteDir.path}/pages');
    final pages = <Map<String, dynamic>>[];
    for (final pageId in order) {
      final pageDir = Directory('${pagesDir.path}/$pageId');
      if (!await pageDir.exists()) continue;
      final pm =
          await _readJson(File('${pageDir.path}/manifest.json'))
              as Map<String, dynamic>?;
      final analysisFile = File('${pageDir.path}/analysis.json');
      pages.add({
        'page_id': pageId,
        'page_index': (pm?['page_index'] as num?)?.toInt() ?? pages.length,
        'document':
            await _readJson(File('${pageDir.path}/content.json')) ?? const {},
        'ink': await _readJson(File('${pageDir.path}/ink.json')) ?? const [],
        if (await analysisFile.exists())
          'analysis': await _readJson(analysisFile),
      });
    }

    return Map<String, dynamic>.from(manifest)..['pages'] = pages;
  }

  /// Plain-text preview of a note's first page, without reconstructing the
  /// whole note. Reads only the first page in `page_order` and joins its
  /// document's delta inserts. Returns '' when nothing readable is on disk —
  /// the caller decides whether to show a snippet or hide the line.
  static Future<String> readFirstPageSnippet(
    String bubbleId,
    String noteId,
  ) async {
    final noteDir = await _noteDir(bubbleId, noteId);
    final manifest =
        await _readJson(File('${noteDir.path}/manifest.json'))
            as Map<String, dynamic>?;
    if (manifest == null) return '';
    final order = (manifest['page_order'] as List?)?.cast<String>() ?? const [];
    if (order.isEmpty) return '';
    final content = await _readJson(
      File('${noteDir.path}/pages/${order.first}/content.json'),
    );
    if (content is! Map) return '';
    return documentSnippet(Map<String, dynamic>.from(content));
  }

  /// True when at least one page folder carries a server-computed analysis.json.
  /// Analysis files are only ever written when the daemon supplied one
  /// ([writeNote]), so presence on disk is a real daemon state, never a guess.
  static Future<bool> hasAnyAnalysis(String bubbleId, String noteId) async {
    final noteDir = await _noteDir(bubbleId, noteId);
    final pagesDir = Directory('${noteDir.path}/pages');
    if (!await pagesDir.exists()) return false;
    await for (final entry in pagesDir.list()) {
      if (entry is Directory &&
          await File('${entry.path}/analysis.json').exists()) {
        return true;
      }
    }
    return false;
  }

  /// Plain-text preview of a blocky AppFlowy document (children → delta
  /// inserts concatenated, whitespace-collapsed). Shared by the first-page
  /// snippet reader and the notes-list card builder.
  static String documentSnippet(Map<String, dynamic> document) {
    final parts = <String>[];
    for (final child in (document['children'] as List? ?? [])) {
      if (child is! Map) continue;
      final data = child['data'];
      if (data is! Map) continue;
      for (final op in (data['delta'] as List? ?? [])) {
        if (op is Map && op['insert'] is String) {
          final text = (op['insert'] as String).trim();
          if (text.isNotEmpty) parts.add(text);
        }
      }
    }
    // Collapse the multi-line join into a single readable line.
    return parts.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// The notes-screen list, newest local write first. Skips tombstones.
  static Future<List<Map<String, dynamic>>> listNotes(String bubbleId) async {
    final file = await _indexFile(bubbleId);
    if (!await file.exists()) return [];
    final raw = await _readJson(file);
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((e) => e['deleted'] != true)
        .toList();
  }

  // -- delete (tombstone) ------------------------------------------------

  /// Tombstone a note so a background refresh can't resurrect it. The folder is
  /// kept until a successful daemon delete confirms it can be dropped.
  static Future<void> markDeleted(String bubbleId, String noteId) async {
    final sync = await readSyncState(bubbleId, noteId);
    sync['deleted'] = true;
    sync['dirty'] = true;
    await _writeSyncState(bubbleId, noteId, sync);
    await _setIndexFlag(bubbleId, noteId, 'deleted', true);
  }

  /// Drop a note's folder entirely (after the daemon confirms the delete).
  static Future<void> purge(String bubbleId, String noteId) async {
    final noteDir = await _noteDir(bubbleId, noteId);
    if (await noteDir.exists()) await noteDir.delete(recursive: true);
    await _removeFromIndex(bubbleId, noteId);
  }

  // -- images ------------------------------------------------------------

  static Future<File> writeImage(
    String bubbleId,
    String noteId,
    String name,
    List<int> bytes,
  ) async {
    final noteDir = await _noteDir(bubbleId, noteId);
    final imagesDir = Directory('${noteDir.path}/images');
    await imagesDir.create(recursive: true);
    final file = File('${imagesDir.path}/$name');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  /// The local file for a cached image, or null if it isn't cached yet.
  static Future<File?> readImage(
    String bubbleId,
    String noteId,
    String name,
  ) async {
    final noteDir = await _noteDir(bubbleId, noteId);
    final file = File('${noteDir.path}/images/$name');
    return await file.exists() ? file : null;
  }

  /// Absolute path of a note's images folder (used by the sync-render resolver
  /// to build `Image.file` paths without another async hop per image).
  static Future<String> imagesDirPath(String bubbleId, String noteId) async {
    final noteDir = await _noteDir(bubbleId, noteId);
    return '${noteDir.path}/images';
  }

  /// Names of every locally-cached image for a note (excludes the sidecar
  /// manifest).
  static Future<Set<String>> listImageNames(
    String bubbleId,
    String noteId,
  ) async {
    final noteDir = await _noteDir(bubbleId, noteId);
    final dir = Directory('${noteDir.path}/images');
    if (!await dir.exists()) return {};
    final names = <String>{};
    await for (final entry in dir.list()) {
      if (entry is File) {
        final name = entry.path.split(Platform.pathSeparator).last;
        if (name != '_manifest.json') names.add(name);
      }
    }
    return names;
  }

  /// The note's server filename, once it has one (null while a brand-new note
  /// is still local-only). Read from the note manifest.
  static Future<String?> noteFilename(String bubbleId, String noteId) async {
    final noteDir = await _noteDir(bubbleId, noteId);
    final manifest =
        await _readJson(File('${noteDir.path}/manifest.json'))
            as Map<String, dynamic>?;
    return manifest?['filename'] as String?;
  }

  // Image sidecar manifest: `images/_manifest.json` = { name: {daemon_url} }.
  // Lets the render resolver fall back to the daemon URL when the local cache
  // is missing (e.g. a note synced from another device), and fixes the old
  // "absolute URL breaks when baseUrl changes" bug by storing a resolvable ref
  // in the document instead of a hard URL.

  static Future<Map<String, dynamic>> _imageManifest(
    String bubbleId,
    String noteId,
  ) async {
    final noteDir = await _noteDir(bubbleId, noteId);
    final raw = await _readJson(File('${noteDir.path}/images/_manifest.json'));
    return raw is Map ? Map<String, dynamic>.from(raw) : {};
  }

  static Future<void> setImageDaemonUrl(
    String bubbleId,
    String noteId,
    String name,
    String daemonUrl,
  ) async {
    final noteDir = await _noteDir(bubbleId, noteId);
    final manifest = await _imageManifest(bubbleId, noteId);
    manifest[name] = {'daemon_url': daemonUrl};
    await _writeJson(File('${noteDir.path}/images/_manifest.json'), manifest);
  }

  /// name → daemon URL for every image whose upload has been confirmed.
  static Future<Map<String, String>> imageDaemonUrls(
    String bubbleId,
    String noteId,
  ) async {
    final manifest = await _imageManifest(bubbleId, noteId);
    final out = <String, String>{};
    manifest.forEach((name, v) {
      final url = (v is Map) ? v['daemon_url'] as String? : null;
      if (url != null) out[name] = url;
    });
    return out;
  }

  // -- sync state (.sync.json) ------------------------------------------

  static Future<Map<String, dynamic>> readSyncState(
    String bubbleId,
    String noteId,
  ) async {
    final noteDir = await _noteDir(bubbleId, noteId);
    final file = File('${noteDir.path}/.sync.json');
    if (!await file.exists()) {
      return {'dirty': false, 'deleted': false, 'last_pushed_at': null};
    }
    final raw = await _readJson(file);
    return raw is Map ? Map<String, dynamic>.from(raw) : {'dirty': false};
  }

  static Future<void> _writeSyncState(
    String bubbleId,
    String noteId,
    Map<String, dynamic> state,
  ) async {
    final noteDir = await _noteDir(bubbleId, noteId);
    await noteDir.create(recursive: true);
    await _writeJson(File('${noteDir.path}/.sync.json'), state);
  }

  /// Mark a note as having unsynced local edits.
  static Future<void> markDirty(String bubbleId, String noteId) async {
    final sync = await readSyncState(bubbleId, noteId);
    sync['dirty'] = true;
    await _writeSyncState(bubbleId, noteId, sync);
    await _setIndexFlag(bubbleId, noteId, 'dirty', true);
  }

  /// Clear the dirty flag after a successful push, stamping the push time.
  static Future<void> clearDirty(String bubbleId, String noteId) async {
    final sync = await readSyncState(bubbleId, noteId);
    sync['dirty'] = false;
    sync['last_pushed_at'] = DateTime.now().toUtc().toIso8601String();
    await _writeSyncState(bubbleId, noteId, sync);
    await _setIndexFlag(bubbleId, noteId, 'dirty', false);
  }

  // -- _index.json bookkeeping ------------------------------------------

  static Future<void> _updateIndex(
    String bubbleId,
    String noteId,
    Map<String, dynamic> manifest,
  ) async {
    final entries = await _rawIndex(bubbleId);
    final sync = await readSyncState(bubbleId, noteId);
    entries.removeWhere((e) => e['note_id'] == noteId);
    entries.insert(0, {
      'note_id': noteId,
      'filename': manifest['filename'],
      'title': manifest['title'] ?? 'Untitled',
      'analyse_note': manifest['analyse_note'],
      'updated_at': manifest['updated_at'],
      'dirty': sync['dirty'] == true,
      'deleted': sync['deleted'] == true,
    });
    await _writeJson(await _indexFile(bubbleId), entries);
  }

  static Future<void> _setIndexFlag(
    String bubbleId,
    String noteId,
    String key,
    Object? value,
  ) async {
    final entries = await _rawIndex(bubbleId);
    final idx = entries.indexWhere((e) => e['note_id'] == noteId);
    if (idx < 0) return;
    entries[idx][key] = value;
    await _writeJson(await _indexFile(bubbleId), entries);
  }

  static Future<void> _removeFromIndex(String bubbleId, String noteId) async {
    final entries = await _rawIndex(bubbleId);
    entries.removeWhere((e) => e['note_id'] == noteId);
    await _writeJson(await _indexFile(bubbleId), entries);
  }

  static Future<List<Map<String, dynamic>>> _rawIndex(String bubbleId) async {
    final file = await _indexFile(bubbleId);
    if (!await file.exists()) return [];
    final raw = await _readJson(file);
    if (raw is! List) return [];
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  // -- json io -----------------------------------------------------------

  static Future<void> _writeJson(File file, Object? data) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(data), flush: true);
  }

  static Future<dynamic> _readJson(File file) async {
    try {
      if (!await file.exists()) return null;
      final text = await file.readAsString();
      if (text.isEmpty) return null;
      return jsonDecode(text);
    } catch (_) {
      // A half-written or corrupt file shouldn't take down a read.
      return null;
    }
  }
}

/// Convenience for reading cached image bytes (used by the offline image
/// resolver in a later phase).
extension NoteStoreImageBytes on NoteStore {
  static Future<Uint8List?> imageBytes(
    String bubbleId,
    String noteId,
    String name,
  ) async {
    final file = await NoteStore.readImage(bubbleId, noteId, name);
    if (file == null) return null;
    return file.readAsBytes();
  }
}
