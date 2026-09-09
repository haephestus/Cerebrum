/// Models for the dashboard's "Understanding Gaps" hero ([GapCard]).
///
/// These describe ONE bubble worth of gaps, rolled up from the note-level
/// analysis payload the daemon already returns
/// ([LearningCenterApi.getFullCachedAnalysis]): `note_overview.concept_map`
/// (weak areas / confused links), `knowledge_gaps_summary`, and
/// `suggested_sources`, with `chunk_diagnostics` weak-point findings as an
/// evidence-backed fallback per note.
///
/// Honesty rules (homepage-dashboard.md, hard requirements):
///   - Every rendered gap is grounded in a note's analysis, and every gap
///     points at evidence (note title + analysis version; a chunk excerpt for
///     fallback-sourced gaps). A bare label with no evidence is a bug.
///   - Daemon fill-values ("None", "N/A", "no technical material") are treated
///     as no-data, never rendered.
///   - No meaningful gaps → the whole region shrinks away (silent empty state).
library;

/// The single most severe gap across every bubble in [summaries], or null
/// when nothing carries a real daemon severity. Shared by [PriorityGapCard]
/// (the hero) and [GapCard] (the full breakdown) so they agree on exactly
/// which item is "the priority" and it never renders in both places.
GapItem? topPriorityGapAcross(Map<String, BubbleGapSummary> summaries) {
  GapItem? best;
  for (final b in summaries.values) {
    final candidate = b.topPriorityGap;
    if (candidate == null) continue;
    if (best == null ||
        BubbleGapSummary.severityRank(candidate.severity!) >
            BubbleGapSummary.severityRank(best.severity!)) {
      best = candidate;
    }
  }
  return best;
}

/// Stable identity for a [GapItem] (kind + title + detail + source bubble),
/// used only to dedupe an item that's been promoted to the priority hero
/// out of the full per-bubble list below it.
String gapItemKey(GapItem item) {
  final bubbleId =
      item.evidence.isNotEmpty ? (item.evidence.first.bubbleId ?? '') : '';
  return '$bubbleId|${item.kind.name}|${item.title}|${item.detail ?? ''}';
}

/// Formats a daemon analysis version for display. The version can arrive as
/// a double with floating-point noise (e.g. 2.0299999999999994) -- this
/// trims it to at most 2 decimal places and drops a trailing ".00" so the
/// UI never leaks raw floating-point artifacts.
String formatAnalysisVersion(num version) {
  final rounded = double.parse(version.toStringAsFixed(2));
  return rounded == rounded.roundToDouble()
      ? rounded.toInt().toString()
      : rounded.toString();
}

enum GapKind {
  weakArea,
  confusion,
  knowledgeGap,
  suggestedReading;

  /// Face the user with a label tied to the payload field it came from, not a
  /// new vocabulary ("confusion" is what concept_map.confused_links is).
  String get label => switch (this) {
    weakArea => 'Weak area',
    confusion => 'Confusion',
    knowledgeGap => 'Knowledge gap',
    suggestedReading => 'Suggested reading',
  };
}

/// Where a gap was found: the note, the analysis version that found it, and
/// for chunk-sourced fallbacks the excerpt + blocks the finding covers.
class GapEvidence {
  final String noteId;
  final String noteTitle;
  final String? bubbleId;
  final num? analysisVersion; // the analysis's cached_version
  final bool isCurrent;
  final String? excerpt; // trimmed chunk excerpt (fallback-sourced gaps only)

  const GapEvidence({
    required this.noteId,
    required this.noteTitle,
    this.bubbleId,
    this.analysisVersion,
    this.isCurrent = true,
    this.excerpt,
  });
}
class GapItem {
  final GapKind kind;

  /// For a confusion: "A vs B". For a reading: the source title. For weak
  /// areas / knowledge gaps: the daemon's own label or a derived excerpt lead.
  final String title;

  /// confusion_description / gap_explanation / suggested-source reason.
  final String? detail;

  /// Daemon finding severity (`high`/`medium`/`low`) for chunk-fallback gaps.
  /// Null for overview-level gaps — the daemon emits no severity there, and
  /// inventing one would fail the honesty gate.
  final String? severity;
  final List<GapEvidence> evidence;

