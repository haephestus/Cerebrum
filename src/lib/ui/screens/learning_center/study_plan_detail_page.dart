import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:cerebrum/api/planner_api.dart';

/// Study Plan detail/progress view, opened from the Learning Center's
/// Plans tab (see d_learning_center_page.dart.
///
/// UI: a month-scale gantt rail where each incomplete phase is a card
/// positioned by its start month; the active phase (matched by
/// `current_week.phase_id`, never by list index) carries a progress ring
/// and a below-the-chart week/day checklist; success metrics attach as
/// badges under the phase whose month range contains them (parsed from
/// `month_marker`, e.g. "M4").
///
/// Backed by GET /study_plan/{plan_id}/progress via PlannerApi
/// (planner_api.dart: getProgress/completeTask/reopenTask/densifyPhase).
/// Payload shape is pinned in .steward/cross-repo/contracts.md.
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
  final ScrollController _ganttScrollController = ScrollController();

  static const _currentColor = Color(0xFF3F51B5); // indigo
  static const _upcomingColor = Color(0xFF9E9E9E); // grey
  static const _nextUpColor = Color(0xFFE8A33D); // amber

  static const double _monthWidth = 96;
  static const double _headerHeight = 32;

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
    try {
      await PlannerApi.completeTask(taskId: taskId, userId: widget.userId);
      _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not mark task complete: $e')),
        );
      }
    }
  }

  Future<void> _reopenTask(int taskId) async {
    try {
      await PlannerApi.reopenTask(taskId: taskId, userId: widget.userId);
      _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not reopen task: $e')));
      }
    }
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

  /// Parses "M4" -> 4. Returns null if it doesn't match that shape.
  int? _parseMonthMarker(dynamic marker) {
    if (marker == null) return null;
    final match = RegExp(r'M(\d+)').firstMatch(marker.toString());
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  @override
  void dispose() {
    _ganttScrollController.dispose();
    super.dispose();
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
            final unplacedMetrics = _unplacedMetrics(
              unachievedMetrics,
              incompletePhases,
            );

            if (incompletePhases.isEmpty) {
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  Text(
                    'Your plan',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('All phases are complete. Nice work.'),
                  // Metrics are *unachieved* — that's why they're in the
                  // payload. A done plan can still have checkpoints left
                  // to hit, so never hide them behind the empty state.
                  if (unachievedMetrics.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text(
                      'Checkpoints still to hit',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final m in unachievedMetrics)
                          _tag(
                            context,
                            '${m['month_marker']} ${m['checkpoint']}',
                            Colors.deepPurple,
                            icon: Icons.flag_outlined,
                          ),
                      ],
                    ),
                  ],
                ],
              );
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(0, 16, 0, 32),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Your plan',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _buildGanttChart(
                  context,
                  currentWeek,
                  incompletePhases,
                  unachievedMetrics,
                ),
                const SizedBox(height: 28),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildStatusBoard(
                    context,
                    currentWeek,
                    incompletePhases,
                  ),
                ),
                if (unplacedMetrics.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _buildUnplacedMetrics(context, unplacedMetrics),
                  ),
                ],
                if (currentWeek != null) ...[
                  const SizedBox(height: 28),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _buildThisWeekChecklist(context, data, currentWeek),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Gantt / calendar-scale timeline
  // ---------------------------------------------------------------------

  Widget _buildGanttChart(
    BuildContext context,
    Map<String, dynamic>? currentWeek,
    List<Map<String, dynamic>> phases,
    List<Map<String, dynamic>> allMetrics,
  ) {
    final maxMonth = phases
        .map((p) => (p['month_end'] as num?)?.toInt() ?? 0)
        .fold<int>(0, (a, b) => a > b ? a : b);
    final monthCount = maxMonth + 1;
    final totalWidth = monthCount * _monthWidth;

    // Identify the active phase by the current week's phase_id, NOT by
    // list position — incomplete_phases is ordered by phase_id but an
    // earlier skipped/not_started phase would otherwise steal the
    // "In Progress" ring and label (see cross-repo/contracts.md).
    final activePhaseId = (currentWeek?['phase_id'] as num?)?.toInt();
    final activeIndex = phases.indexWhere(
      (p) => (p['phase_id'] as num?)?.toInt() == activePhaseId,
    );

    // "Today" is inferred, not given: we anchor it to the start of the
    // active phase (or the next one up), plus how far into it the
    // current week suggests we are. There's no real calendar date in
    // this payload, so treat this marker as approximate.
    double? todayX;
    if (phases.isNotEmpty) {
      final anchor = activeIndex >= 0 ? activeIndex : 0;
      final activeStart = (phases[anchor]['month_start'] as num?)?.toInt() ?? 0;
      double fraction = 0;
      if (currentWeek != null) {
        final week = (currentWeek['week_number'] as num?)?.toInt() ?? 1;
        fraction = ((week - 1) % 4) / 4.0;
      }
      todayX = (activeStart + fraction) * _monthWidth;
    }

    return Listener(
      onPointerSignal: _onGanttPointerSignal,
      child: Scrollbar(
        controller: _ganttScrollController,
        child: SingleChildScrollView(
          controller: _ganttScrollController,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(
            width: totalWidth,
            // Rows flow vertically at their natural height — a phase card
            // with many metric tags grows the chart instead of overlapping
            // the next row or being clipped by a fixed height.
            child: Stack(
              children: [
                // Alternating month shading, purely a reading aid.
                for (var m = 0; m < monthCount; m++)
                  if (m.isEven)
                    Positioned(
                      left: m * _monthWidth,
                      top: 0,
                      bottom: 0,
                      width: _monthWidth,
                      child: Container(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withValues(alpha: 0.4),
                      ),
                    ),
                // Today indicator.
                if (todayX != null) ...[
                  Positioned(
                    left: todayX - 1,
                    top: _headerHeight,
                    bottom: 0,
                    child: Container(width: 2, color: Colors.redAccent),
                  ),
                  Positioned(
                    left: todayX - 5,
                    top: _headerHeight - 10,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: Colors.redAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Month scale header.
                    SizedBox(
                      height: _headerHeight,
                      child: Row(
                        children: [
                          for (var m = 0; m < monthCount; m++)
                            SizedBox(
                              width: _monthWidth,
                              child: Center(
                                child: Text(
                                  'Month $m',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.labelSmall?.copyWith(
                                    color:
                                        Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    // One floating card per phase, offset by its start month.
                    for (var i = 0; i < phases.length; i++)
                      Padding(
                        padding: EdgeInsets.only(
                          left:
                              ((phases[i]['month_start'] as num?)?.toDouble() ??
                                  0) *
                              _monthWidth,
                          top: 8,
                        ),
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: _buildPhaseCard(
                            context,
                            phases[i],
                            isCurrent: i == activeIndex,
                            isNextActionable: i == 0 && currentWeek == null,
                            currentWeek: i == activeIndex ? currentWeek : null,
                            minBarWidth: _phaseBarWidth(phases[i], totalWidth),
                            totalWidth: totalWidth,
                            metrics: _metricsInRange(
                              allMetrics,
                              (phases[i]['month_start'] as num?)?.toInt(),
                              (phases[i]['month_end'] as num?)?.toInt(),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Makes the mouse wheel pan the timeline when the pointer is over the
  /// gantt, instead of only the page scrolling. Consumes the signal only
  /// when the gantt can actually move — at the ends it stays unconsumed so
  /// the outer page list keeps scrolling (no dead zone, no trap).
  ///
  /// Native horizontal input (trackpad two-finger, horizontal wheel) is
  /// left to the inner scrollable — its own handler registers and wins.
  void _onGanttPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (!_ganttScrollController.hasClients) return;
    final position = _ganttScrollController.position;
    final delta = event.scrollDelta.dx + event.scrollDelta.dy;
    if (delta == 0) return;
    final target = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (target == position.pixels) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (e) {
      position.pointerScroll(delta);
    });
  }

  Widget _buildPhaseCard(
    BuildContext context,
    Map<String, dynamic> phase, {
    required bool isCurrent,
    required bool isNextActionable,
    Map<String, dynamic>? currentWeek,
    required List<Map<String, dynamic>> metrics,
    required double minBarWidth,
    required double totalWidth,
  }) {
    final statusColor =
        isCurrent
            ? _currentColor
            : isNextActionable
            ? _nextUpColor
            : _upcomingColor;
    final statusLabel =
        isCurrent
            ? 'In Progress'
            : isNextActionable
            ? 'Next Up'
            : 'Upcoming';

    double? ratio;
    if (isCurrent && currentWeek != null) {
      // Caller only has current_week here, so we fall back to week-level
      // progress if task counts aren't threaded through; safe to omit ring
      // entirely when we don't have numbers.
      final tasks =
          List<Map<String, dynamic>>.from(currentWeek['days'] as List? ?? [])
              .expand(
                (d) =>
                    List<Map<String, dynamic>>.from(d['tasks'] as List? ?? []),
              )
              .toList();
      if (tasks.isNotEmpty) {
        final done = tasks.where((t) => t['status'] == 'complete').length;
        ratio = done / tasks.length;
      }
    }

    // The card is a gantt BAR: it must stretch across its month span
    // (minWidth = months * monthWidth), but never squeeze content below
    // 280px nor poke past the end of the ruler.
    final startPx =
        ((phase['month_start'] as num?)?.toInt() ?? 0) * _monthWidth;
    final maxWidth = math.max(
      minBarWidth,
      math.min(280.0, totalWidth - startPx),
    );

    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: minBarWidth, maxWidth: maxWidth),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
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
                  Icons.view_timeline_outlined,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    phase['phase_label']?.toString() ?? 'Phase',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (ratio != null) ...[
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      value: ratio,
                      strokeWidth: 2.5,
                      color: _currentColor,
                      backgroundColor:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                _tag(
                  context,
                  phase['theme']?.toString() ?? '',
                  Colors.blueGrey,
                ),
                _tag(
                  context,
                  'M${phase['month_start']}-${phase['month_end']}',
                  Colors.grey,
                ),
                _statusPillSmall(statusLabel, statusColor),
                for (final m in metrics)
                  _tag(
                    context,
                    '${m['month_marker']} ${m['checkpoint']}',
                    Colors.deepPurple,
                    icon: Icons.flag_outlined,
                  ),
              ],
            ),
            if (isNextActionable) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 30,
                child: FilledButton.icon(
                  onPressed:
                      _densifying
                          ? null
                          : () => _densifyNextPhase(phase['phase_id'] as int),
                  icon:
                      _densifying
                          ? const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : const Icon(Icons.auto_awesome, size: 14),
                  label: Text(
                    _densifying ? 'Generating…' : 'Generate this week',
                    style: const TextStyle(fontSize: 12),
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _tag(
    BuildContext context,
    String label,
    MaterialColor color, {
    IconData? icon,
  }) {
    if (label.trim().isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color.shade700),
            const SizedBox(width: 3),
          ],
          // Flexible is required: in a min-size Row the Text would
          // otherwise get unbounded width and paint past the card,
          // overflowing the 280px ConstrainedBox (ellipsis alone can't
          // save it). Tooltip keeps the full label reachable on hover.
          Flexible(
            child: Tooltip(
              message: label,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: color.shade700,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusPillSmall(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // "Projects Status" board (kanban strip)
  // ---------------------------------------------------------------------

  Widget _buildStatusBoard(
    BuildContext context,
    Map<String, dynamic>? currentWeek,
    List<Map<String, dynamic>> phases,
  ) {
    final activePhaseId = (currentWeek?['phase_id'] as num?)?.toInt();
    final inProgress = <Map<String, dynamic>>[];
    final nextUp = <Map<String, dynamic>>[];
    final upcoming = <Map<String, dynamic>>[];

    for (var i = 0; i < phases.length; i++) {
      final matchesActive =
          ((phases[i]['phase_id'] as num?)?.toInt()) == activePhaseId;
      if (currentWeek != null && matchesActive) {
        inProgress.add(phases[i]);
      } else if (currentWeek == null && i == 0) {
        nextUp.add(phases[i]);
      } else {
        upcoming.add(phases[i]);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Plan status',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          // Completed/archived phases aren't in this payload yet — the
          // backend only exposes incomplete phases here (see StudyPlanApi
          // notes on the missing full-history route).
          'Completed phases will show here once a plan-history endpoint exists.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _statusColumn(context, 'In Progress', _currentColor, inProgress),
              const SizedBox(width: 12),
              _statusColumn(context, 'Next Up', _nextUpColor, nextUp),
              const SizedBox(width: 12),
              _statusColumn(context, 'Upcoming', _upcomingColor, upcoming),
            ],
          ),
        ),
      ],
    );
  }

  Widget _statusColumn(
    BuildContext context,
    String title,
    Color color,
    List<Map<String, dynamic>> items,
  ) {
    return SizedBox(
      width: 190,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _statusPillSmall(title, color),
          const SizedBox(height: 8),
          if (items.isEmpty)
            Text('—', style: Theme.of(context).textTheme.bodySmall)
          else
            ...items.map(
              (p) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p['phase_label']?.toString() ?? 'Phase',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Months ${p['month_start']}-${p['month_end']}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // This week's checklist (below the chart, since day-level detail doesn't
  // fit the month-scale gantt above)
  // ---------------------------------------------------------------------

  Widget _buildThisWeekChecklist(
    BuildContext context,
    Map<String, dynamic> data,
    Map<String, dynamic> currentWeek,
  ) {
    final days = List<Map<String, dynamic>>.from(
      currentWeek['days'] as List? ?? [],
    );
    final taskProgress =
        data['current_week_task_progress'] as Map<String, dynamic>? ?? {};
    final total = (taskProgress['total'] as num?)?.toInt() ?? 0;
    final completed = (taskProgress['completed'] as num?)?.toInt() ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Week ${currentWeek['week_number']}',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            Text(
              '$completed/$total tasks',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...days.map((day) => _buildDayCard(day)),
      ],
    );
  }

  Widget _buildDayCard(Map<String, dynamic> day) {
    final tasks = List<Map<String, dynamic>>.from(day['tasks'] as List? ?? []);
    final dayOfWeek = (day['day_of_week'] as num).toInt();

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
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

  /// Gantt bar width: the phase card stretches across its month span
  /// (min 1 month), clamped to the room remaining on the ruler so it
  /// never pokes past the grid end.
  double _phaseBarWidth(Map<String, dynamic> phase, double totalWidth) {
    final start = (phase['month_start'] as num?)?.toInt() ?? 0;
    final end = (phase['month_end'] as num?)?.toInt() ?? start;
    final months = math.max(1, end - start + 1);
    return math.min(months * _monthWidth, totalWidth - start * _monthWidth);
  }

  List<Map<String, dynamic>> _metricsInRange(
    List<Map<String, dynamic>> metrics,
    int? start,
    int? end,
  ) {
    if (start == null || end == null) return const [];
    return metrics.where((m) {
      final month = _parseMonthMarker(m['month_marker']);
      return month != null && month >= start && month <= end;
    }).toList();
  }

  /// Metrics that didn't attach to any phase badge — either their
  /// month_marker isn't `M<n>` shape at all, or it falls outside every
  /// phase's month range. `month_marker` is free-form LLM text, so this
  /// WILL happen. Never drop these from the screen (contract rule).
  List<Map<String, dynamic>> _unplacedMetrics(
    List<Map<String, dynamic>> metrics,
    List<Map<String, dynamic>> phases,
  ) {
    return metrics.where((m) {
      final month = _parseMonthMarker(m['month_marker']);
      if (month == null) return true;
      return !phases.any(
        (p) =>
            month >= ((p['month_start'] as num?)?.toInt() ?? -1) &&
            month <= ((p['month_end'] as num?)?.toInt() ?? -1),
      );
    }).toList();
  }

  Widget _buildUnplacedMetrics(
    BuildContext context,
    List<Map<String, dynamic>> metrics,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Other checkpoints',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          "These success metrics don't map to a phase month — still worth tracking.",
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final m in metrics)
              _tag(
                context,
                '${m['month_marker']} ${m['checkpoint']}',
                Colors.deepPurple,
                icon: Icons.flag_outlined,
              ),
          ],
        ),
      ],
    );
  }
}
