import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:cerebrum/api/bubbles_api.dart';
import 'package:cerebrum/services/note_store.dart';

/// Offline-capable note sync — the client push half (offline-first plan,
/// phases 1-4).
///
/// Notes are written to [NoteStore] first (that's the never-lose guarantee),
/// then handed here to reach the daemon. This service owns three
/// `shared_preferences` outboxes — note pushes, image uploads, and note deletes
/// — queued while the daemon is unreachable and retried by [drainOutbox] on app
/// start / resume / reconnect.
///
/// Pushes go through the whole-page-set `/update` contract
/// ([BubbleNotesApi.updateNote]) — the daemon reconciles per `page_id`
/// (edits + adds + deletes) with last-writer-wins, so a stale queued push can't
/// delete pages edited elsewhere in the meantime. Brand-new notes (no filename
/// yet) are first materialised with [BubbleNotesApi.createNote], then their full
/// page set is pushed via `/update`.
///
/// Reconnect handling: rather than pull in a connectivity plugin, anything left
/// queued after a failed push starts a light **auto-drain** poll ([_ensure
/// AutoDrain]) that retries every [_retryInterval] until all outboxes clear,
/// then stops. Combined with the start/resume drains, a note saved offline syncs
/// on its own once the daemon is reachable again.
///
/// (The retired `/sync/push` version-vector path — dead code that dropped edits
/// and couldn't delete pages — has been removed.)
///
/// ══ CROSS-REPO CONTRACT / fragility ═════════════════════════════════════
///  • Drain ORDER matters: notes → images → deletes. A new note must be pushed
///    (createNote, which back-fills its server `filename`) BEFORE its images
///    upload — image upload needs the note's filename (NoteStore.noteFilename).
///    Reorder this and offline-created notes' images fail to upload.
///  • Idempotency rides on the client-owned `note_id` (see EditorScaffold/
///    BubbleNotesApi): a replayed push is an update on the same id, not a new
///    note. There is no version vector — reconciliation is the daemon's
///    per-`page_id` LWW in `/update`. Don't send a partial page set (it deletes
///    pages) and don't push before the local write (NoteStore first = the
///    never-lose guarantee).
///  • `_push` persists the daemon's merged response back to NoteStore so a
///    background drain also captures the server filename; skipping that
///    re-creates the note on the next save (duplicate).
/// ════════════════════════════════════════════════════════════════════════
class SyncService {
  static const _kOutbox = 'cerebrum_sync_outbox';
  static const _kImageOutbox = 'cerebrum_image_outbox';
  static const _kDeleteOutbox = 'cerebrum_delete_outbox';

  static const _retryInterval = Duration(seconds: 20);
  static Timer? _retryTimer;

  /// Queue a locally-saved note for the daemon and attempt an immediate push.
  ///
  /// The caller has already written the note to [NoteStore] and marked it dirty.
  /// Returns the merged server note on success (dirty cleared), or null if the
  /// push was queued for later (offline / hub down).
  static Future<Map<String, dynamic>?> queueSave({
    required String bubbleId,
    required String noteId,
    required String title,
    required List<Map<String, dynamic>> pages,
    String? filename,
    bool analyseNote = true,
  }) async {
    await _enqueue({
      'bubbleId': bubbleId,
      'noteId': noteId,
      'filename': filename,
      'title': title,
      'analyse_note': analyseNote,
      'pages': pages,
    });
    final result = await _tryPush(bubbleId, noteId);
    await _ensureAutoDrain();
    return result;
  }

  /// Queue a note delete. Tombstoned locally by the caller already; this
  /// propagates the delete to the daemon (immediately if reachable, else on the
  /// next drain) and purges the local folder once the server confirms. Local-
  /// only notes (never pushed, no filename) don't need this — there's nothing on
  /// the server to delete.
  static Future<void> queueDelete({
    required String bubbleId,
    required String noteId,
    required String filename,
  }) async {
    // A note being deleted shouldn't also try to push its edits.
    await _dequeue(bubbleId, noteId);

    final items = await _deleteOutbox();
    if (!items.any((i) => i['bubbleId'] == bubbleId && i['noteId'] == noteId)) {
      items.add({
        'bubbleId': bubbleId,
        'noteId': noteId,
        'filename': filename,
      });
      await _saveDeleteOutbox(items);
    }
    await _pushDelete(bubbleId, noteId, filename); // best-effort now
    await _ensureAutoDrain();
  }

  /// Queue an image for upload. Written to the local cache already by the
  /// caller; the upload can only run once its note exists on the daemon (needs a
  /// filename), so it's queued and retried by [drainOutbox].
  static Future<void> queueImageUpload({
    required String bubbleId,
    required String noteId,
    required String name,
  }) async {
    final items = await _imageOutbox();
    if (!items.any(
      (i) =>
          i['bubbleId'] == bubbleId &&
          i['noteId'] == noteId &&
          i['name'] == name,
    )) {
      items.add({'bubbleId': bubbleId, 'noteId': noteId, 'name': name});
      await _saveImageOutbox(items);
    }
    await _pushImage(bubbleId, noteId, name); // best-effort now
    await _ensureAutoDrain();
  }

