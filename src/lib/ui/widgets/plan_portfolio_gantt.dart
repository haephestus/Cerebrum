import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:cerebrum/api/planner_api.dart';

/// Portfolio gantt for the Learning Center overview.
///
/// Renders APPROVED plans (status != 'draft') as calendar bars from their
/// predicted start (plan `created_at`) to `created_at + total_duration_months`
/// over a real calendar month ruler, with a today marker.
///
/// Per-plan KPI chips are derived client-side from
/// `GET /study_plan/{id}/progress` (v1: W-week · tasks, phases, checkpoints)
/// and degrade silently per-plan on failure — the bar still renders. The
/// daemon-aggregated `kpi` payload (v2) is pinned as a planned contract in
/// .steward/cross-repo/contracts.md "Plan KPI payload".
///
/// CROSS-REPO CONTRACT (load-bearing): bar anchors are `created_at`
/// (SQLite CURRENT_TIMESTAMP or ISO8601) and `total_duration_months` from
/// `GET /study_plan/user/all` (daemon fetch_all_plans_inator). Renaming or
/// dropping either drops the bar. See .steward/cross-repo/contracts.md
/// "Plans list payload".
class PlanPortfolioGantt extends StatefulWidget {
  final List<Map<String, dynamic>> plans;
  final String userId;
  final void Function(Map<String, dynamic> plan) onPlanTap;

  const PlanPortfolioGantt({
    super.key,
    required this.plans,
    required this.userId,
    required this.onPlanTap,
  });

  @override
  State<PlanPortfolioGantt> createState() => _PlanPortfolioGanttState();
}

class _PlanPortfolioGanttState extends State<PlanPortfolioGantt> {
  static const double _monthWidth = 96;
  static const double _headerHeight = 36;
  static const double _rowHeight = 58;

  static const _monthLabels = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  final ScrollController _scrollController = ScrollController();

  /// plan_id -> progress payload, or null when that plan's KPI fetch failed.
  final Map<String, Map<String, dynamic>?> _kpiByPlan = {};

