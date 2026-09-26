import 'package:cerebrum/ui/themes/theme_access.dart';
import 'package:flutter/material.dart';
import 'package:cerebrum/models/engram_models.dart';

/// Everything the engrams section needs to render one grouped rollup: the
/// daemon payload plus the local names it resolves to (bubble names from the
/// daemon, note titles from the local NoteStore index). Both name lookups
/// are best-effort — a missing name degrades to the raw id, never a
/// placeholder.
class EngramsViewData {
  final EngramListResponse response;
  final Map<String, String> bubbleNames; // bubbleId -> display name
  final Map<String, Map<String, String>>
  noteTitles; // bubbleId -> (noteId -> title)

  const EngramsViewData({
    required this.response,
    required this.bubbleNames,
    required this.noteTitles,
  });
}

// ── Presentation helpers shared by the dashboard (due-today card,
// performance panel) and the section below. Top-level so both sides use one
// implementation instead of the section asking the page for a pile of
// function props (the DueTodayStrip convention).

/// Human label for an engram type.
String engramTypeLabel(EngramType t) => switch (t) {
  EngramType.mcq => 'Multiple Choice',
  EngramType.flashcard => 'Flashcards',
  EngramType.shortQuestion => 'Short Questions',
  EngramType.longQuestion => 'Long Questions',
  EngramType.unknown => 'Other',
};

/// Icon for an engram type.
IconData engramTypeIcon(EngramType t) => switch (t) {
  EngramType.mcq => Icons.quiz_outlined,
  EngramType.flashcard => Icons.style_outlined,
  EngramType.shortQuestion => Icons.short_text,
  EngramType.longQuestion => Icons.article_outlined,
  EngramType.unknown => Icons.help_outline,
};

/// One-line preview of an engram's content, per type.
String engramPreview(Engram e) {
  switch (e.type) {
    case EngramType.mcq:
      return (e.content as McqContent).stem;
    case EngramType.flashcard:
      return (e.content as FlashcardContent).front;
    case EngramType.shortQuestion:
      final c = e.content as ShortQuestionContent;
      return c.questions.isNotEmpty
          ? c.questions.first.stem
          : 'Short question set';
    case EngramType.longQuestion:
      return (e.content as LongQuestionContent).questionStem;
    case EngramType.unknown:
      return 'Untitled item';
  }
}

/// Weak-point concept label from an engram's tags. The daemon emits
/// `["weak_point", "<Concept Name>"]` — the second element IS the topic
/// label. Guarded: any other shape degrades to a bare "Weak point".
String weakPointConcept(Engram e) {
  final idx = e.tags.indexOf('weak_point');
  if (idx >= 0 && idx + 1 < e.tags.length && e.tags[idx + 1].isNotEmpty) {
    return e.tags[idx + 1];
  }
  return 'Weak point';
}

bool isWeakPoint(Engram e) => e.tags.contains('weak_point');

/// How the browse list below Needs your attention is organized.
enum _EngramBrowseMode { byBubble, byNote, byType }

/// Due-status filter derived from the daemon's `scheduled_at`. Honest by
/// construction: only null vs set-and-compare-to-now — no synthesized times.
enum _DueFilter { all, due, upcoming, unscheduled }

String _dueFilterLabel(_DueFilter f) => switch (f) {
  _DueFilter.all => 'All',
  _DueFilter.due => 'Due',
  _DueFilter.upcoming => 'Upcoming',
  _DueFilter.unscheduled => 'Unscheduled',
};

