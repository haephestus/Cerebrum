import 'package:flutter/material.dart';

import 'gap_models.dart';
import 'gap_repository.dart';

/// Paged "gap reports & findings" surface: one page per study bubble's full
/// analysis breakdown, swipeable/page-turnable, ordered as a best-effort
/// "most recent analysis first".
///
/// RECENCY CAVEAT: [GapEvidence] has no real analyzed-at timestamp -- only
/// `analysisVersion`, a per-note version counter. This widget approximates
/// "most recent" by the highest `analysisVersion` seen among a bubble's
/// items, which is a reasonable proxy (higher version = a later re-analysis
/// of that note) but not a true chronological sort across bubbles that were
/// analyzed on different days. See the fuller note in d_homescreen_page.dart
/// for what a real fix needs.
///
/// Same honesty rules as GapCard/PriorityGapCard: instant last-known cache,
/// background daemon refresh, silent empty state, never blanks shown data
/// on a failed refresh. Also shares [topPriorityGapAcross] so whatever
/// PriorityGapCard already promoted to the dashboard's attention widget
/// doesn't repeat here.
class GapFindingsCarousel extends StatefulWidget {
  final GapRepository repository;

  const GapFindingsCarousel({
    super.key,
    this.repository = const LiveGapRepository(),
  });

  @override
  State<GapFindingsCarousel> createState() => _GapFindingsCarouselState();
}

class _GapFindingsCarouselState extends State<GapFindingsCarousel>
    with WidgetsBindingObserver {
  Map<String, BubbleGapSummary> _summaries = const {};
  bool _loading = true;
  bool _fetching = false;
  final PageController _pageController = PageController();
  int _page = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh(background: true);
  }

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
        _summaries = summaries.isEmpty ? _summaries : summaries;
        _loading = false;
      });
    } finally {
      _fetching = false;
    }
  }

  /// Proxy recency: the highest analysisVersion among a bubble's items.
  double _recencyProxy(BubbleGapSummary summary) {
    var best = -1.0;
    for (final item in summary.items) {
      for (final e in item.evidence) {
        final v = e.analysisVersion?.toDouble();
        if (v != null && v > best) best = v;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 260,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_summaries.isEmpty) {
      // Silent empty state: no grounded gaps anywhere → nothing to page.
      return const SizedBox.shrink();
    }

    final priorityItem = topPriorityGapAcross(_summaries);
    final priorityKey = priorityItem == null ? null : gapItemKey(priorityItem);

    // Filter the promoted item out of each bubble, then drop bubbles left
    // with nothing to show, then sort by the recency proxy (desc).
    final pages =
        _summaries.values
            .map(
              (s) =>
                  priorityKey == null
                      ? s
                      : BubbleGapSummary(
                        bubbleId: s.bubbleId,
                        bubbleName: s.bubbleName,
                        items:
                            s.items
                                .where((i) => gapItemKey(i) != priorityKey)
                                .toList(),
                      ),
            )
            .where((s) => !s.isEmpty)
            .toList()
          ..sort((a, b) => _recencyProxy(b).compareTo(_recencyProxy(a)));

    if (pages.isEmpty) return const SizedBox.shrink();
    if (_page >= pages.length) _page = 0;

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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Gap reports & findings',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Most recently analyzed bubble first.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed:
                        _page > 0
                            ? () => _pageController.previousPage(
                              duration: const Duration(milliseconds: 200),
                              curve: Curves.easeOut,
                            )
                            : null,
                  ),
                  Text(
                    '${_page + 1} / ${pages.length}',
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed:
                        _page < pages.length - 1
                            ? () => _pageController.nextPage(
                              duration: const Duration(milliseconds: 200),
                              curve: Curves.easeOut,
                            )
                            : null,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 320,
            child: PageView.builder(
              controller: _pageController,
              itemCount: pages.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder:
                  (context, i) => _BubbleFindingsPage(summary: pages[i]),
            ),
          ),
        ],
      ),
    );
  }
}

class _BubbleFindingsPage extends StatelessWidget {
  final BubbleGapSummary summary;

  const _BubbleFindingsPage({required this.summary});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      padding: const EdgeInsets.all(14),
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
                  summary.bubbleName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (summary.countLine.isNotEmpty)
                Text(
                  summary.countLine,
                  style: const TextStyle(fontSize: 11, color: Colors.black54),
                ),
            ],
          ),
          const Divider(height: 20),
          Expanded(
            child: ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: summary.items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) => _FindingRow(item: summary.items[i]),
            ),
          ),
        ],
      ),
    );
  }
}

class _FindingRow extends StatelessWidget {
  final GapItem item;

  const _FindingRow({required this.item});

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
                  evidence.analysisVersion != null
                      ? '${evidence.noteTitle} · v${evidence.analysisVersion!}'
                      : evidence.noteTitle,
                  style: const TextStyle(fontSize: 10, color: Colors.black45),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
