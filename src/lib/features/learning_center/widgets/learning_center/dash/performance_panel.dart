import 'package:flutter/material.dart';
import 'package:cerebrum/models/performance_metrics.dart';

/// Mastery/streak show "--" until metrics_api.dart has a real
/// implementation (see the TODO there) -- never a made-up number.
/// Weak-point concepts are real: passed in from the same tag-based
/// grouping the engrams section already uses.
class PerformancePanel extends StatelessWidget {
  final PerformanceMetrics? metrics;
  final Map<String, int> weakPointConcepts;
  final void Function(String concept) onConceptTap;

  const PerformancePanel({
    super.key,
    required this.metrics,
    required this.weakPointConcepts,
    required this.onConceptTap,
  });

  @override
  Widget build(BuildContext context) {
    final concepts =
        weakPointConcepts.keys.toList()..sort(
          (a, b) => weakPointConcepts[b]!.compareTo(weakPointConcepts[a]!),
        );

    return Container(
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  label: 'Mastery',
                  value:
                      metrics != null
                          ? '${metrics!.masteryPercent.round()}%'
                          : '--',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatTile(
                  label: 'Streak',
                  value: metrics != null ? '${metrics!.streakDays}d' : '--',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.errorContainer.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 15,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Needs attention',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (concepts.isEmpty)
                  Text(
                    'No weak points flagged right now.',
                    style: Theme.of(context).textTheme.bodySmall,
                  )
                else
                  for (final concept in concepts)
                    InkWell(
                      onTap: () => onConceptTap(concept),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                concept,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Theme.of(context).colorScheme.error,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              '${weakPointConcepts[concept]}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            Icon(
                              Icons.chevron_right,
                              size: 14,
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ],
                        ),
                      ),
                    ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;

  const _StatTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 2),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
