import 'package:cerebrum/ui/screens/home/gap_extract.dart';
import 'package:cerebrum/ui/screens/home/gap_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fixtures model the REAL daemon payload (verified 2026-09-09):
/// `getFullCachedAnalysis` returns `{chunk_diagnostics, note_overview,
/// cached_version, cached_at, is_current}`.
Map<String, dynamic> fullAnalysis({
  Map<String, dynamic>? overview,
  List<dynamic>? chunks,
  num? cachedVersion,
  bool isCurrent = true,
}) => {
  'chunk_diagnostics': chunks ?? const [],
  'cached_version': cachedVersion ?? 4,
  'cached_at': '2026-09-09T12:00:00Z',
  'is_current': isCurrent,
  if (overview != null) 'note_overview': overview,
};

Map<String, dynamic> realOverview({
  List<String> weak = const [],
  List<dynamic> confused = const [],
  List<String> gaps = const [],
  List<dynamic> sources = const [],
}) => {
  'topic': 'Data Structures',
  'mastery_signal': 'novice',
  'progress_delta': 'baseline',
  'concept_map': {
    'strong_areas': const ['Pointers'],
    'weak_areas': weak,
    'confused_links': confused,
  },
  'knowledge_gaps_summary': gaps,
  'priority_study_areas': const ['N/A'],
  'suggested_sources': sources,
};

Map<String, dynamic> chunkDiagnostics({
  required String excerpt,
  String type = 'weak_point',
  String severity = 'low',
}) => {
  'chunk_id': 'p0-chunk0',
  'chunk_index': 0,
  'page_id': 'p0',
  'source_block_ids': const ['IX6ZWS'],
  'chunk_diagnostics': [
    {
      'chunk_id': 'p0-chunk0',
      'chunk_excerpt': excerpt,
      'findings': [
        {
          'finding_index': 0,
          'type': type,
          'severity': severity,
          'confidence': 1.0,
          'student_claim': 'some claim',
          'correct_understanding': 'correct version',
          'gap_explanation': 'The student compresses the definition.',
        },
      ],
    },
  ],
};

