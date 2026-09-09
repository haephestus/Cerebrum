import 'dart:convert';
import 'dart:io';

import 'package:cerebrum/api/bubbles_api.dart';
import 'package:cerebrum/api/learning_center_api.dart';
import 'package:cerebrum/services/note_store.dart';
import 'package:cerebrum/services/storage_paths.dart';
import 'gap_extract.dart';
import 'gap_models.dart';

/// Fetches the hero's rollup: every bubble's gaps, grouped per study bubble.
///
/// The live implementation is local-first exactly where the daemon is not
/// needed, and daemon-backed where it is:
///   - bubble identity + display names: daemon `fetchBubbles`; offline we fall
///     back to the bubble folders already on disk + the last-known `_meta.json`
///     names (never a loud failure, never a fabricated name).
///   - per-note analysis: daemon `getFullCachedAnalysis` (server-side cached),
///     one call per analyse_note note. That is the phase-1 cost; the whole
///     rollup is then written back to `_gap_cache.json` so the next load —
///     including offline — renders last-known data instantly.
///   - notes + titles: local `NoteStore` only.
abstract class GapRepository {
  /// Last-known summary straight from disk. Never throws; returns {} when no
  /// cache exists.
  Future<Map<String, BubbleGapSummary>> cached();

  /// Rollup with a fresh daemon pass (bubbles + per-note analysis), falling
  /// back to the last-known cache when the daemon is unreachable. Never throws
  /// — an offline first load degrades to a silent empty region.
  Future<Map<String, BubbleGapSummary>> refresh();
}

class LiveGapRepository implements GapRepository {
  const LiveGapRepository();

  @override
  Future<Map<String, BubbleGapSummary>> cached() async {
    final cache = await _readCache();
    return cache?.summaries ?? const {};
  }

  @override
  Future<Map<String, BubbleGapSummary>> refresh() async {
    final cache = await _readCache();

    // Bubble identity: daemon first, then local folders + cached names.
    Map<String, String> names = cache?.names ?? const <String, String>{};
    var bubbles = <String>[];
    try {
      final data = await BubblesApi.fetchBubbles();
      names = {
        for (final b in data.whereType<Map>())
          if (b['id'] != null) '${b['id']}': '${b['name'] ?? ''}',
      };
      bubbles = names.keys.toList();
    } catch (_) {
      // Daemon unreachable — offline path: local bubble folders + last-known
      // names. A folder with no cached name is skipped (an unnameable bubble
      // would render a placeholder, and placeholders are bugs).
      final root = await _bubblesRoot();
      if (await root.exists()) {
        await for (final entry in root.list()) {
          if (entry is Directory) {
            final id = entry.path.split(Platform.pathSeparator).last;
            if (names.containsKey(id)) bubbles.add(id);
          }
        }
      }
    }

    final summaries = <String, BubbleGapSummary>{};
    for (final bubbleId in bubbles) {
      final items = await _rollupBubble(bubbleId);
      if (items.isNotEmpty) {
        summaries[bubbleId] = BubbleGapSummary(
          bubbleId: bubbleId,
          bubbleName: names[bubbleId] ?? 'Study bubble',
          items: items,
        );
      }
    }

    // Persist names + summaries so offline / next load renders last-known.
    await _writeCache(
      GapCacheData(
        fetchedAt: DateTime.now().toUtc().toIso8601String(),
        names: names,
        summaries: summaries,
      ),
    );

    // If the daemon pass produced nothing but a cache exists, keep what we
    // know (last-known data beats a blank region).
    return summaries.isNotEmpty ? summaries : (cache?.summaries ?? {});
  }

  /// One analysis call per analyse_note note; per-note failures are swallowed
  /// so one bad note can't take the whole rollup down.
  Future<List<GapItem>> _rollupBubble(String bubbleId) async {
    final notes = await NoteStore.listNotes(bubbleId);
    final items = <GapItem>[];
    for (final n in notes) {
      if (n['analyse_note'] != true) continue;
      final noteId = n['note_id'] as String?;
      if (noteId == null) continue;
      try {
        final full = await LearningCenterApi.getFullCachedAnalysis(
          bubbleId: bubbleId,
          noteId: noteId,
        );
        if (full == null) continue;
        items.addAll(
          extractNoteGaps(
            noteId: noteId,
            noteTitle: n['title']?.toString() ?? 'Untitled',
            bubbleId: bubbleId,
            full: full,
          ).items,
        );
      } catch (_) {
        // Single note analysis failed — keep the rest of the rollup intact.
      }
    }
    return items;
  }

  static Future<Directory> _bubblesRoot() async {
    final root = await StoragePaths.cerebrumRoot();
    return Directory('${root.path}/bubbles');
  }

  static Future<File> _cacheFile() async {
    final root = await _bubblesRoot();
    return File('${root.path}/_gap_cache.json');
  }

  static Future<GapCacheData?> _readCache() async {
    try {
      final file = await _cacheFile();
      if (!await file.exists()) return null;
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map) return null;
      final summaries = <String, BubbleGapSummary>{};
      final rawSummaries = raw['summaries'];
      if (rawSummaries is Map) {
        rawSummaries.forEach((id, s) {
          if (s is Map) {
            final summary = BubbleGapSummary.fromJson(
              Map<String, dynamic>.from(s),
            );
            if (!summary.isEmpty) summaries['$id'] = summary;
          }
        });
      }
      final names = <String, String>{};
      final rawNames = raw['names'];
      if (rawNames is Map) {
        rawNames.forEach((id, n) => names['$id'] = '$n');
      }
      return GapCacheData(
        fetchedAt: raw['fetched_at'] as String? ?? '',
        names: names,
        summaries: summaries,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> _writeCache(GapCacheData data) async {
    try {
      final file = await _cacheFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({
          'fetched_at': data.fetchedAt,
          'names': data.names,
          'summaries': {
            for (final e in data.summaries.entries) e.key: e.value.toJson(),
          },
        }),
        flush: true,
      );
    } catch (_) {
      // Cache writes are best-effort; the rollup already rendered.
    }
  }
}

class GapCacheData {
  final String fetchedAt;
  final Map<String, String> names;
  final Map<String, BubbleGapSummary> summaries;

  const GapCacheData({
    required this.fetchedAt,
    required this.names,
    required this.summaries,
  });
}
