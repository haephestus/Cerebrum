import 'package:flutter/material.dart';

import 'gap_models.dart';
import 'gap_repository.dart';

/// The dashboard's hero: the "what you don't know" surface, per study bubble.
///
/// Homepage-dashboard spec (the soul of the app, not a convenience):
///   - Every gap is grounded data with evidence pointing at the note (and, for
///     chunk-sourced gaps, the excerpt) that produced it.
///   - No meaningful gaps → the whole region shrinks away (silent empty state).
///     The spec bans placeholders that outlive their wireframe purpose.
///   - Suggested reading is the gap's resolution action, ranked from the
///     daemon's grounded `suggested_sources`, never generic picks.
///
/// Refresh strategy mirrors UpcomingEngramsSection: last-known data is served
/// instantly (repository cache), a background daemon pass refreshes on mount
/// and on app resume, and a failed refresh keeps whatever was already shown.
class GapCard extends StatefulWidget {
  final GapRepository repository;

  const GapCard({super.key, this.repository = const LiveGapRepository()});

  @override
  State<GapCard> createState() => _GapCardState();
}

class _GapCardState extends State<GapCard> with WidgetsBindingObserver {
  Map<String, BubbleGapSummary> _summaries = const {};
  bool _loading = true; // only until the FIRST refresh resolves
  bool _fetching = false; // guards against overlapping fetches

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh(background: true);
  }

  /// Serve the last-known rollup instantly, then refresh from the daemon.
  Future<void> _bootstrap() async {
    final cached = await widget.repository.cached();
    if (!mounted) return;
    setState(() => _summaries = cached);
    await _refresh(background: true);
  }

  Future<void> _refresh({bool background = false}) async {
    if (_fetching) return;
    _fetching = true;
    try {
      final summaries = await widget.repository.refresh();
      if (!mounted) return;
      setState(() {
        // An empty daemon pass never blanks last-known data (offline rule).
        _summaries = summaries.isEmpty ? _summaries : summaries;
        _loading = false;
      });
    } finally {
      _fetching = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 150,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_summaries.isEmpty) {
      // Silent empty state: no grounded gaps → nothing to surface.
      return const SizedBox.shrink();
    }

    final bubbles =
        _summaries.values.toList()
          // Cross-bubble rollup: the bubbles with the most severe gaps lead.
          ..sort((a, b) => b.attention.compareTo(a.attention));
    // Same item PriorityGapCard renders as the page's hero — excluded here
    // (by identity, not just bubble) so it never appears twice on screen.
    final priorityItem = topPriorityGapAcross(_summaries);
    final priorityKey = priorityItem == null ? null : gapItemKey(priorityItem);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F1FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE3DEF2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Understanding Gaps',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          const Text(
            'Weak areas and confusions found in your notes\' analysis.',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 8),
          // Sizes to content up to a cap, then scrolls internally — mirrors
          // UpcomingEngramsList; never overflows its parent on resize.
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360),
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: bubbles.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder:
                  (context, i) => _BubbleGapSection(
                    summary: bubbles[i],
                    excludeKey: priorityKey,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BubbleGapSection extends StatelessWidget {
  final BubbleGapSummary summary;

  /// Identity of the item already shown by PriorityGapCard, if any — dropped
  /// from this bubble's list so it doesn't render a second time on the page.
  final String? excludeKey;

  const _BubbleGapSection({required this.summary, this.excludeKey});

  @override
  Widget build(BuildContext context) {
    final filtered = excludeKey == null
        ? summary
        : BubbleGapSummary(
            bubbleId: summary.bubbleId,
            bubbleName: summary.bubbleName,
            items: summary.items
                .where((i) => gapItemKey(i) != excludeKey)
                .toList(),
          );
    // Every item in this bubble was the one promoted to the hero — nothing
    // left to show here, so this bubble's section stays silent too.
    if (filtered.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  filtered.bubbleName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (filtered.countLine.isNotEmpty)
                Text(
                  filtered.countLine,
                  style: const TextStyle(fontSize: 11, color: Colors.black54),
                ),
            ],
          ),
          const SizedBox(height: 8),
          for (final item in filtered.items)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _GapRow(item: item),
            ),
        ],
      ),
    );
  }
}

class _GapRow extends StatelessWidget {
  final GapItem item;

  const _GapRow({required this.item});

  static const _ink = Color(0xFF2F2940);

  @override
  Widget build(BuildContext context) {
    final evidence = item.evidence.isNotEmpty ? item.evidence.first : null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 1),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFFE3DEF2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            item.kind.label,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6C4FCE),
            ),
          ),
        ),
        if (item.severity != null) ...[
          const SizedBox(width: 4),
          Container(
            margin: const EdgeInsets.only(top: 1),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: _severityColor(item.severity!).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              item.severity!.toUpperCase(),
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: _severityColor(item.severity!),
              ),
            ),
          ),
        ],
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: _ink,
                ),
              ),
              if (item.detail != null && item.detail!.trim().isNotEmpty)
                Text(
                  item.detail!,
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              if (evidence != null) ...[
                const SizedBox(height: 2),
                Text(
                  _evidenceLine(evidence),
                  style: const TextStyle(fontSize: 10, color: Colors.black45),
                ),
                if (evidence.excerpt != null &&
                    evidence.excerpt!.trim().isNotEmpty)
                  Text(
                    '"${evidence.excerpt!.trim()}"',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      fontStyle: FontStyle.italic,
                      color: Colors.black38,
                    ),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Evidence is the note + the analysis version that found the gap — a bare
  /// label without it is a spec violation.
  static String _evidenceLine(GapEvidence e) {
    final version = e.analysisVersion != null
        ? ' · v${formatAnalysisVersion(e.analysisVersion!)}'
        : '';
    final state = e.isCurrent ? '' : ' · stale analysis';
    return '${e.noteTitle}$version$state';
  }

  static Color _severityColor(String severity) => switch (severity) {
    'high' => const Color(0xFFB3261E),
    'medium' => const Color(0xFF8A6A00),
    _ => const Color(0xFF5B5B66),
  };
}
