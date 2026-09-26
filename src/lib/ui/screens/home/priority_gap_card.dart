import 'package:cerebrum/ui/themes/theme_access.dart';
import 'package:flutter/material.dart';

import '../../../models/gap_models.dart';
import 'gap_repository.dart';

/// Right-column "needs your attention" widget: the single highest-severity
/// gap across every study bubble, styled compact for a sidebar slot rather
/// than a full-width hero (the redesign puts continuity -- [Quickview] --
/// in the strong/prominent position; this is the urgent-but-secondary
/// notice beside it). [GapCard] still holds the full per-bubble breakdown
/// further down the page; this and that widget share [topPriorityGapAcross]
/// so they always agree on which item is "the priority" and don't repeat it.
///
/// Same honesty + refresh rules as GapCard: renders nothing when no gap
/// carries a real daemon severity, serves the last-known cache instantly,
/// and a failed background refresh never blanks what's already shown.

/// Returns a short scope label: chunk-specific gaps say which section the
/// gap lives in (the excerpt lead); note-wide gaps carry no block target.
String _scopeLabel(GapItem item) {
  final evidence = item.evidence.isNotEmpty ? item.evidence.first : null;
  if (evidence != null && evidence.blockIds.isNotEmpty) {
    final lead = evidence.excerpt;
    if (lead != null) {
      final first = lead
          .split('\n')
          .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
      return 'In: $first';
    }
    return 'In: this section';
  }
  return 'Note-wide gap';
}

class PriorityGapCard extends StatefulWidget {
  final GapRepository repository;

  /// Called when the person taps "Review". Left to the caller because
  /// opening the underlying note/evidence is a navigation decision this
  /// widget shouldn't own.
  final void Function(GapItem item)? onReview;

  const PriorityGapCard({
    super.key,
    this.repository = const LiveGapRepository(),
    this.onReview,
  });

  @override
  State<PriorityGapCard> createState() => _PriorityGapCardState();
}

class _PriorityGapCardState extends State<PriorityGapCard>
    with WidgetsBindingObserver {
  GapItem? _priority;
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

  Future<void> _bootstrap() async {
    final cached = await widget.repository.cached();
    if (!mounted) return;
    setState(() => _priority = topPriorityGapAcross(cached));
    await _refresh(background: true);
  }

  Future<void> _refresh({bool background = false}) async {
    if (_fetching) return;
    _fetching = true;
    try {
      final summaries = await widget.repository.refresh();
      if (!mounted) return;
      final next = topPriorityGapAcross(summaries);
      setState(() {
        _priority = summaries.isEmpty ? _priority : next;
        _loading = false;
      });
    } finally {
      _fetching = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();

    final item = _priority;
    if (item == null) {
      // No gap carries a real severity — silent empty state.
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.cerebrum.status.dangerSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(color: context.cerebrum.status.danger, width: 4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.priority_high_rounded,
                size: 16,
                color: context.cerebrum.status.dangerDeep,
              ),
              const SizedBox(width: 6),
              Text(
                'Needs your attention',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: context.cerebrum.status.dangerDeep,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          if (item.detail != null && item.detail!.trim().isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              item.detail!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: context.cerebrum.text.muted,
              ),
            ),
          ],
          const SizedBox(height: 8),
          // Scope indicator: chunk-specific gaps carry block linkage (the
          // "Review" button deep-links to the chunk); note-wide gaps (from
          // the overview) have no block target.
          Text(
            _scopeLabel(item),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: context.cerebrum.status.dangerDeep,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              onPressed:
                  widget.onReview == null ? null : () => widget.onReview!(item),
              child: const Text('Review'),
            ),
          ),
        ],
      ),
    );
  }
}