/// The Engrams section of the Learning Center: "Needs your attention"
/// (collapsible weak-point rollup) on top, then the browse list grouped by
/// bubble, note, or type. Owns its browse-mode, collapse, and filter state;
/// embedded into the page ListView, so it never scrolls itself.
///
/// Two filter layers:
///   • client-side (instant, no network): due status + type chips — they act
///     on whatever payload is loaded;
///   • server-side (refetch via [refetch]): severity + cognitive-level chips.
///     The daemon owns both (severity on a short-question engram lives per
///     question item, so a client-side interpretation would be an invention),
///     and the filtered response replaces only this section's internal view —
///     the dashboard's unfiltered future is never touched. The server chips
///     live behind the Needs-your-attention header's Filter chip (see
///     [_buildServerFilterChips]) so they stay reachable even when the
///     browse list below has no non-weak-point items.
class EngramsSection extends StatefulWidget {
  final Future<EngramsViewData> future;
  final Future<EngramsViewData> Function({
    int? cognitiveLevel,
    String? severity,
  })
  refetch;
  final void Function(Engram) onEngramTap;

  const EngramsSection({
    super.key,
    required this.future,
    required this.refetch,
    required this.onEngramTap,
  });

  @override
  State<EngramsSection> createState() => _EngramsSectionState();
}

class _EngramsSectionState extends State<EngramsSection> {
  _EngramBrowseMode _browseMode = _EngramBrowseMode.byBubble;
  _DueFilter _dueFilter = _DueFilter.all;
  final Set<EngramType> _typeFilter = {};

  // Server-side filters (daemon-authoritative). When either is active the
  // section shows `_overrideFuture` (a filtered refetch) instead of the full
  // `widget.future`, so the dashboard's shared future stays unfiltered.
  int? _cognitiveLevel;
  String? _severity;
  Future<EngramsViewData>? _overrideFuture;

  Future<EngramsViewData> get _effectiveFuture =>
      _overrideFuture ?? widget.future;

  // Needs-your-attention starts collapsed to a handful of items -- a flat
  // list of every weak-point engram (11+ in practice) was the thing that
  // made this section unmanageable in the first place.
  bool _weakPointExpanded = false;
  static const int _weakPointCollapsedLimit = 4;

  // Server-side filter panel visibility in the Needs-your-attention header.
  // The header's trailing slot fits exactly ONE compact chip — a Filter
  // toggle — and tapping it reveals the severity + level chips beneath.
  bool _filterPanelOpen = false;

  @override
  void didUpdateWidget(covariant EngramsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Parent refreshed the payload (pull-to-refresh re-created `future`).
    // Re-run the active server filter against the fresh data; the browse
    // chips keep their selection, the data doesn't silently go stale.
    if (!identical(oldWidget.future, widget.future)) {
      if (_cognitiveLevel == null && _severity == null) {
        _overrideFuture = null;
      } else {
        _overrideFuture = widget.refetch(
          cognitiveLevel: _cognitiveLevel,
          severity: _severity,
        );
      }
    }
  }

  void _setServerFilter({int? cognitiveLevel, String? severity}) {
    setState(() {
      _cognitiveLevel = cognitiveLevel;
      _severity = severity;
      _overrideFuture =
          cognitiveLevel == null && severity == null
              ? null
              : widget.refetch(
                cognitiveLevel: cognitiveLevel,
                severity: severity,
              );
    });
  }

  bool _passesDue(Engram e) {
    final at = e.scheduledAt;
    final now = DateTime.now();
    return switch (_dueFilter) {
      _DueFilter.all => true,
      _DueFilter.due => at != null && !at.isAfter(now),
      _DueFilter.upcoming => at != null && at.isAfter(now),
      _DueFilter.unscheduled => at == null,
    };
  }

