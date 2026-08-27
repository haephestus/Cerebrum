import 'dart:convert';

import 'package:drift/drift.dart' show Value;

import 'package:cerebrum/models/engram_models.dart';
import 'package:cerebrum/services/db/app_database.dart';

/// Local cache of engram *content* (question + answers) so a quiz can start with
/// no connection. Populated from `listEngrams` (fetched with answers) and read
/// back when the daemon is unreachable. Backed by the Drift [AppDatabase].
///
/// Content is stored as the raw engram JSON so it round-trips through
/// `Engram.fromJson` unchanged (including the answer-bearing fields the client
/// reveals after an answer).
///
/// CROSS-REPO CONTRACT ⇄ daemon `list_engrams` payload: [cacheRaw] persists the
/// raw engram maps verbatim (so answers + `bubble_id` survive); offline reads
/// rebuild through `Engram.fromJson`. Breaks if the daemon payload shape drifts
/// from `Engram.fromJson`, or if the Drift schema changes without a
/// `--force-jit` regen + a migration (see app_database schemaVersion).
class EngramStore {
  static AppDatabase get _db => AppDatabase.instance;

  /// Cache the raw engram maps from a fetch. `bubbleId` is the query scope, used
  /// only when an engram map lacks its own `bubble_id`.
  static Future<void> cacheRaw({
    required String userId,
    String? bubbleId,
    required List<Map<String, dynamic>> engrams,
  }) async {
    final now = DateTime.now().toUtc();
    for (final e in engrams) {
      final id = e['id'] as String?;
      final type = e['type'] as String?;
      if (id == null || type == null) continue;
      await _db.upsertCachedEngram(
        CachedEngramsCompanion.insert(
          id: id,
          userId: userId,
          bubbleId: Value((e['bubble_id'] as String?) ?? bubbleId),
          noteId: Value(e['note_id'] as String?),
          type: type,
          targetCognitiveLevel:
              Value((e['target_cognitive_level'] as num?)?.toInt() ?? 1),
          tagsJson: Value(jsonEncode(e['tags'] ?? const [])),
          contentJson: jsonEncode(e['content'] ?? const {}),
          updatedAt: now,
        ),
      );
    }
  }

  /// Rebuild an [EngramListResponse] from the local cache (offline listing).
  static Future<EngramListResponse> cachedResponse({
    required String userId,
    String? bubbleId,
    String? noteId,
  }) async {
    final rows = await _db.cachedEngramsFor(
      userId: userId,
      bubbleId: bubbleId,
      noteId: noteId,
    );
    final engrams = rows.map(_rowToEngram).whereType<Engram>().toList();
    return EngramListResponse(
      bubbleId: bubbleId,
      noteId: noteId,
      count: engrams.length,
      engrams: engrams,
    );
  }

  static Engram? _rowToEngram(CachedEngram r) {
    try {
      return Engram.fromJson({
        'id': r.id,
        'note_id': r.noteId ?? '',
        'type': r.type,
        'target_cognitive_level': r.targetCognitiveLevel,
        'tags': jsonDecode(r.tagsJson),
        'content': jsonDecode(r.contentJson),
      });
    } catch (_) {
      return null; // skip a corrupt/legacy row rather than fail the whole list
    }
  }
}
