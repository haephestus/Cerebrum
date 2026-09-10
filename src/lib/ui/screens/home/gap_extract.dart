/// Pure extraction: analysis payload (the `full` map from
/// [LearningCenterApi.getFullCachedAnalysis]) -> one note's gaps.
///
/// Kept free of IO and UI so the honesty rules are unit-inspectable:
///   - fill-values the daemon emits when it found nothing ("None", "N/A",
///     "undefined", "no technical material") are dropped, never rendered.
///   - if `note_overview` has no *real* weak/confusion/gap data but the note's
///     `chunk_diagnostics` carry weak-point findings, those become gaps with a
///     chunk excerpt as evidence (fallback, capped + deduped). If neither
///     exists the note contributes nothing.
///
/// The daemon's `note_overview` is authoritative when it has substance —
/// concept::weak_areas at concept granularity (the spec's "3 weak areas") —
/// but today it degrades to `["None"]` / "The current note contains no
/// technical material to diagnose understanding against." for notes whose
/// topic extraction failed, while the per-chunk findings are still real. Hence
/// the fallback; rendering "None" would fail the no-fabricated-data gate.
library;

import 'gap_models.dart';

/// Patterns the daemon emits when analysis produced no data for a field.
const _fillPatterns = [
  r'^\s*none\s*$',
  r'^\s*n/?a\s*$',
  r'^\s*undefined\s*$',
  r'no technical material',
  r'contains no',
];

bool _isFill(Object? value) {
  if (value == null) return true;
  final s = value.toString().trim();
  if (s.isEmpty) return true;
  return _fillPatterns.any((p) => RegExp(p, caseSensitive: false).hasMatch(s));
}

/// Dedupes nearly-identical gap items (identical title + detail). The daemon
/// can report the same weak point on multiple chunks; counting it twice would
/// inflate "N weak areas" and bury real gaps.
void _dedupe(List<GapItem> items) {
  final seen = <String>{};
  items.removeWhere((i) {
    final key = '${i.kind.name}|${i.title}|${i.detail}';
    return !seen.add(key);
  });
}

int _severityRank(Object? severity) => switch (severity
    .toString()
    .toLowerCase()) {
  'high' => 2,
  'medium' => 1,
  _ => 0, // low + unknown
};

/// First heading or first non-empty line of a chunk excerpt, trimmed to a
/// label of max 64 chars — used as the weak-area title for fallback gaps.
String _excerptTitle(String excerpt) {
  final lines =
      excerpt
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
  final heading =
      lines
          .where((l) => l.startsWith('#'))
          .map((l) => l.replaceFirst(RegExp(r'^#+\s*'), ''))
          .firstOrNull;
  final raw = (heading ?? lines.firstOrNull) ?? '';
  return raw.length <= 64 ? raw : '${raw.substring(0, 61)}…';
}

String _crop(String value, int max) =>
    value.length <= max ? value : '${value.substring(0, max - 1)}…';

