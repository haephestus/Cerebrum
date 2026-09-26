import 'package:cerebrum/ui/themes/theme_access.dart';
import 'package:flutter/material.dart';

/// One day's printable task list with checkable tasks.
///
/// Shared by the phase detail sheet (week drill-down, "select a week and
/// see its tasks") and any checklist surface, so the day/task rendering and
/// checkbox flow live in ONE place instead of being duplicated per widget —
/// see [[features/study-plan-week-detail]]: "week cards expand to days with
/// checkable tasks; reuse _buildDayCard / _completeTask flows".
///
/// Extracted from StudyPlanDetailPage._buildDayCard (dead code removed when
/// the active-week-only checklist was replaced by the full phase timeline).
class StudyPlanDayCard extends StatelessWidget {
  final Map<String, dynamic> day;
  final Future<void> Function(int taskId) onCompleteTask;
  final Future<void> Function(int taskId) onReopenTask;

  /// Whether today's day card starts expanded. The sheet passes this only
  /// for the active week, so "This week" lands expanded without the old
  /// active-week-only checklist being a separate section.
  final bool expandToday;

  const StudyPlanDayCard({
    super.key,
    required this.day,
    required this.onCompleteTask,
    required this.onReopenTask,
    this.expandToday = false,
  });

  static const List<String> _dayNames = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  static String dayName(int dayOfWeek) => _dayNames[dayOfWeek.clamp(0, 6)];

  static int get todayIndex => DateTime.now().weekday - 1;

  static Color taskTypeColor(String type, BuildContext context) {
    switch (type) {
      case 'study':
        return context.cerebrum.gantt.current;
      case 'practice':
        return context.cerebrum.status.success;
      case 'build':
        return context.cerebrum.status.warning;
      case 'review':
        return context.cerebrum.brand.primary;
      case 'milestone_check':
        return context.cerebrum.status.danger;
      default:
        return Theme.of(context).colorScheme.primary;
    }
  }

  static IconData taskTypeIcon(String type) {
    switch (type) {
      case 'study':
        return Icons.menu_book_outlined;
      case 'practice':
        return Icons.fitness_center;
      case 'build':
        return Icons.build_outlined;
      case 'review':
        return Icons.refresh;
      case 'milestone_check':
        return Icons.flag_outlined;
      default:
        return Icons.circle_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tasks = List<Map<String, dynamic>>.from(day['tasks'] as List? ?? []);
    final dayOfWeek = (day['day_of_week'] as num).toInt();
    final isToday = dayOfWeek == todayIndex;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        initiallyExpanded: expandToday && isToday,
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        title: Row(
          children: [
            Text(dayName(dayOfWeek)),
            if (isToday) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: context.cerebrum.gantt.current.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Today',
                  style: TextStyle(
                    color: context.cerebrum.gantt.current,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: Text('${tasks.length} task(s)'),
        children:
            tasks.map((task) {
              final status = task['status'] as String? ?? 'pending';
              final isComplete = status == 'complete';
              final autoResolved = (task['auto_resolved'] as num?) == 1;
              final taskType = task['task_type'] as String? ?? 'study';
              final taskId = (task['task_id'] as num).toInt();

              return ListTile(
                leading: Icon(
                  taskTypeIcon(taskType),
                  color: taskTypeColor(taskType, context),
                ),
                title: Text(
                  task['label']?.toString() ?? '',
                  style: TextStyle(
                    decoration: isComplete ? TextDecoration.lineThrough : null,
                  ),
                ),
                subtitle: Text(
                  [
                    if (task['target_minutes'] != null)
                      '${task['target_minutes']} min',
                    if (task['topic'] != null) task['topic'].toString(),
                    if (task['source_hint'] != null)
                      task['source_hint'].toString(),
                    if (autoResolved) 'auto-detected',
                  ].join(' \u00b7 '),
                ),
                trailing: Checkbox(
                  value: isComplete,
                  onChanged:
                      (checked) =>
                          checked == true
                              ? onCompleteTask(taskId)
                              : onReopenTask(taskId),
                ),
              );
            }).toList(),
      ),
    );
  }
}