void main() {
  NoteGapData extract(Map<String, dynamic> full) =>
      extractNoteGaps(noteId: 'n1', noteTitle: 'Data Structures', full: full);

  group('note_overview gaps', () {
    test('weak areas, confusions, knowledge gaps, sources all surface', () {
      final data = extract(
        fullAnalysis(
          overview: realOverview(
            weak: ['Recursion', 'Heaps'],
            confused: [
              {
                'concept_a': 'Stack',
                'concept_b': 'Queue',
                'confusion_description': 'FIFO vs LIFO',
              },
            ],
            gaps: ['Can\'t trace recursion trees'],
            sources: [
              {'title': 'Algorithms Unlocked', 'reason': 'covers sorting'},
            ],
          ),
          cachedVersion: 7,
        ),
      );

      expect(data.items, hasLength(5));
      expect(
        data.items.where((i) => i.kind == GapKind.weakArea).map((i) => i.title),
        ['Recursion', 'Heaps'],
      );
      final confusion = data.items.firstWhere(
        (i) => i.kind == GapKind.confusion,
      );
      expect(confusion.title, 'Stack vs Queue');
      expect(confusion.detail, 'FIFO vs LIFO');
      expect(
        data.items.firstWhere((i) => i.kind == GapKind.suggestedReading).title,
        'Algorithms Unlocked',
      );
      // Evidence points at the note + the analysis version that found it.
      final evidence = data.items.first.evidence.single;
      expect(evidence.noteId, 'n1');
      expect(evidence.noteTitle, 'Data Structures');
      expect(evidence.analysisVersion, 7);
      expect(evidence.isCurrent, isTrue);
    });

    test('daemon fill-values are dropped, never rendered', () {
      final data = extract(
        fullAnalysis(
          overview: realOverview(
            weak: ['None', 'N/A', '', 'Recursion'],
            gaps: [
              'The current note contains no technical material to diagnose understanding against.',
            ],
          ),
        ),
      );

      expect(data.items, hasLength(1));
      expect(data.items.single.title, 'Recursion');
    });

    test('malformed confusion links (missing concept_b) are skipped', () {
      final data = extract(
        fullAnalysis(
          overview: realOverview(
            confused: [
              {'concept_a': 'Stack', 'confusion_description': 'incomplete'},
            ],
          ),
        ),
      );

      expect(data.items, isEmpty);
    });

    test('suggested source with a fill title is skipped', () {
      final data = extract(
        fullAnalysis(
          overview: realOverview(
            sources: [
              {'title': 'N/A', 'reason': 'x'},
              {'title': 'Real Source', 'reason': 'y'},
            ],
          ),
        ),
      );

      expect(data.items.map((i) => i.title), ['Real Source']);
    });

    test('no overview is treated as no overview-level gaps', () {
      final data = extract(fullAnalysis());
      expect(data.items, isEmpty);
    });
  });

  group('chunk weak-point fallback', () {
    final degradedOverview = realOverview(
      weak: const ['None'],
      gaps: const [
        'The current note contains no technical material to diagnose understanding against.',
      ],
    );

    test(
      'fills gaps when the overview degraded but chunk findings are real',
      () {
        final data = extract(
          fullAnalysis(
            overview: degradedOverview,
            chunks: [
              chunkDiagnostics(
                excerpt: '# Primitive Data Types\n\nTypes are the basics.',
              ),
            ],
          ),
        );

        expect(data.items, hasLength(1));
        final gap = data.items.single;
        expect(gap.kind, GapKind.weakArea);
        // Title comes from the excerpt heading, not a bare label.
        expect(gap.title, 'Primitive Data Types');
        expect(gap.detail, contains('compresses the definition'));
        expect(gap.evidence.single.excerpt, contains('Primitive Data Types'));
        expect(gap.evidence.single.isCurrent, isTrue);
      },
    );

    test('dedupes the same weak point reported on multiple chunks', () {
      final data = extract(
        fullAnalysis(
          overview: degradedOverview,
          chunks: [
            chunkDiagnostics(excerpt: '# Abstract Data Types\n\nA is B.'),
            chunkDiagnostics(excerpt: '# Abstract Data Types\n\nA is B.'),
          ],
        ),
      );

      expect(data.items, hasLength(1));
    });

    test('only weak-point-like findings feed the fallback', () {
      final data = extract(
        fullAnalysis(
          overview: degradedOverview,
          chunks: [
            chunkDiagnostics(
              excerpt: '# Not A Gap\n\nFine material.',
              type: 'strong_point',
            ),
          ],
        ),
      );

      expect(data.items, isEmpty);
    });

    test('most severe findings first, capped by maxChunkGaps', () {
      final data = extractNoteGaps(
        noteId: 'n1',
        noteTitle: 'Data Structures',
        full: fullAnalysis(
          overview: degradedOverview,
          chunks: [
            chunkDiagnostics(excerpt: '# One\n\nlow', severity: 'low'),
            chunkDiagnostics(excerpt: '# Two\n\nhigh', severity: 'high'),
            chunkDiagnostics(excerpt: '# Three\n\nmed', severity: 'medium'),
            chunkDiagnostics(excerpt: '# Four\n\nlow', severity: 'low'),
          ],
        ),
        maxChunkGaps: 3,
      );

      expect(data.items, hasLength(3));
      expect(data.items[0].title, 'Two'); // highest severity first
    });

    test('overview gaps win over the fallback when both are real', () {
      final data = extract(
        fullAnalysis(
          overview: realOverview(
            weak: ['Recursion'], // real
            confused: [
              {
                'concept_a': 'Stack',
                'concept_b': 'Queue',
                'confusion_description': 'FIFO vs LIFO',
              },
            ],
          ),
          chunks: [chunkDiagnostics(excerpt: '# Chunk\n\nweak')],
        ),
      );

      // 2 overview gaps + 1 suggested... no sources here; only overview data.
      expect(data.items, hasLength(2));
      // No chunk-derived item because the overview already has real gaps.
      expect(data.items.map((i) => i.title), contains('Recursion'));
    });
  });
}
