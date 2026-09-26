import 'package:cerebrum/ui/themes/theme_access.dart';
import 'package:cerebrum/ui/widgets/learning_center/gantt/study_plan_phase_gantt.dart';
import 'package:flutter/material.dart';
// ===========================================================================
// Compact card on the timeline: identity + status + week-resolution ticks.
// Everything else lives in the detail sheet.
// ===========================================================================

class _PhaseCard extends StatelessWidget {
  final Map<String, dynamic> phase;
  final String statusLabel;
  final Color statusColor;
  final List<Map<String, dynamic>>? weeks;
  final bool loadingWeeks;
  final VoidCallback onTap;

  const _PhaseCard({
    required this.phase,
    required this.statusLabel,
    required this.statusColor,
    required this.weeks,
    required this.loadingWeeks,
    required this.onTap,
  });

  Color _weekColor(BuildContext context, String status) {
    switch (status) {
      case 'complete':
        return context.cerebrum.status.success;
      case 'active':
        return StudyPlanPhaseGantt.currentColor(context);
      default:
        return context.cerebrum.surface.outlineStrong;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final completeCount =
        weeks?.where((w) => w['status'] == 'complete').length ?? 0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        // Original card radius.
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          // Original card chrome: plain surface, outlineVariant border,
          // soft shadow. The active phase is marked by its status pill
          // (and the today marker), not by tinting the whole card.
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: theme.colorScheme.outlineVariant,
              width: 1,
            ),
            color: theme.colorScheme.surface,
            boxShadow: [
              BoxShadow(
                color: context.cerebrum.text.strong.withValues(alpha: 0.06),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    // Original gantt card icon.
                    Icons.view_timeline_outlined,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      phase['phase_label']?.toString() ?? 'Phase',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  StudyPlanPhaseGantt.statusPill(statusLabel, statusColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'M${phase['month_start']}\u2013M${phase['month_end']}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (loadingWeeks)
                const SizedBox(
                  height: 14,
                  width: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (weeks == null || weeks!.isEmpty)
                Text(
                  'No week detail yet',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              else ...[
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (final w in weeks!)
                      Tooltip(
                        message:
                            'Week ${w['week_number']} \u00b7 ${w['status']}',
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color:
                                w['status'] == 'complete'
                                    ? _weekColor(context, 'complete')
                                    : Colors.transparent,
                            border: Border.all(
                              color: _weekColor(
                                context,
                                w['status']?.toString() ?? 'pending',
                              ),
                              width: 1.5,
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child:
                              w['status'] == 'complete'
                                  ? Icon(
                                    Icons.check,
                                    size: 10,
                                    color: context.cerebrum.text.onBrand,
                                  )
                                  : null,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '$completeCount/${weeks!.length} weeks complete',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
