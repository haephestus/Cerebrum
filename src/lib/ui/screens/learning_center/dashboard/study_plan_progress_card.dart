import 'package:flutter/material.dart';
import 'package:cerebrum/models/study_plan_milestone.dart';

/// Two modes, both showing only real data:
/// - "basic": all we have today is target role + status + draft count,
///   pulled from the same plan summaries the portfolio gantt already
///   fetches (PlannerApi.getPlans). Shown whenever `milestones` is null.
/// - "detailed": once a milestone/progress endpoint exists, pass
///   `milestones` (and `percentComplete`) and the richer view renders
///   instead. See study_plan_milestone.dart for what that endpoint needs
///   to return.
///
/// NOT CURRENTLY MOUNTED — the Learning Center deleted this card from its
/// dashboard row because the Plans section already owns this data (drafts
/// in the Timeline staging pane, current plan on the Timeline gantt and in
/// Focus). Kept because the "detailed"/milestone mode is the natural
/// inside-Focus content once a milestone endpoint exists; delete the file
/// if Focus never wants a milestone list.
class StudyPlanProgressCard extends StatefulWidget {
  final String? targetRole;
  final String? status;
  final int draftCount;
  final double? percentComplete;
  final List<StudyPlanMilestone>? milestones;
  final VoidCallback? onOpenPlan;
  final VoidCallback? onReviewDrafts;
  final bool loading;

  const StudyPlanProgressCard({
    super.key,
    required this.targetRole,
    required this.status,
    required this.draftCount,
    this.percentComplete,
    this.milestones,
    this.onOpenPlan,
    this.onReviewDrafts,
  }) : loading = false;

  const StudyPlanProgressCard.loading({super.key})
    : targetRole = null,
      status = null,
      draftCount = 0,
      percentComplete = null,
      milestones = null,
      onOpenPlan = null,
      onReviewDrafts = null,
      loading = true;

  @override
  State<StudyPlanProgressCard> createState() => _StudyPlanProgressCardState();
}

class _StudyPlanProgressCardState extends State<StudyPlanProgressCard> {
  String? _expandedMilestone;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: widget.loading ? _buildLoading(context) : _buildContent(context),
    );
  }

  Widget _buildLoading(BuildContext context) {
    return const SizedBox(
      height: 140,
      child: Center(child: CircularProgressIndicator()),
    );
  }

  Widget _buildContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.targetRole != null)
          _buildActivePlan(context)
        else
          _buildEmpty(context),
        if (widget.draftCount > 0) ...[
          if (widget.targetRole != null) const Divider(height: 24),
          _buildDraftRow(context),
        ],
      ],
    );
  }

  /// The approved/in-progress plan: title, status, progress (once real
  /// progress data exists), milestones (ditto).
  Widget _buildActivePlan(BuildContext context) {
    final milestones = widget.milestones;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                widget.targetRole!,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (widget.status != null)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  widget.status!,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (widget.percentComplete != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: widget.percentComplete!.clamp(0, 1),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${(widget.percentComplete! * 100).round()}% complete',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
        ],
        if (milestones != null && milestones.isNotEmpty)
          for (final m in milestones) _buildMilestoneRow(context, m)
        else if (widget.percentComplete == null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Detailed progress tracking is coming soon.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        if (widget.onOpenPlan != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: widget.onOpenPlan,
              child: const Text('Open plan'),
            ),
          ),
      ],
    );
  }

  /// Draft-plan callout. Shown whenever there are drafts, whether or not
  /// there's also an approved/in-progress plan above it -- previously
  /// this only appeared alongside an active plan, so a user with only
  /// drafts (no approved plan yet) saw a bare "no active plan" message
  /// and no sign their draft existed.
  Widget _buildDraftRow(BuildContext context) {
    return Row(
      children: [
        Icon(
          Icons.description_outlined,
          size: 16,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            widget.draftCount == 1
                ? '1 draft awaiting review'
                : '${widget.draftCount} drafts awaiting review',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        TextButton(
          onPressed: widget.onReviewDrafts,
          child: const Text('Review'),
        ),
      ],
    );
  }

  Widget _buildMilestoneRow(BuildContext context, StudyPlanMilestone m) {
    final expandable =
        m.state == MilestoneState.active && m.itemLabels.isNotEmpty;
    final expanded = _expandedMilestone == m.name;
    final icon = switch (m.state) {
      MilestoneState.done => Icons.check_circle,
      MilestoneState.active => Icons.play_circle_outline,
      MilestoneState.upcoming => Icons.circle_outlined,
    };
    final color = switch (m.state) {
      MilestoneState.done => Theme.of(context).colorScheme.primary,
      MilestoneState.active => Theme.of(context).colorScheme.primary,
      MilestoneState.upcoming => Theme.of(context).colorScheme.outline,
    };

    return InkWell(
      onTap:
          expandable
              ? () => setState(() {
                _expandedMilestone = expanded ? null : m.name;
              })
              : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    m.name,
                    style: TextStyle(
                      fontSize: 13,
                      color:
                          m.state == MilestoneState.upcoming
                              ? Theme.of(context).colorScheme.outline
                              : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
                Text(
                  '${m.completedCount}/${m.totalCount}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (expandable)
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                  ),
              ],
            ),
            if (expanded)
              Padding(
                padding: const EdgeInsets.only(left: 24, top: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final item in m.itemLabels)
                      Text(item, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final message =
        widget.draftCount > 0
            // There's a draft, it just hasn't been approved yet -- don't
            // say "no plan" when one exists and is sitting right below.
            ? 'Not started yet. Review the draft below to get going.'
            : 'No active plan yet. Generate one to see progress here.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Study plan',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(message, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
