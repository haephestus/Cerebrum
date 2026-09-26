import 'package:cerebrum/ui/themes/theme_access.dart';
import 'package:cerebrum/ui/widgets/learning_center/gantt/study_plan_phase_gantt.dart';
import 'package:flutter/material.dart';
// ===========================================================================
// Floating detail sheet: everything that doesn't fit on the timeline.
// ===========================================================================

class PhaseDetailSheet extends StatelessWidget {
  final Map<String, dynamic> phase;
  final String statusLabel;
  final Color statusColor;
  final List<Map<String, dynamic>> metrics;
  final String? targetRole;
  final String? guidingPrinciple;
  final List<Map<String, dynamic>>? weeks;
  final bool loadingWeeks;
  final bool showDensify;
  final bool densifying;
  final VoidCallback? onDensify;
  final Future<void> Function(int taskId) onCompleteTask;
  final Future<void> Function(int taskId) onReopenTask;
  final VoidCallback onClose;

  const _PhaseDetailSheet({
    required this.phase,
    required this.statusLabel,
    required this.statusColor,
    required this.metrics,
    required this.targetRole,
    required this.guidingPrinciple,
    required this.weeks,
    required this.loadingWeeks,
    required this.showDensify,
    required this.densifying,
    required this.onDensify,
    required this.onCompleteTask,
    required this.onReopenTask,
    required this.onClose,
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
    final tracks = phase['tracks_json'];
    final Map<String, dynamic> tracksMap =
        tracks is Map ? Map<String, dynamic>.from(tracks) : <String, dynamic>{};

    // Floating card chrome: rounded, elevated, with a labeled header and
    // close button. The body scrolls independently of the gantt behind it.
    return Material(
      color: theme.colorScheme.surface,
      elevation: 8,
      shadowColor: context.cerebrum.text.strong.withValues(alpha: 0.25),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    phase['phase_label']?.toString() ?? 'Phase',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  onPressed: onClose,
                  icon: const Icon(Icons.close, size: 20),
                  tooltip: 'Close',
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              children: [
                if (targetRole != null) ...[
                  Text(
                    targetRole!,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                Row(
                  children: [
                    StudyPlanPhaseGantt.statusPill(statusLabel, statusColor),
                    const SizedBox(width: 8),
                    Text(
                      'Months ${phase['month_start']}\u2013${phase['month_end']}',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
                if (guidingPrinciple != null) ...[
                  const SizedBox(height: 16),
                  _sectionLabel(context, 'Guiding principle'),
                  const SizedBox(height: 4),
                  Text(
                    guidingPrinciple!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
                if (phase['theme'] != null) ...[
                  const SizedBox(height: 16),
                  _sectionLabel(context, 'Theme'),
                  const SizedBox(height: 4),
                  Text(
                    phase['theme'].toString(),
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
                if (phase['milestone'] != null) ...[
                  const SizedBox(height: 16),
                  _sectionLabel(context, 'Milestone'),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.flag_outlined,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          phase['milestone'].toString(),
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ],
                if (tracksMap.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _sectionLabel(context, 'Tracks'),
                  const SizedBox(height: 6),
                  ...tracksMap.entries.map(
                    (e) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e.key,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            e.value.toString(),
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                if (metrics.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _sectionLabel(context, 'Checkpoints'),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final m in metrics)
                        StudyPlanPhaseGantt.tag(
                          context,
                          '${m['month_marker']} ${m['checkpoint']}',
                          context.cerebrum.brand.primaryDeep,
                          icon: Icons.flag_outlined,
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                _sectionLabel(context, 'Weeks'),
                const SizedBox(height: 6),
                if (loadingWeeks)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: LinearProgressIndicator(),
                  )
                else if (weeks == null || weeks!.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'No week detail generated for this phase yet.',
                      style: theme.textTheme.bodySmall,
                    ),
                  )
                else
                  ...weeks!.map((w) {
                    final status = w['status']?.toString() ?? 'pending';
                    final topics = _weekTopics(w);
                    final days = List<Map<String, dynamic>>.from(
                      w['days'] as List? ?? [],
                    );
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      clipBehavior: Clip.antiAlias,
                      child: ExpansionTile(
                        // Land on the active week expanded so "this week's"
                        // checkable tasks are the default view — every other
                        // week is one tap away (the phase → week → task zoom
                        // this detail sheet exists for).
                        initiallyExpanded: status == 'active',
                        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                        childrenPadding: const EdgeInsets.only(bottom: 4),
                        leading: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: _weekColor(context, status),
                            shape: BoxShape.circle,
                          ),
                        ),
                        title: Text(
                          'Week ${w['week_number']}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        subtitle:
                            w['focus_summary'] != null
                                ? Text(
                                  w['focus_summary'].toString(),
                                  style: theme.textTheme.bodySmall,
                                )
                                : null,
                        children: [
                          if (topics.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                              child: Wrap(
                                spacing: 4,
                                runSpacing: 4,
                                children: [
                                  for (final t in topics)
                                    StudyPlanPhaseGantt.tag(
                                      context,
                                      t.toString(),
                                      context.cerebrum.status.success,
                                    ),
                                ],
                              ),
                            ),
                          if (days.isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(
                                left: 16,
                                bottom: 12,
                              ),
                              child: Text(
                                'No tasks generated for this week yet.',
                                style: theme.textTheme.bodySmall,
                              ),
                            )
                          else
                            ...days.map(
                              (day) => StudyPlanDayCard(
                                day: day,
                                onCompleteTask: onCompleteTask,
                                onReopenTask: onReopenTask,
                                expandToday: status == 'active',
                              ),
                            ),
                        ],
                      ),
                    );
                  }),
                if (showDensify) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: densifying ? null : onDensify,
                    icon:
                        densifying
                            ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : const Icon(Icons.auto_awesome, size: 16),
                    label: Text(
                      densifying
                          ? 'Generating\u2026'
                          : weeks == null || weeks!.isEmpty
                          ? 'Generate this week'
                          : 'Generate more week detail',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String text) {
    return Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        letterSpacing: 0.6,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  /// Daemon weeks payload carries `topics` — the read path pops
  /// `topics_json` into `topics` (Cross-repo contract for the weeks
  /// route). Fall back to `topics_json` for any pre-contract payload.
  List<dynamic> _weekTopics(Map<String, dynamic> w) {
    final topics = w['topics'];
    if (topics is List) return topics;
    final legacy = w['topics_json'];
    return legacy is List ? legacy : const [];
  }
}