  // TODO(filters): daemon `state`. Present on Engram and filterable server-side
  // (`listEngrams.state`) but display-only per the model contract
  // (`scheduled`/`due`/`completed`...); decide filter semantics once the
  // daemon is authoritative on it.
  bool _passesType(Engram e) =>
      _typeFilter.isEmpty || _typeFilter.contains(e.type);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<EngramsViewData>(
      future: _effectiveFuture,
      builder: (context, snapshot) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
              child: Text(
                'Engrams',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (snapshot.connectionState == ConnectionState.waiting)
              const SizedBox(
                height: 160,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (snapshot.hasError)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Error: ${snapshot.error}'),
              )
            else
              _buildEngramsList(context, snapshot.data!),
          ],
        );
      },
    );
  }

  /// Order every list so it reads sensibly instead of in daemon row order:
  /// due/overdue items first (soonest due first), then weak points, then
  /// everything else — with the original response order as a stable
  /// tiebreak. Groups (bubble/note/type/concept) keep this order inside
  /// them because the grouping builders consume this ordering directly.
  List<Engram> _inSensibleOrder(List<Engram> engrams) {
    final now = DateTime.now();
    final indexed = <(int, Engram)>[
      for (var i = 0; i < engrams.length; i++) (i, engrams[i]),
    ];
    indexed.sort((a, b) {
      int rank(Engram e) {
        final at = e.scheduledAt;
        final due =
            at != null && !at.isAfter(now)
                ? 0
                : at != null
                ? 1
                : 2;
        final weak = e.tags.contains('weak_point') ? 0 : 1;
        return due * 10 + weak;
      }

      final ra = rank(a.$2);
      final rb = rank(b.$2);
      if (ra != rb) return ra.compareTo(rb);
      final sa = a.$2.scheduledAt;
      final sb = b.$2.scheduledAt;
      if (sa != null && sb != null && !sa.isAtSameMomentAs(sb)) {
        return sa.compareTo(sb);
      }
      return a.$1.compareTo(b.$1);
    });
    return [for (final (_, e) in indexed) e];
  }

  /// Needs-your-attention (collapsible) on top, then the browse list —
  /// grouped by bubble, note, or type depending on `_browseMode` and filtered
  /// by the due-status + type chips. The client-side chips apply only to the
  /// browse list; the server-side severity/level chips (in the weak-point
  /// header) refetch and apply to the whole section payload, weak points
  /// included. The weak-point block stays exempt from the *client* filters —
  /// it is the "look here first" surface, and the dashboard due-today strip
  /// already answers "what is due". Embedded into the page ListView, so it
  /// never scrolls itself.
  Widget _buildEngramsList(BuildContext context, EngramsViewData view) {
    final engrams = view.response.engrams;
    if (engrams.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Text(
          // A server filter that matched nothing is not "no engrams yet" —
          // one is an empty library, the other an empty result.
          _cognitiveLevel != null || _severity != null
              ? 'No engrams match these filters.'
              : 'No engrams yet.',
        ),
      );
    }

    final ordered = _inSensibleOrder(engrams);
    final weakPoint = ordered.where(isWeakPoint).toList();
    final regular = ordered.where((e) => !isWeakPoint(e)).toList();
    final filtered = regular.where(_passesDue).where(_passesType).toList();

    // Severity + level options come from the payload itself — no invented
    // vocabulary. Facet-style: once a server filter narrows the list, the
    // remaining options narrow with it.
    final severities = _distinctSeverities(engrams);
    final levels = _distinctLevels(engrams);

    return ListView(
      padding: const EdgeInsets.all(16),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        if (weakPoint.isNotEmpty) ...[
          _buildWeakPointSection(
            context,
            weakPoint,
            view,
            severities: severities,
            levels: levels,
          ),
          const SizedBox(height: 20),
        ],
        if (regular.isNotEmpty) ...[
          if (weakPoint.isEmpty) ...[
            _buildServerFilterChips(context, severities, levels),
            const SizedBox(height: 8),
          ],
          _buildBrowseModeSelector(context),
          const SizedBox(height: 8),
          _buildFilters(context),
          const SizedBox(height: 12),
          if (filtered.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('No engrams match these filters.'),
            )
          else
            _buildBrowseList(context, filtered, view),
        ],
      ],
    );
  }

  /// All / By bubble / By note / By type segmented control for the browse
  /// list beneath Needs your attention.
  Widget _buildBrowseModeSelector(BuildContext context) {
    return SegmentedButton<_EngramBrowseMode>(
      segments: const [
        ButtonSegment(
          value: _EngramBrowseMode.byBubble,
          label: Text('By bubble'),
        ),
        ButtonSegment(value: _EngramBrowseMode.byNote, label: Text('By note')),
        ButtonSegment(value: _EngramBrowseMode.byType, label: Text('By type')),
      ],
      selected: {_browseMode},
      onSelectionChanged: (selection) {
        setState(() => _browseMode = selection.first);
      },
    );
  }

  /// Compact, instant filter chips for the browse list: due status
  /// (single-select) and type (multi-select). They act on whatever payload
  /// is loaded — no network. The server-side severity + cognitive-level
  /// chips do NOT live here; they are in the Needs-your-attention header
  /// ([_buildServerFilterChips]) because they refetch the whole section,
  /// weak points included.
  Widget _buildFilters(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        for (final f in _DueFilter.values)
          ChoiceChip(
            label: Text(_dueFilterLabel(f)),
            selected: _dueFilter == f,
            visualDensity: VisualDensity.compact,
            onSelected: (_) => setState(() => _dueFilter = f),
          ),
        for (final t in EngramType.values)
          FilterChip(
            avatar: Icon(engramTypeIcon(t), size: 15),
            label: Text(engramTypeLabel(t)),
            selected: _typeFilter.contains(t),
            visualDensity: VisualDensity.compact,
            onSelected:
                (on) => setState(
                  () => on ? _typeFilter.add(t) : _typeFilter.remove(t),
                ),
          ),
      ],
    );
  }

  /// Daemon-authoritative list filters: severity + cognitive level. They
  /// refetch through `widget.refetch` (`listEngrams`
  /// `severity`/`cognitive_level` params) and apply to the WHOLE section,
  /// weak points included — which is why they sit in the Needs-your-
  /// attention header instead of the browse list.
  ///
  /// Options come from the current payload — no invented vocabulary:
  /// severities from whatever values the engrams (or their short-question
  /// items) actually carry, levels from distinct `target_cognitive_level`
  /// values. Facet-style: an active server filter narrows what the refetch
  /// returns, so the option pool narrows with it.
  Widget _buildServerFilterChips(
    BuildContext context,
    List<String> severities,
    List<int> levels,
  ) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        for (final s in severities)
          FilterChip(
            avatar: Icon(
              Icons.circle,
              size: 12,
              color: _severityColor(context, s),
            ),
            label: Text(_severityLabel(s)),
            selected: _severity == s,
            visualDensity: VisualDensity.compact,
            onSelected:
                (_) => _setServerFilter(
                  cognitiveLevel: _cognitiveLevel,
                  severity: _severity == s ? null : s,
                ),
          ),
        for (final l in levels)
          FilterChip(
            label: Text('Level $l'),
            selected: _cognitiveLevel == l,
            visualDensity: VisualDensity.compact,
            onSelected:
                (_) => _setServerFilter(
                  cognitiveLevel: _cognitiveLevel == l ? null : l,
                  severity: _severity,
                ),
          ),
      ],
    );
  }

  /// Every severity value an engram (or one of its short-question items)
  /// carries. The per-engram FILTER decision stays with the daemon — this
  /// only feeds the chip option pool.
  Iterable<String> _engramSeverities(Engram e) => switch (e.type) {
    EngramType.shortQuestion => (e.content as ShortQuestionContent).questions
        .map((q) => q.severity),
    EngramType.mcq => [(e.content as McqContent).severity],
    EngramType.flashcard => [(e.content as FlashcardContent).severity],
    EngramType.longQuestion => [(e.content as LongQuestionContent).severity],
    EngramType.unknown => const [],
  };

  /// Distinct severities in the payload, daemon vocabulary first
  /// (high/medium/low — see gap_models.severityRank), unknown values after
  /// alphabetically.
  List<String> _distinctSeverities(List<Engram> es) {
    final set = <String>{};
    for (final e in es) {
      set.addAll(_engramSeverities(e));
    }
    const rank = {'high': 0, 'medium': 1, 'low': 2};
    return set.toList()..sort((a, b) {
      final ra = rank[a];
      final rb = rank[b];
      if (ra != null && rb != null) return ra.compareTo(rb);
      if (ra != null) return -1;
      if (rb != null) return 1;
      return a.compareTo(b);
    });
  }

  /// Distinct cognitive levels (target_cognitive_level) present in the
  /// payload, ascending. Level meaning is daemon-owned (scheduler
  /// cognitive-level promotion) — chips just expose the numbers the daemon
  /// emitted, no invented taxonomy.
  List<int> _distinctLevels(List<Engram> es) =>
      es.map((e) => e.targetCognitiveLevel).toSet().toList()..sort();

  String _severityLabel(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  Color _severityColor(BuildContext context, String s) => switch (s) {
    'high' => context.cerebrum.status.dangerSoft,
    'medium' => context.cerebrum.status.warningSoft,
    'low' => context.cerebrum.status.successSoft,
    _ => context.cerebrum.surface.outlineStrong,
  };

  Widget _buildBrowseList(
    BuildContext context,
    List<Engram> regular,
    EngramsViewData view,
  ) {
    switch (_browseMode) {
      case _EngramBrowseMode.byBubble:
        return _buildByBubble(context, regular, view);
      case _EngramBrowseMode.byNote:
        return _buildByNote(context, regular, view);
      case _EngramBrowseMode.byType:
        return _buildByType(context, regular, view);
    }
  }

  String _bubbleLabel(EngramsViewData view, String bubbleId) {
    if (bubbleId.isEmpty) return 'Other';
    return view.bubbleNames[bubbleId] ?? bubbleId;
  }

  String _noteLabel(EngramsViewData view, String bubbleId, String noteId) {
    if (bubbleId.isEmpty) return noteId;
    final titles = view.noteTitles[bubbleId];
    if (titles == null) return noteId;
    return titles[noteId] ?? noteId;
  }

  /// One engram row, shared by every grouping. `contentPadding` is zeroed in
  /// the weak-point block (inside its own padded container) and left at the
  /// ListTile default inside expansion groups.
  Widget _engramTile(
    EngramsViewData view,
    Engram e, {
    required String subtitle,
    EdgeInsetsGeometry contentPadding = const EdgeInsets.symmetric(
      horizontal: 16,
    ),
  }) {
    return ListTile(
      dense: true,
      contentPadding: contentPadding,
      leading: Icon(engramTypeIcon(e.type), size: 18),
      title: Text(
        engramPreview(e),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => widget.onEngramTap(e),
    );
  }

  /// "Needs your attention": collapsed to `_weakPointCollapsedLimit` items
  /// (across all concepts, concept order preserved) by default, with a
  /// toggle to show the rest. Grouped by concept label (the daemon's
  /// `weak_point` + Concept Name tags) whenever expanded past one concept.
  ///
  /// Hosts the server-side severity + cognitive-level filters: a single
  /// compact Filter chip in the header trail (all that trailing slot fits)
  /// toggles the chip panel beneath it. This block is the section's primary
  /// surface, so the daemon-filter controls live here rather than hidden
  /// under the browse-list mode selector. Filtering applies to the whole
  /// section, weak points included.
  Widget _buildWeakPointSection(
    BuildContext context,
    List<Engram> weakPoint,
    EngramsViewData view, {
    List<String> severities = const [],
    List<int> levels = const [],
  }) {
    final byConcept = <String, List<Engram>>{};
    for (final e in weakPoint) {
      byConcept.putIfAbsent(weakPointConcept(e), () => []).add(e);
    }
    final conceptOrder =
        byConcept.keys.toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    // Flatten in concept order so the collapsed view still respects
    // grouping (doesn't cut off mid-concept in a confusing way) while
    // keeping the "first N items" logic simple.
    final orderedConcepts = _weakPointExpanded ? conceptOrder : <String>[];
    var shown = 0;
    if (!_weakPointExpanded) {
      for (final concept in conceptOrder) {
        if (shown >= _weakPointCollapsedLimit) break;
        orderedConcepts.add(concept);
        shown += byConcept[concept]!.length;
      }
    }
    final visibleConcepts = _weakPointExpanded ? conceptOrder : orderedConcepts;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.errorContainer.withValues(alpha: 0.35),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                size: 16,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(width: 6),
              Row(
                children: [
                  Text(
                    'Needs your attention',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(width: 8),
                  Text(
                    '${weakPoint.length}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              const Spacer(),
              if (severities.isNotEmpty || levels.isNotEmpty)
                FilterChip(
                  avatar: const Icon(Icons.filter_list, size: 15),
                  label: const Text('Filter'),
                  selected: _filterPanelOpen,
                  visualDensity: VisualDensity.compact,
                  onSelected: (on) => setState(() => _filterPanelOpen = on),
                ),
            ],
          ),
          if (_filterPanelOpen) ...[
            const SizedBox(height: 8),
            _buildServerFilterChips(context, severities, levels),
          ],
          const SizedBox(height: 8),
          for (final concept in visibleConcepts) ...[
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 2),
              child: Text(
                concept,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            for (final e in byConcept[concept]!)
              _engramTile(
                view,
                e,
                subtitle:
                    '${_noteLabel(view, e.bubbleId ?? '', e.noteId)} · '
                    '${engramTypeLabel(e.type)}',
                contentPadding: EdgeInsets.zero,
              ),
          ],
          if (weakPoint.length > _weakPointCollapsedLimit)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed:
                    () => setState(
                      () => _weakPointExpanded = !_weakPointExpanded,
                    ),
                child: Text(
                  _weakPointExpanded
                      ? 'Show less'
                      : 'Show all (${weakPoint.length})',
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Grouping 1: bubble → note. Each bubble is a card; each note inside it
  /// is a collapsed expansion group. This is the original default layout.
  Widget _buildByBubble(
    BuildContext context,
    List<Engram> regular,
    EngramsViewData view,
  ) {
    final byBubble = <String, List<Engram>>{};
    for (final e in regular) {
      byBubble.putIfAbsent(e.bubbleId ?? '', () => []).add(e);
    }
    final bubbleOrder =
        byBubble.keys.toList()..sort((a, b) {
          final na = view.bubbleNames[a] ?? a;
          final nb = view.bubbleNames[b] ?? b;
          return na.toLowerCase().compareTo(nb.toLowerCase());
        });

    return Column(
      children: [
        for (final bubbleId in bubbleOrder)
          _buildBubbleSection(context, bubbleId, byBubble[bubbleId]!, view),
      ],
    );
  }

  /// One bubble's engrams: bubble header + per-note expansion groups.
  Widget _buildBubbleSection(
    BuildContext context,
    String bubbleId,
    List<Engram> engrams,
    EngramsViewData view,
  ) {
    final byNote = <String, List<Engram>>{};
    for (final e in engrams) {
      byNote.putIfAbsent(e.noteId, () => []).add(e);
    }
    final noteOrder =
        byNote.keys.toList()..sort((a, b) {
          final na = _noteLabel(view, bubbleId, a).toLowerCase();
          final nb = _noteLabel(view, bubbleId, b).toLowerCase();
          return na.compareTo(nb);
        });

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                const Icon(Icons.bubble_chart, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _bubbleLabel(view, bubbleId),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  '${engrams.length}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          for (final noteId in noteOrder)
            _buildNoteGroup(
              context,
              noteId,
              byNote[noteId]!,
              view,
              bubbleIdOverride: bubbleId,
            ),
        ],
      ),
    );
  }

  /// Grouping 2: note only, regardless of which bubble it's in. Useful
  /// once you have more bubbles than you want to scroll through to find
  /// one note. Bubble name shows as a subtitle instead of a header.
  Widget _buildByNote(
    BuildContext context,
    List<Engram> regular,
    EngramsViewData view,
  ) {
    // Key by bubbleId + noteId, not noteId alone -- two notes in
    // different bubbles could otherwise collide if ids aren't globally
    // unique. TODO(backend): confirm note_id uniqueness scope; if it's
    // globally unique this key can drop the bubble prefix.
    final byNoteKey = <String, List<Engram>>{};
    for (final e in regular) {
      final key = '${e.bubbleId ?? ''}::${e.noteId}';
      byNoteKey.putIfAbsent(key, () => []).add(e);
    }
    final keyOrder =
        byNoteKey.keys.toList()..sort((a, b) {
          final ea = byNoteKey[a]!.first;
          final eb = byNoteKey[b]!.first;
          final na =
              _noteLabel(view, ea.bubbleId ?? '', ea.noteId).toLowerCase();
          final nb =
              _noteLabel(view, eb.bubbleId ?? '', eb.noteId).toLowerCase();
          return na.compareTo(nb);
        });

    return Card(
      child: Column(
        children: [
          for (final key in keyOrder)
            _buildNoteGroup(
              context,
              byNoteKey[key]!.first.noteId,
              byNoteKey[key]!,
              view,
              showBubbleSubtitle: true,
            ),
        ],
      ),
    );
  }

  /// One note's engrams: an expansion group titled by the note's real
  /// name. `bubbleIdOverride` is used from the by-bubble grouping (bubble
  /// is already known, no need to look it up per-engram); otherwise the
  /// first engram's own bubbleId is used. `showBubbleSubtitle` adds the
  /// bubble name beneath the note name, for the by-note grouping where
  /// there's no enclosing bubble header to provide that context.
  Widget _buildNoteGroup(
    BuildContext context,
    String noteId,
    List<Engram> engrams,
    EngramsViewData view, {
    String? bubbleIdOverride,
    bool showBubbleSubtitle = false,
  }) {
    final sample = engrams.first;
    final bubbleId = bubbleIdOverride ?? sample.bubbleId ?? '';
    final noteLabel = _noteLabel(view, bubbleId, noteId);
    final subtitle =
        showBubbleSubtitle
            ? '${_bubbleLabel(view, bubbleId)} · ${engrams.length} item(s)'
            : '${engrams.length} item(s)';

    return ExpansionTile(
      leading: const Icon(Icons.description_outlined, size: 18),
      title: Text(
        noteLabel,
        style: const TextStyle(fontSize: 13),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(subtitle),
      children: [
        for (final e in engrams)
          _engramTile(view, e, subtitle: engramTypeLabel(e.type)),
      ],
    );
  }

  /// Grouping 3: engram type (MCQ, flashcard, etc). Each type is a
  /// collapsed expansion group with a bubble · note subtitle per item, so
  /// you can find "all the flashcards" without caring which bubble/note
  /// they came from.
  Widget _buildByType(
    BuildContext context,
    List<Engram> regular,
    EngramsViewData view,
  ) {
    final byType = <EngramType, List<Engram>>{};
    for (final e in regular) {
      byType.putIfAbsent(e.type, () => []).add(e);
    }
    const typeOrder = [
      EngramType.mcq,
      EngramType.flashcard,
      EngramType.shortQuestion,
      EngramType.longQuestion,
      EngramType.unknown,
    ];

    return Card(
      child: Column(
        children: [
          for (final type in typeOrder)
            if (byType[type] != null && byType[type]!.isNotEmpty)
              ExpansionTile(
                leading: Icon(engramTypeIcon(type), size: 18),
                title: Text(
                  engramTypeLabel(type),
                  style: const TextStyle(fontSize: 13),
                ),
                subtitle: Text('${byType[type]!.length} item(s)'),
                children: [
                  for (final e in byType[type]!)
                    _engramTile(
                      view,
                      e,
                      subtitle:
                          '${_bubbleLabel(view, e.bubbleId ?? '')} · '
                          '${_noteLabel(view, e.bubbleId ?? '', e.noteId)}',
                    ),
                ],
              ),
        ],
      ),
    );
  }
}
