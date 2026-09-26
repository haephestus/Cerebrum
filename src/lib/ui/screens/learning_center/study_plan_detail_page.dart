import 'package:cerebrum/ui/themes/theme_access.dart';
import 'package:flutter/material.dart';
import 'package:cerebrum/api/planner_api.dart';
import 'package:cerebrum/api/study_plan_api.dart';
import 'package:cerebrum/ui/widgets/learning_center/gantt/study_plan_phase_gantt.dart';

/// Study Plan detail/progress view, opened from the Learning Center's
/// portfolio timeline or Focus pane (see d_learning_center_page.dart).
///
/// UI, top to bottom:
///   1. A slim header: target_role + guiding_principle, so the plan
///      timeline below isn't just month numbers with no "toward what."
///   2. [StudyPlanPhaseGantt] — the single source of truth for "where
///      am I": a horizontally-scrolling month-scale rail of phase
///      cards with week-level resolution ticks, and the full week
///      drill: tapping a phase opens a floating sheet whose weeks
///      expand to days with checkable tasks (phase → week → task).
///      The active week lands expanded, replacing the old
///      active-week-only checklist with the whole phase timeline.
///
/// Backed by GET /study_plan/{plan_id}/progress via PlannerApi
/// (planner_api.dart: getProgress/completeTask/reopenTask/densifyPhase),
/// GET /study_plan/{plan_id}/weeks/phase/{phase_id} via
/// PlannerApi.getPhaseWeeks (loaded per phase by the gantt), and
/// GET /study_plan/{plan_id} via StudyPlanApi.getPlan for the
/// plan-level overview (target_role/guiding_principle).
///
/// Payload shapes are pinned in .steward/cross-repo/contracts.md.
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
  late Future<Map<String, dynamic>?> _planFuture;
  bool _densifying = false;

  @override
  void initState() {
    super.initState();
    _loadProgress();
    _planFuture = StudyPlanApi.getPlan(widget.planId);
  }

  void _loadProgress() {
    _progressFuture = _fetchProgress();
  }

  void _refresh() => setState(_loadProgress);

  Future<Map<String, dynamic>> _fetchProgress() {
    return PlannerApi.getProgress(planId: widget.planId, userId: widget.userId);
  }

  Future<List<Map<String, dynamic>>> _fetchWeeksForPhase(int phaseId) async {
    final rawData = await PlannerApi.getPhaseWeeks(
      widget.planId,
      phaseId,
      widget.userId,
    );
    final List<dynamic>? weekList = rawData['weeks'] as List<dynamic>?;
    return List<Map<String, dynamic>>.from(weekList ?? []);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Plan Progress')),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: FutureBuilder<Map<String, dynamic>>(
          future: _progressFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
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
                          StudyPlanPhaseGantt.tag(
                            context,
                            '${m['month_marker']} ${m['checkpoint']}',
                            context.cerebrum.brand.primaryDeep,
                            icon: Icons.flag_outlined,
                          ),
                      ],
                    ),
                  ],
                ],
              );
            }

            return FutureBuilder<Map<String, dynamic>?>(
              future: _planFuture,
              builder: (context, planSnapshot) {
                final plan = planSnapshot.data;
                final overview =
                    plan?['plan_overview'] as Map<String, dynamic>?;
                final targetRole = overview?['target_role']?.toString();
                final guidingPrinciple =
                    overview?['guiding_principle']?.toString();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (targetRole != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              targetRole,
                              style: Theme.of(
                                context,
                              ).textTheme.titleSmall?.copyWith(
                                color:
                                    Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                                fontSize: 20,
                              ),
                            ),
                          ],
                          if (guidingPrinciple != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              guidingPrinciple,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(fontStyle: FontStyle.normal),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: StudyPlanPhaseGantt(
                        phases: incompletePhases,
                        currentWeek: currentWeek,
                        unachievedMetrics: unachievedMetrics,
                        onDensify: _densifyNextPhase,
                        densifying: _densifying,
                        fetchWeeksForPhase: _fetchWeeksForPhase,
                        onCompleteTask: _completeTask,
                        onReopenTask: _reopenTask,
                        targetRole: targetRole,
                        guidingPrinciple: guidingPrinciple,
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}
