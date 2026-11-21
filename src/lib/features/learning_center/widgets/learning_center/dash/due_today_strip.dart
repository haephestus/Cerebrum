import 'package:flutter/material.dart';
import 'package:cerebrum/models/engram_models.dart';

/// Horizontal strip of engrams due today. Presentation-only: the caller
/// decides what "due" means and how to label/preview each engram, so this
/// widget doesn't need to change once real due-date filtering exists (see
/// the TODO on DLearningCenterPage._dueTodayEngrams).
class DueTodayStrip extends StatelessWidget {
  final List<Engram> engrams;
  final IconData Function(EngramType) typeIconOf;
  final String Function(EngramType) typeLabelOf;
  final String Function(Engram) previewTextOf;
  final void Function(Engram) onTap;

  const DueTodayStrip({
    super.key,
    required this.engrams,
    required this.typeIconOf,
    required this.typeLabelOf,
    required this.previewTextOf,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Due today',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            Text(
              '${engrams.length} item(s)',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (engrams.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Nothing due today.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          )
        else
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: engrams.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final e = engrams[i];
                return _DueCard(
                  icon: typeIconOf(e.type),
                  label: typeLabelOf(e.type),
                  preview: previewTextOf(e),
                  onTap: () => onTap(e),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _DueCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String preview;
  final VoidCallback onTap;

  const _DueCard({
    required this.icon,
    required this.label,
    required this.preview,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        width: 180,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, size: 18),
            // Overflow-proof by construction: preview and label are
            // flex children, so icon + text ALWAYS fit the fixed height
            // of the card — at any text scale, preview absorbs the
            // slack and trims, never throws (live RenderFlex overflow
            // bug: 2-line preview exceeded the 96px card at real fonts).
            // Never "fix" this back to a taller card or maxLines: 2 —
            // that only moves the overflow threshold.
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  preview,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