/// One note's gaps from its full analysis payload.
NoteGapData extractNoteGaps({
  required String noteId,
  required String noteTitle,
  required Map<String, dynamic> full,
  String? bubbleId,
  int maxChunkGaps = 3,
}) {
  final items = <GapItem>[];
  final evidence = GapEvidence(
    noteId: noteId,
    noteTitle: noteTitle,
    bubbleId: bubbleId,
    analysisVersion: full['cached_version'] as num?,
    isCurrent: full['is_current'] != false, // absent = assumed current
  );

  final overview = full['note_overview'];
  if (overview is Map) {
    final conceptMap = overview['concept_map'];
    if (conceptMap is Map) {
      for (final raw in (conceptMap['weak_areas'] as List? ?? [])) {
        if (!_isFill(raw)) {
          items.add(
            GapItem(
              kind: GapKind.weakArea,
              title: raw.toString().trim(),
              evidence: [evidence],
            ),
          );
        }
      }
      for (final raw in (conceptMap['confused_links'] as List? ?? [])) {
        if (raw is! Map) continue;
        final a = raw['concept_a']?.toString().trim();
        final b = raw['concept_b']?.toString().trim();
        if (a == null || a.isEmpty || b == null || b.isEmpty) continue;
        final description = raw['confusion_description']?.toString().trim();
        items.add(
          GapItem(
            kind: GapKind.confusion,
            title: '$a vs $b',
            detail: _isFill(description) ? null : description,
            evidence: [evidence],
          ),
        );
      }
    }
    for (final raw in (overview['knowledge_gaps_summary'] as List? ?? [])) {
      if (!_isFill(raw)) {
        items.add(
          GapItem(
            kind: GapKind.knowledgeGap,
            title: raw.toString().trim(),
            evidence: [evidence],
          ),
        );
      }
    }
    for (final raw in (overview['suggested_sources'] as List? ?? [])) {
      if (raw is! Map) continue;
      final title = raw['title']?.toString().trim();
      if (_isFill(title)) continue;
      final reason = raw['reason']?.toString().trim();
      items.add(
        GapItem(
          kind: GapKind.suggestedReading,
          title: title!,
          detail: _isFill(reason) ? null : reason,
          evidence: [evidence],
        ),
      );
    }
  }

  // Fallback: no real overview-level gap data, but chunk diagnostics carry
  // weak-point findings. The daemon emits `type: "weak_point"` (observed in
  // real payloads); other finding types aren't part of the disclosure contract
  // yet, so only weak-point-like findings feed the hero.
  final hasOverviewGaps = items.any(
    (i) =>
        i.kind == GapKind.weakArea ||
        i.kind == GapKind.confusion ||
        i.kind == GapKind.knowledgeGap,
  );
  if (!hasOverviewGaps) {
    final findings =
        <
          ({
            String excerpt,
            String title,
            String detail,
            int rank,
            String? severity,
            List<String> blockIds,
            String? pageId,
          })
        >[];
    for (final outer in (full['chunk_diagnostics'] as List? ?? [])) {
      if (outer is! Map) continue;
      // Block linkage lives on the OUTER map (verified in real payloads and
      // mirrored by EditorScaffold._flattenAndSortChunks): which page + which
      // stable blocks this group of chunk diagnostics covers.
      final chunkBlockIds =
          (outer['source_block_ids'] as List?)?.cast<String>() ?? <String>[];
      final chunkPageId = outer['page_id'] as String?;
      for (final diag in (outer['chunk_diagnostics'] as List? ?? [])) {
        if (diag is! Map) continue;
        final excerpt = diag['chunk_excerpt']?.toString() ?? '';
        for (final finding in (diag['findings'] as List? ?? [])) {
          if (finding is! Map) continue;
          final type = finding['type']?.toString().toLowerCase() ?? '';
          if (!type.contains('weak')) continue;
          final explanation =
              finding['gap_explanation']?.toString().trim() ?? '';
          if (explanation.isEmpty) continue;
          final severity = finding['severity']?.toString().toLowerCase() ?? '';
          findings.add((
            excerpt: excerpt,
            title: _excerptTitle(excerpt),
            detail: explanation,
            rank: _severityRank(severity),
            // Only a known vocabulary is claimed; anything else sorts low.
            severity:
                const {'low', 'medium', 'high'}.contains(severity)
                    ? severity
                    : null,
            blockIds: chunkBlockIds,
            pageId: chunkPageId,
          ));
        }
      }
    }

    // Dedupe identical (title, detail) before keeping the most severe, capped.
    final unique =
        <
          ({
            String title,
            String detail,
            String excerpt,
            int rank,
            String? severity,
            List<String> blockIds,
            String? pageId,
          })
        >[];
    final seen = <String>{};
    for (final f in findings) {
      final key = '${f.title}|${f.detail}';
      if (!seen.add(key)) continue;
      unique.add((
        title: f.title,
        detail: f.detail,
        excerpt: f.excerpt,
        rank: f.rank,
        severity: f.severity,
        blockIds: f.blockIds,
        pageId: f.pageId,
      ));
    }
    unique.sort((a, b) => b.rank.compareTo(a.rank));
    for (final f in unique.take(maxChunkGaps)) {
      items.add(
        GapItem(
          kind: GapKind.weakArea,
          title: f.title,
          detail: f.detail,
          severity: f.severity,
          evidence: [
            GapEvidence(
              noteId: evidence.noteId,
              noteTitle: evidence.noteTitle,
              bubbleId: evidence.bubbleId,
              analysisVersion: evidence.analysisVersion,
              isCurrent: evidence.isCurrent,
              excerpt: _crop(f.excerpt, 240),
              blockIds: f.blockIds,
              pageId: f.pageId,
            ),
          ],
        ),
      );
    }
  }

  _dedupe(items);
  return NoteGapData(
    noteId: noteId,
    noteTitle: noteTitle,
    bubbleId: bubbleId,
    items: items,
  );
}