  /// Retry every queued push (call on app start / resume / reconnect). Stops at
  /// the first failure so we don't hammer an unreachable daemon. Order: note
  /// pushes first (so new notes get a filename before their images upload), then
  /// image uploads, then deletes. Cancels the auto-drain poll once everything is
  /// through.
  static Future<void> drainOutbox() async {
    for (final item in await _outbox()) {
      final result = await _push(item);
      if (result == null) break; // still offline — keep the rest queued
    }
    await _drainImages();
    await _drainDeletes();

    if (await pendingCount() == 0) {
      _retryTimer?.cancel();
      _retryTimer = null;
    }
  }

  /// How many operations are waiting (for a "pending sync" indicator).
  static Future<int> pendingCount() async =>
      (await _outbox()).length +
      (await _imageOutbox()).length +
      (await _deleteOutbox()).length;

  // -- auto-drain (poll-based reconnect substitute) ----------------------

  /// Start the retry poll if anything is queued and it isn't already running.
  /// The poll drains on each tick and [drainOutbox] stops it once the outboxes
  /// are empty, so it costs nothing while everything is synced.
  static Future<void> _ensureAutoDrain() async {
    if (_retryTimer != null) return;
    if (await pendingCount() == 0) return;
    _retryTimer = Timer.periodic(_retryInterval, (_) => drainOutbox());
  }

  // -- push --------------------------------------------------------------

  static Future<Map<String, dynamic>?> _tryPush(
    String bubbleId,
    String noteId,
  ) async {
    final items = await _outbox();
    final item = items.firstWhere(
      (i) => i['bubbleId'] == bubbleId && i['noteId'] == noteId,
      orElse: () => const {},
    );
    if (item.isEmpty) return null;
    return _push(item);
  }

