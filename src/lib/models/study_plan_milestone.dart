/// Not wired to any API yet. This is the shape StudyPlanProgressCard is
/// already built to accept, so adding the real endpoint later is a
/// data-fetch change, not a widget rewrite.
///
/// TODO(backend): needs a new endpoint -- something like
/// GET /study_plan/{plan_id}/progress -- returning, per milestone, a
/// state (done / active / upcoming) and a completed/total count. The
/// active milestone's `itemLabels` (sub-topics) are what the progress
/// card expands to show; every other milestone stays collapsed to name +
/// count. Until this exists, DLearningCenterPage passes `milestones: null`
/// and the card falls back to a "basic" view built from the plan summary
/// it already has (target role, status, draft count).
enum MilestoneState { done, active, upcoming }

class StudyPlanMilestone {
  final String name;
  final MilestoneState state;
  final int completedCount;
  final int totalCount;
  final List<String> itemLabels;

  const StudyPlanMilestone({
    required this.name,
    required this.state,
    required this.completedCount,
    required this.totalCount,
    this.itemLabels = const [],
  });

  factory StudyPlanMilestone.fromJson(Map<String, dynamic> json) {
    final stateStr = json['state'] as String? ?? 'upcoming';
    return StudyPlanMilestone(
      name: json['name'] as String? ?? 'Untitled milestone',
      state: MilestoneState.values.firstWhere(
        (s) => s.name == stateStr,
        orElse: () => MilestoneState.upcoming,
      ),
      completedCount: json['completed_count'] as int? ?? 0,
      totalCount: json['total_count'] as int? ?? 0,
      itemLabels:
          (json['item_labels'] as List? ?? []).map((e) => '$e').toList(),
    );
  }
}
