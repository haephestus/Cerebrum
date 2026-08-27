import 'package:flutter/material.dart';
import 'package:cerebrum/api/planner_api.dart';

/// Rewrite of StudyPlanDetailPage from learning_center_page.dart.
/// Replaces the old flat "phases + metrics" list with the week/day/task
/// view backed by GET /study_plan/{plan_id}/progress, via PlannerApi
/// (see planner_api_additions.dart for the getProgress/completeTask/
/// reopenTask/densifyPhase methods this calls).
class StudyPlanDetailPage extends StatefulWidget {
  final String planId;
  final String userId;
  const StudyPlanDetailPage({
    super.key,
    required this.planId,
    required this.userId,
  });

  @override
  State<StudyPlanDetailPage> createState() => _StudyPlanDetailPageState();
}

class _StudyPlanDetailPageState extends State<StudyPlanDetailPage> {
  late Future<Map<String, dynamic>> _progressFuture;
  bool _densifying = false;

  @override
  void initState() {
    super.initState();
    _loadProgress();
  }

  void _loadProgress() {
    _progressFuture = _fetchProgress();
  }

  void _refresh() => setState(_loadProgress);

  Future<Map<String, dynamic>> _fetchProgress() {
    return PlannerApi.getProgress(planId: widget.planId, userId: widget.userId);
  }

  Future<void> _completeTask(int taskId) async {
    await PlannerApi.completeTask(taskId: taskId, userId: widget.userId);
    _refresh();
  }

  Future<void> _reopenTask(int taskId) async {
    await PlannerApi.reopenTask(taskId: taskId, userId: widget.userId);
    _refresh();
  }

  Future<void> _densifyNextPhase(int phaseId) async {
    setState(() => _densifying = true);
    try {
      await PlannerApi.densifyPhase(
        planId: widget.planId,
        phaseId: phaseId,
        userId: widget.userId,
      );
      _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not generate week detail: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _densifying = false);
    }
  }

  String _dayName(int dayOfWeek) =>
      const [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday',
      ][dayOfWeek.clamp(0, 6)];

  Color _taskTypeColor(String type, BuildContext context) {
    switch (type) {
      case 'study':
        return Colors.indigo;
      case 'practice':
        return Colors.teal;
      case 'build':
        return Colors.orange;
      case 'review':
        return Colors.purple;
      case 'milestone_check':
        return Colors.red;
      default:
        return Theme.of(context).colorScheme.primary;
    }
  }

  IconData _taskTypeIcon(String type) {
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
    return Scaffold(
      appBar: AppBar(title: const Text('Plan Progress')),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: FutureBuilder<Map<String, dynamic>>(
          future: _progressFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(
                padding: const EdgeInsets.all(24),
                children: [Center(child: Text('Error: ${snapshot.error}'))],
              );
            }

            final data = snapshot.data!;
            final currentWeek = data['current_week'] as Map<String, dynamic>?;
            final incompletePhases = List<Map<String, dynamic>>.from(
              data['incomplete_phases'] as List? ?? [],
            );
            final unachievedMetrics = List<Map<String, dynamic>>.from(
              data['unachieved_metrics'] as List? ?? [],
            );

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (currentWeek == null)
                  _buildNoCurrentWeekCard(incompletePhases)
                else
                  ..._buildCurrentWeekSections(context, data, currentWeek),
                const SizedBox(height: 28),
                _buildSectionHeader('Phases'),
                const SizedBox(height: 8),
                ...incompletePhases.map(_buildPhaseCard),
                const SizedBox(height: 28),
                _buildSectionHeader('Success Metrics'),
                const SizedBox(height: 8),
                ...unachievedMetrics.map(_buildMetricTile),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildNoCurrentWeekCard(List<Map<String, dynamic>> incompletePhases) {
    // No active week generated yet — offer to densify the earliest
    // incomplete phase so there's always a clear next action rather
    // than a blank screen.
    final nextPhase =
        incompletePhases.isNotEmpty ? incompletePhases.first : null;
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'No week-by-week detail generated yet',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              nextPhase != null
                  ? 'Generate day-by-day tasks for "${nextPhase['phase_label']}" to get started.'
                  : 'All phases are complete or this plan has no phases yet.',
            ),
            if (nextPhase != null) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed:
                    _densifying
                        ? null
                        : () => _densifyNextPhase(nextPhase['phase_id'] as int),
                icon:
                    _densifying
                        ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : const Icon(Icons.auto_awesome),
                label: Text(_densifying ? 'Generating…' : 'Generate this week'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _buildCurrentWeekSections(
    BuildContext context,
    Map<String, dynamic> data,
    Map<String, dynamic> currentWeek,
  ) {
    final taskProgress =
        data['current_week_task_progress'] as Map<String, dynamic>? ?? {};
    final avgMastery = data['current_week_avg_mastery'];
    final topics = List<String>.from(currentWeek['topics'] as List? ?? []);
    final days = List<Map<String, dynamic>>.from(
      currentWeek['days'] as List? ?? [],
    );

    final total = (taskProgress['total'] as num?)?.toInt() ?? 0;
    final completed = (taskProgress['completed'] as num?)?.toInt() ?? 0;
    final ratio = total > 0 ? completed / total : 0.0;

    return [
      Text(
        'Week ${currentWeek['week_number']}',
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 4),
      if (currentWeek['focus_summary'] != null)
        Text(
          currentWeek['focus_summary'].toString(),
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      const SizedBox(height: 12),
      if (topics.isNotEmpty)
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children:
              topics
                  .map(
                    (t) => Chip(
                      label: Text(t),
                      visualDensity: VisualDensity.compact,
                    ),
                  )
                  .toList(),
        ),
      const SizedBox(height: 16),
      Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 8,
                backgroundColor:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text('$completed/$total tasks'),
        ],
      ),
      if (avgMastery != null) ...[
        const SizedBox(height: 4),
        Text(
          'Avg. topic mastery: ${((avgMastery as num) * 100).toStringAsFixed(0)}%',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
      const SizedBox(height: 20),
      ...days.map((day) => _buildDayCard(day)),
    ];
  }

  Widget _buildDayCard(Map<String, dynamic> day) {
    final tasks = List<Map<String, dynamic>>.from(day['tasks'] as List? ?? []);
    final dayOfWeek = (day['day_of_week'] as num).toInt();

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        initiallyExpanded: true,
        title: Text(_dayName(dayOfWeek)),
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
                  _taskTypeIcon(taskType),
                  color: _taskTypeColor(taskType, context),
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
                    if (autoResolved) 'auto-detected',
                  ].join(' · '),
                ),
                trailing: Checkbox(
                  value: isComplete,
                  onChanged:
                      (checked) =>
                          checked == true
                              ? _completeTask(taskId)
                              : _reopenTask(taskId),
                ),
              );
            }).toList(),
      ),
    );
  }

  Widget _buildSectionHeader(String title) => Text(
    title,
    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
  );

  Widget _buildPhaseCard(Map<String, dynamic> phase) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(phase['phase_label']?.toString() ?? 'Phase'),
        subtitle: Text(
          '${phase['theme'] ?? ''}\nMonths ${phase['month_start']}-${phase['month_end']}',
        ),
        isThreeLine: true,
      ),
    );
  }

  Widget _buildMetricTile(Map<String, dynamic> metric) {
    return CheckboxListTile(
      value: false,
      title: Text(metric['checkpoint']?.toString() ?? ''),
      subtitle: Text(metric['month_marker']?.toString() ?? ''),
      onChanged: (_) {}, // wire to existing mark_metric_achieved endpoint
    );
  }
}