  @override
  void initState() {
    super.initState();
    _loadKpis();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadKpis() async {
    final results = <String, Map<String, dynamic>?>{};
    await Future.wait(
      widget.plans.map((p) async {
        final id = p['plan_id'] as String?;
        if (id == null) return;
        try {
          final progress = await PlannerApi.getProgress(
            planId: id,
            userId: widget.userId,
          );
          results[id] = progress;
        } catch (_) {
          // Degrade silently: no KPI chips for this plan, bar still renders.
          results[id] = null;
        }
      }),
    );
    if (!mounted) return;
    setState(() => _kpiByPlan.addAll(results));
  }

  DateTime? _parseStart(Map<String, dynamic> plan) {
    final raw = plan['created_at'];
    if (raw == null) return null;
    final s = raw.toString().trim();
    if (s.isEmpty) return null;
    // SQLite CURRENT_TIMESTAMP has no 'T' separator; ISO8601 does.
    final normalized = s.contains('T') ? s : s.replaceFirst(' ', 'T');
    return DateTime.tryParse(normalized)?.toLocal();
  }

  DateTime _endOf(DateTime start, Map<String, dynamic> plan) {
    final months = (plan['total_duration_months'] as num?)?.toInt() ?? 1;
    return DateTime(start.year, start.month + months, start.day);
  }

  Widget _buildEmpty(BuildContext context) {
    return Center(
      child: Text(
        'No approved plans yet.\nDrafts wait in the upcoming pane.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final anchored =
        <
          ({
            String planId,
            Map<String, dynamic> plan,
            DateTime start,
            DateTime end,
          })
        >[];
    for (final p in widget.plans) {
      final start = _parseStart(p);
      if (start == null) continue;
      anchored.add((
        planId: (p['plan_id'] as String?) ?? '',
        plan: p,
        start: start,
        end: _endOf(start, p),
      ));
    }
    if (anchored.isEmpty) return _buildEmpty(context);

    DateTime rangeStart = anchored.first.start;
    DateTime rangeEnd = anchored.first.end;
    for (final a in anchored) {
      if (a.start.isBefore(rangeStart)) rangeStart = a.start;
      if (a.end.isAfter(rangeEnd)) rangeEnd = a.end;
    }
    rangeStart = DateTime(rangeStart.year, rangeStart.month, 1);
    // End-exclusive so the last bar's month gets a full column.
    rangeEnd = DateTime(rangeEnd.year, rangeEnd.month + 1, 1);

    final totalDays = rangeEnd.difference(rangeStart).inDays;
    final monthCount =
        (rangeEnd.year - rangeStart.year) * 12 +
        (rangeEnd.month - rangeStart.month);
    final totalWidth = monthCount * _monthWidth;
    final pxPerDay = totalWidth / totalDays;

    double xOf(DateTime d) => d.difference(rangeStart).inDays * pxPerDay;

    final today = DateTime.now();
    final showToday = !today.isBefore(rangeStart) && today.isBefore(rangeEnd);
    final todayX = xOf(today);

    final chartHeight = _headerHeight + anchored.length * _rowHeight + 16;

    return Listener(
      onPointerSignal: _onPointerSignal,
      child: Scrollbar(
        controller: _scrollController,
        child: SingleChildScrollView(
          controller: _scrollController,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(left: 16, right: 16, top: 0),
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SizedBox(
              width: totalWidth,
              height: chartHeight,
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
                  if (showToday) ...[
                    Positioned(
                      left: todayX - 1,
                      top: _headerHeight,
                      bottom: 0,
                      child: Container(width: 2, color: Colors.redAccent),
                    ),
                    Positioned(
                      left: todayX - 5,
                      top: _headerHeight - 12,
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
                      _buildRuler(context, rangeStart, monthCount),
                      for (var i = 0; i < anchored.length; i++)
                        _buildPlanRow(context, anchored[i], xOf, pxPerDay),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRuler(
    BuildContext context,
    DateTime rangeStart,
    int monthCount,
  ) {
    return SizedBox(
      height: _headerHeight,
      child: Row(
        children: [
          for (var m = 0; m < monthCount; m++)
            SizedBox(
              width: _monthWidth,
              child: Center(
                child: Text(
                  "${_monthLabels[(rangeStart.month - 1 + m) % 12]} '${(rangeStart.year + ((rangeStart.month - 1 + m) ~/ 12)) % 100}",
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPlanRow(
    BuildContext context,
    ({String planId, Map<String, dynamic> plan, DateTime start, DateTime end})
    a,
    double Function(DateTime) xOf,
    double pxPerDay,
  ) {
    final left = xOf(a.start);
    final width =
        (a.end.difference(a.start).inDays * pxPerDay)
            .clamp(24.0, double.infinity)
            .toDouble();
    final status = (a.plan['status'] as String?) ?? 'active';
    final color = _statusColor(status, context);

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(left: left),
            child: GestureDetector(
              onTap: () => widget.onPlanTap(a.plan),
              child: Container(
                height: 14,
                width: width,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      a.plan['target_role']?.toString() ?? 'Untitled plan',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (_kpiByPlan.containsKey(a.planId))
            Padding(
              padding: EdgeInsets.only(left: left),
              child: _buildKpiChips(context, a.planId),
            ),
        ],
      ),
    );
  }

  Widget _buildKpiChips(BuildContext context, String planId) {
    final progress = _kpiByPlan[planId];
    final chips = <String>[];
    if (progress != null) {
      final week = progress['current_week'] as Map<String, dynamic>?;
      if (week != null) {
        final weekNo = (week['week_number'] as num?)?.toInt();
        final taskProgress =
            progress['current_week_task_progress'] as Map<String, dynamic>?;
        final total = (taskProgress?['total'] as num?)?.toInt();
        final done = (taskProgress?['completed'] as num?)?.toInt();
        if (weekNo != null) {
          chips.add(
            total != null && done != null
                ? 'W$weekNo · $done/$total'
                : 'W$weekNo',
          );
        }
      }
      final phases = List<Map<String, dynamic>>.from(
        progress['incomplete_phases'] as List? ?? [],
      );
      if (phases.isNotEmpty) {
        chips.add('${phases.length} phases');
      }
      final metrics = List<Map<String, dynamic>>.from(
        progress['unachieved_metrics'] as List? ?? [],
      );
      if (metrics.isNotEmpty) {
        chips.add('${metrics.length} ckpts');
      }
    }
    if (chips.isEmpty) {
      return const SizedBox(height: 2);
    }
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Wrap(
        spacing: 4,
        runSpacing: 2,
        children: [
          for (final c in chips)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                c,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Color _statusColor(String status, BuildContext context) {
    switch (status) {
      case 'active':
        return Colors.green;
      case 'completed':
        return Colors.blue;
      case 'archived':
        return Colors.grey;
      default:
        return Theme.of(context).colorScheme.primary;
    }
  }

  /// Makes the mouse wheel pan the timeline when the pointer is over the
  /// gantt (same behavior as the detail page). Consumed only when the gantt
  /// can actually move — at the ends it stays unconsumed so the outer page
  /// list keeps scrolling (no dead zone, no trap).
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
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
}