  const GapItem({
    required this.kind,
    required this.title,
    this.detail,
    this.severity,
    required this.evidence,
  });

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'title': title,
    if (detail != null) 'detail': detail,
    if (severity != null) 'severity': severity,
    'evidence': [
      for (final e in evidence)
        {
          'noteId': e.noteId,
          'noteTitle': e.noteTitle,
          if (e.bubbleId != null) 'bubbleId': e.bubbleId,
          if (e.analysisVersion != null)
            'analysisVersion': e.analysisVersion,
          'isCurrent': e.isCurrent,
          if (e.excerpt != null) 'excerpt': e.excerpt,
        },
    ],
  };

  factory GapItem.fromJson(Map<String, dynamic> json) => GapItem(
    kind: GapKind.values.byName(json['kind'] as String),
    title: json['title'] as String,
    detail: json['detail'] as String?,
    severity: json['severity'] as String?,
    evidence: [
      for (final e in json['evidence'] as List)
        GapEvidence(
          noteId: (e as Map)['noteId'] as String,
          noteTitle: e['noteTitle'] as String,
          bubbleId: e['bubbleId'] as String?,
          analysisVersion: e['analysisVersion'] as num?,
          isCurrent: e['isCurrent'] as bool? ?? true,
          excerpt: e['excerpt'] as String?,
        ),
    ],
  );
}

/// All gaps extracted from ONE note's analysis payload.
class NoteGapData {
  final String noteId;
  final String noteTitle;
  final String? bubbleId;
  final List<GapItem> items;

  const NoteGapData({
    required this.noteId,
    required this.noteTitle,
    this.bubbleId,
    required this.items,
  });

  bool get hasGaps => items.isNotEmpty;
}

/// One bubble's rollup: everything the dashboard's hero renders for it.
class BubbleGapSummary {
  final String bubbleId;
  final String bubbleName;
  final List<GapItem> items;

  const BubbleGapSummary({
    required this.bubbleId,
    required this.bubbleName,
    required this.items,
  });
bool get isEmpty => items.isEmpty;

  int countOf(GapKind kind) =>
      items.where((i) => i.kind == kind).length;

  /// Scales daemon severity into an ordering rank. Overview gaps carry no
  /// daemon severity (null) and rank as medium so they never silently
  /// outrank a documented high-severity chunk finding.
  static int severityRank(String? severity) => switch (severity) {
    'high' => 3,
    'medium' => 2,
    'low' => 1,
    _ => 2,
  };

  /// Cross-bubble attention: bubble sections are ordered by this, so the
  /// bubbles with the most severe gaps lead the hero.
  int get attention => items.fold(0, (sum, i) => sum + severityRank(i.severity));

  /// The single most severe gap WITH a real daemon severity, or null when no
  /// item carries one (do not invent a priority lead from overview gaps).
  GapItem? get topPriorityGap {
    GapItem? best;
    for (final item in items) {
      if (item.severity == null) continue;
      if (best == null ||
          severityRank(item.severity!) > severityRank(best.severity!)) {
        best = item;
      }
    }
    return best;
  }

  /// "3 weak areas · 2 confusions · 1 suggested reading" — the flat
  /// projection the feature spec's example names.
  String get countLine {
    final parts = <String>[
      for (final kind in GapKind.values)
        if (countOf(kind) > 0)
          switch (kind) {
            GapKind.weakArea =>
              '${countOf(kind)} ${countOf(kind) == 1 ? 'weak area' : 'weak areas'}',
            GapKind.confusion =>
              '${countOf(kind)} ${countOf(kind) == 1 ? 'confusion' : 'confusions'}',
            GapKind.knowledgeGap =>
              '${countOf(kind)} ${countOf(kind) == 1 ? 'knowledge gap' : 'knowledge gaps'}',
            GapKind.suggestedReading =>
              '${countOf(kind)} ${countOf(kind) == 1 ? 'suggested reading' : 'suggested readings'}',
          },
    ];
    return parts.join(' · ');
  }

  Map<String, dynamic> toJson() => {
    'bubbleId': bubbleId,
    'bubbleName': bubbleName,
    'items': [for (final i in items) i.toJson()],
  };

  factory BubbleGapSummary.fromJson(Map<String, dynamic> json) =>
      BubbleGapSummary(
        bubbleId: json['bubbleId'] as String,
        bubbleName: json['bubbleName'] as String,
        items: [
          for (final i in json['items'] as List)
            GapItem.fromJson(Map<String, dynamic>.from(i as Map)),
        ],
      );
}