  /// Push one outbox entry. On success clears the note's dirty flag and drops
  /// the entry; on failure leaves it queued and returns null.
  static Future<Map<String, dynamic>?> _push(Map<String, dynamic> item) async {
    final bubbleId = item['bubbleId'] as String;
    final noteId = item['noteId'] as String;
    final title = (item['title'] as String?) ?? 'Untitled';
    final pages = List<Map<String, dynamic>>.from(
      (item['pages'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
    );
    var filename = item['filename'] as String?;

    try {
      Map<String, dynamic> result;
      if (filename == null) {
        // Brand-new note: materialise it server-side (creates the folder) with
        // OUR client-minted id, so the server filename becomes `<noteId>.json`
        // and there's no identity churn. Then push the whole page set /update.
        final created = await BubbleNotesApi.createNote(
          bubbleId: bubbleId,
          title: title,
          noteId: noteId,
          content: {
            'document': pages.isNotEmpty ? pages.first['document'] : const {},
          },
          ink: pages.isNotEmpty
              ? List<Map<String, dynamic>>.from(
                  (pages.first['ink'] as List?) ?? const [],
                )
              : const [],
        );
        filename = created['filename'] as String?;
        result = created;
        if (filename != null && pages.isNotEmpty) {
          result = await BubbleNotesApi.updateNote(
            bubbleId: bubbleId,
            filename: filename,
            title: title,
            noteId: noteId,
            pages: pages,
          );
        }
      } else {
        result = await BubbleNotesApi.updateNote(
          bubbleId: bubbleId,
          filename: filename,
          title: title,
          noteId: noteId,
          pages: pages,
        );
      }

      // Persist the server-confirmed copy locally so a background drain also
      // captures daemon-assigned fields (notably a new note's `filename`) —
      // otherwise the next save would treat it as new again and duplicate it.
      final mergedPages = result['pages'] != null
          ? List<Map<String, dynamic>>.from(
              (result['pages'] as List)
                  .map((e) => Map<String, dynamic>.from(e as Map)),
            )
          : pages;
      await NoteStore.writeNote(
        bubbleId: bubbleId,
        noteId: noteId,
        manifest: {
          'title': title,
          'filename': filename ?? result['filename'],
          'note_id': noteId,
          'bubble_id': bubbleId,
          'analyse_note': item['analyse_note'] ?? true,
        },
        pages: mergedPages,
      );
      await NoteStore.clearDirty(bubbleId, noteId);
      await _dequeue(bubbleId, noteId);
      result['bubble_id'] = bubbleId;
      return result;
    } catch (_) {
      // offline / hub down — leave it queued for drainOutbox().
      return null;
    }
  }

  // -- outbox (a JSON list in shared_preferences) ------------------------

  static Future<List<Map<String, dynamic>>> _outbox() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kOutbox);
    if (raw == null) return [];
    return List<Map<String, dynamic>>.from(
      (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e as Map)),
    );
  }

  static Future<void> _saveOutbox(List<Map<String, dynamic>> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kOutbox, jsonEncode(items));
  }

  static Future<void> _enqueue(Map<String, dynamic> entry) async {
    final items = await _outbox();
    // one pending push per note — replace any earlier queued version
    items.removeWhere(
      (i) => i['bubbleId'] == entry['bubbleId'] && i['noteId'] == entry['noteId'],
    );
    items.add(entry);
    await _saveOutbox(items);
  }

  static Future<void> _dequeue(String bubbleId, String noteId) async {
    final items = await _outbox();
    items.removeWhere((i) => i['bubbleId'] == bubbleId && i['noteId'] == noteId);
    await _saveOutbox(items);
  }

  // -- image outbox ------------------------------------------------------

  static Future<void> _drainImages() async {
    for (final item in await _imageOutbox()) {
      final done = await _pushImage(
        item['bubbleId'] as String,
        item['noteId'] as String,
        item['name'] as String,
      );
      // done == false means either the note isn't on the server yet (skip and
      // keep queued) or we're offline. A cheap check: if the note has no
      // filename it's the former (harmless to keep going); otherwise stop.
      if (!done) {
        final filename = await NoteStore.noteFilename(
          item['bubbleId'] as String,
          item['noteId'] as String,
        );
        if (filename != null) break; // real network failure — stop retrying now
      }
    }
  }

  /// Upload one cached image if its note already exists on the daemon. Returns
  /// true when handled (uploaded, or dropped because the bytes are gone), false
  /// if it should stay queued (note not pushed yet, or upload failed).
  static Future<bool> _pushImage(
    String bubbleId,
    String noteId,
    String name,
  ) async {
    final filename = await NoteStore.noteFilename(bubbleId, noteId);
    if (filename == null) return false; // note not on the server yet

    final file = await NoteStore.readImage(bubbleId, noteId, name);
    if (file == null) {
      await _dequeueImage(bubbleId, noteId, name); // bytes gone — drop it
      return true;
    }

    try {
      final url = await BubbleNotesApi.uploadNoteImage(
        bubbleId: bubbleId,
        filename: filename,
        bytes: await file.readAsBytes(),
        imageFilename: name,
      );
      await NoteStore.setImageDaemonUrl(bubbleId, noteId, name, url);
      await _dequeueImage(bubbleId, noteId, name);
      return true;
    } catch (_) {
      return false; // offline / hub down — keep it queued
    }
  }

  static Future<List<Map<String, dynamic>>> _imageOutbox() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kImageOutbox);
    if (raw == null) return [];
    return List<Map<String, dynamic>>.from(
      (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e as Map)),
    );
  }

  static Future<void> _saveImageOutbox(List<Map<String, dynamic>> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kImageOutbox, jsonEncode(items));
  }

  static Future<void> _dequeueImage(
    String bubbleId,
    String noteId,
    String name,
  ) async {
    final items = await _imageOutbox();
    items.removeWhere(
      (i) =>
          i['bubbleId'] == bubbleId &&
          i['noteId'] == noteId &&
          i['name'] == name,
    );
    await _saveImageOutbox(items);
  }

  // -- delete outbox -----------------------------------------------------

  static Future<void> _drainDeletes() async {
    for (final item in await _deleteOutbox()) {
      final done = await _pushDelete(
        item['bubbleId'] as String,
        item['noteId'] as String,
        item['filename'] as String,
      );
      if (!done) break; // still offline — keep the rest queued
    }
  }

  /// Delete a note on the daemon and purge its local folder. Returns true when
  /// handled (deleted, or already gone server-side), false to stay queued
  /// (offline / transient failure).
  static Future<bool> _pushDelete(
    String bubbleId,
    String noteId,
    String filename,
  ) async {
    try {
      await BubbleNotesApi.deleteNote(bubbleId, filename);
    } catch (e) {
      // Already gone server-side (404) → nothing to retry; fall through to the
      // local purge. Any other error is transient → keep it queued.
      if (!e.toString().contains('404')) return false;
    }
    await NoteStore.purge(bubbleId, noteId);
    await _dequeueDelete(bubbleId, noteId);
    return true;
  }

  static Future<List<Map<String, dynamic>>> _deleteOutbox() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kDeleteOutbox);
    if (raw == null) return [];
    return List<Map<String, dynamic>>.from(
      (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e as Map)),
    );
  }

  static Future<void> _saveDeleteOutbox(List<Map<String, dynamic>> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDeleteOutbox, jsonEncode(items));
  }

  static Future<void> _dequeueDelete(String bubbleId, String noteId) async {
    final items = await _deleteOutbox();
    items.removeWhere((i) => i['bubbleId'] == bubbleId && i['noteId'] == noteId);
    await _saveDeleteOutbox(items);
  }
}
