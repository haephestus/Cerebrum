import 'dart:convert';

import 'package:cerebrum/services/note_store.dart';

/// Resolves the stable image refs we embed in note documents
/// (`cerebrum-image://<noteId>/<name>`) to something a renderer can load
/// (offline-first plan, phase 3).
///
/// Why a ref instead of an absolute daemon URL: a hard `http://…` URL breaks
/// the moment the base URL changes (daemon ↔ tunnel ↔ cloud) and can't render
/// offline. The ref is base-URL-agnostic and points at the local cache first.
///
/// CROSS-REPO / FRAGILITY CONTRACT: the ref (not a URL) is what gets PERSISTED
/// and PUSHED to the daemon (`/update`). The in-memory editor doc holds a
/// loadable src; only the persisted/pushed copy holds the ref — the load/save
/// boundary transform (`resolve` on load ⇄ `toRef` on save, in EditorScaffold)
/// MUST stay symmetric, or images either won't render (ref left in the live doc)
/// or won't survive a reload (path saved instead of ref). Consequence: the
/// daemon now stores refs, so a *different* device can't resolve an image
/// without its own local cache/upload record — cross-device image display is a
/// known daemon-side follow-up.
///
/// Resolution order for the current note: local cached file (as an
/// `Image.file` path) → the daemon URL we recorded on a successful upload →
/// the raw ref (renders as a broken-image placeholder, a graceful degrade).
///
/// [resolve] is intentionally synchronous — it runs inside a widget `build`.
/// Callers prime it with [configureForNote] before the editor renders (so the
/// filesystem lookups happen once, up front) and [noteLocalImage] keeps it
/// current when a new image is inserted mid-session. Only one note is open at a
/// time, so a single static context is enough.
class NoteImageResolver {
  static const scheme = 'cerebrum-image://';

  static String? _noteId;
  static String? _imagesDirPath;
  static Set<String> _localNames = {};
  static Map<String, String> _daemonUrls = {};

  static bool isRef(String? src) => src != null && src.startsWith(scheme);

  static String makeRef(String noteId, String name) => '$scheme$noteId/$name';

  /// Prime the resolver for the note about to be shown. Call (and await) this
  /// before building the editor so the first frame resolves correctly — the
  /// underlying image widgets cache their source, so a late resolve wouldn't
  /// take effect without a rebuild.
  static Future<void> configureForNote({
    required String bubbleId,
    required String noteId,
  }) async {
    _noteId = noteId;
    _imagesDirPath = await NoteStore.imagesDirPath(bubbleId, noteId);
    _localNames = await NoteStore.listImageNames(bubbleId, noteId);
    _daemonUrls = await NoteStore.imageDaemonUrls(bubbleId, noteId);
  }

  /// Register an image that was just written locally (insert path), and its
  /// daemon URL once an upload confirms it.
  static void noteLocalImage(String name, {String? daemonUrl}) {
    _localNames = {..._localNames, name};
    if (daemonUrl != null) {
      _daemonUrls = {..._daemonUrls, name: daemonUrl};
    }
  }

  /// Map a stored image src to a loadable one. Non-ref values (legacy absolute
  /// URLs, base64, plain paths) pass through untouched.
  static String resolve(String? src) {
    if (src == null) return '';
    if (!isRef(src)) return src;

    final rest = src.substring(scheme.length); // "<noteId>/<name>"
    final slash = rest.indexOf('/');
    if (slash < 0) return src;
    final noteId = rest.substring(0, slash);
    final name = rest.substring(slash + 1);

    if (noteId == _noteId &&
        _imagesDirPath != null &&
        _localNames.contains(name)) {
      return '$_imagesDirPath/$name';
    }
    final daemon = _daemonUrls[name];
    if (daemon != null) return daemon;
    return src;
  }

  /// The inverse of [resolve]: map a display value (local file path we handed
  /// the editor, or a daemon URL we recorded) back to the stable ref we persist.
  /// Values we don't own (an already-ref'd src, a user-pasted external URL, a
  /// legacy absolute daemon URL from before phase 3) pass through untouched so
  /// they keep working.
  static String toRef(String src) {
    if (isRef(src)) return src;
    final noteId = _noteId;
    if (noteId == null) return src;

    if (_imagesDirPath != null && src.startsWith('$_imagesDirPath/')) {
      return makeRef(noteId, src.substring(_imagesDirPath!.length + 1));
    }
    for (final entry in _daemonUrls.entries) {
      if (entry.value == src) return makeRef(noteId, entry.key);
    }
    return src;
  }

  /// Rewrite every image `url` in an AppFlowy document tree via [map]
  /// (`resolve` on load, `toRef` on save). Returns a deep copy — the caller's
  /// document is left untouched.
  static Map<String, dynamic> mapDocumentUrls(
    Map<String, dynamic> document,
    String Function(String) map,
  ) {
    final copy =
        jsonDecode(jsonEncode(document)) as Map<String, dynamic>;
    void walk(Map node) {
      if (node['type'] == 'image') {
        final data = node['data'];
        if (data is Map && data['url'] is String) {
          data['url'] = map(data['url'] as String);
        }
      }
      final children = node['children'];
      if (children is List) {
        for (final child in children) {
          if (child is Map) walk(child);
        }
      }
    }

    walk(copy);
    return copy;
  }

  /// Convenience: map image urls across a whole `toPagesJson()` page list.
  static List<Map<String, dynamic>> mapPagesUrls(
    List<Map<String, dynamic>> pages,
    String Function(String) map,
  ) {
    return [
      for (final page in pages)
        {
          ...page,
          if (page['document'] is Map)
            'document': mapDocumentUrls(
              Map<String, dynamic>.from(page['document'] as Map),
              map,
            ),
        },
    ];
  }
}
