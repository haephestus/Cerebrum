import 'package:cerebrum/ui/themes/theme_access.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'study_plan_day_card.dart';

/// Month-scale phase timeline — one horizontally-scrolling view that is
/// the single source of truth for "where am I":
///
///   - Phase cards positioned/staggered along a month axis (as before).
///   - A row of week ticks under each phase card once its weeks are
///     loaded, giving week-level resolution synced to actual task
///     completion (pending / active / complete), not just the
///     phase-level status pill.
///   - Tapping a card opens a floating detail sheet with everything
///     that doesn't fit on the timeline itself: theme, milestone,
///     tracks, guiding principle, and the full week drill — each week
///     expands to its days with checkable tasks (the phase → week →
///     task zoom from [[features/study-plan-week-detail]]). The active
///     week lands expanded, so "this week" is still the default view.
///
/// Weeks are lazy-loaded per phase via [fetchWeeksForPhase] — called
/// once automatically for the active phase (so its ticks show up
/// without extra taps) and on-demand for any other phase the user taps.
/// Task checkbox flips round-trip through [onCompleteTask] /
/// [onReopenTask], then that phase's weeks are refetched so the sheet
/// never shows stale completion state.
class StudyPlanPhaseGantt extends StatefulWidget {
  final List<Map<String, dynamic>> phases;
  final Map<String, dynamic>? currentWeek;
  final List<Map<String, dynamic>> unachievedMetrics;
  final void Function(int phaseId) onDensify;
  final bool densifying;

  /// Task checkbox actions — the gantt owns no API calls; the parent page
  /// completes/reopens via PlannerApi and the gantt refetches that phase's
  /// weeks afterwards so the sheet never shows stale checkbox state.
  final Future<void> Function(int taskId) onCompleteTask;
  final Future<void> Function(int taskId) onReopenTask;

  /// Plan-level context shown in every phase's detail sheet.
  final String? targetRole;
  final String? guidingPrinciple;

  /// GET /study_plan/{plan_id}/weeks/phase/{phase_id} — all densified
  /// weeks for one phase, week shape pinned in
  /// [[features/study-plan-week-detail]] / cross-repo contracts:
  /// {week_id, week_number, status, focus_summary, topics[], days:
  /// [{day_of_week, tasks: [...]}]}. PlannerApi.getPhaseWeeks.
  final Future<List<Map<String, dynamic>>> Function(int phaseId)
  fetchWeeksForPhase;

  const StudyPlanPhaseGantt({
    super.key,
    required this.phases,
    required this.currentWeek,
    required this.unachievedMetrics,
    required this.onDensify,
    required this.densifying,
    required this.fetchWeeksForPhase,
    required this.onCompleteTask,
    required this.onReopenTask,
    this.targetRole,
    this.guidingPrinciple,
  });

  // Restored from the original detail-page gantt: indigo current, amber
  // next-up, grey upcoming. These read from the active theme rather than
  // being compile-time constants so a custom family can restyle the timeline.
  static Color currentColor(BuildContext context) =>
      context.cerebrum.gantt.current;
  static Color nextUpColor(BuildContext context) =>
      context.cerebrum.status.warning;
  static Color upcomingColor(BuildContext context) =>
      context.cerebrum.status.neutral;

  static Widget statusPill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  static Widget tag(
    BuildContext context,
    String label,
    Color color, {
    IconData? icon,
  }) {
    // Flexible + ellipsis: the Wrap that hosts tags constrains children to
    // its own width, but a raw Text in this min-size Row never shrinks —
    // long labels (topics, free-form month_marker checkpoints) overflowed
    // the Row by up to ~95px. Truncate in place; Tooltip keeps the full
    // text reachable.
    return Tooltip(
      message: label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: TextStyle(
                  color: color,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static List<Map<String, dynamic>> unplacedMetrics(
    List<Map<String, dynamic>> metrics,
    List<Map<String, dynamic>> phases,
  ) {
    return metrics.where((m) {
      final month = _parseMonthMarker(m['month_marker']?.toString());
      if (month == null) return true;
      return !phases.any((p) => _monthInPhase(month, p));
    }).toList();
  }

  static int? _parseMonthMarker(String? marker) {
    if (marker == null) return null;
    final match = RegExp(r'\d+').firstMatch(marker);
    return match == null ? null : int.tryParse(match.group(0)!);
  }

  static bool _monthInPhase(int month, Map<String, dynamic> phase) {
    final start = (phase['month_start'] as num?)?.toInt();
    final end = (phase['month_end'] as num?)?.toInt();
    if (start == null || end == null) return false;
    return month >= start && month <= end;
  }

  @override
  State<StudyPlanPhaseGantt> createState() => _StudyPlanPhaseGanttState();
}

class _StudyPlanPhaseGanttState extends State<StudyPlanPhaseGantt> {
  // Month column width restored to the original gantt's 96px.
  static const double monthWidth = 96;
  static const double cardStagger = 92;
  static const double rowHeight = 210;

  final Map<int, List<Map<String, dynamic>>> _weeksByPhase = {};
  final Set<int> _loadingPhaseIds = {};

  /// Phase whose detail sheet is currently floating over the gantt.
  ({
    int index,
    Map<String, dynamic> phase,
    List<Map<String, dynamic>> metrics,
    String statusLabel,
    Color statusColor,
  })?
  _selected;

  int? get _activePhaseId => (widget.currentWeek?['phase_id'] as num?)?.toInt();

  @override
  void initState() {
    super.initState();
    // Eagerly load the active phase's weeks so its ticks render without
    // requiring a tap — that's the phase the user cares about most.
    final activeId = _activePhaseId;
    if (activeId != null) _loadWeeks(activeId);
  }

  Future<void> _loadWeeks(int phaseId) async {
    if (_weeksByPhase.containsKey(phaseId) ||
        _loadingPhaseIds.contains(phaseId)) {
      return;
    }
    setState(() => _loadingPhaseIds.add(phaseId));
    try {
      final weeks = await widget.fetchWeeksForPhase(phaseId);
      if (mounted) setState(() => _weeksByPhase[phaseId] = weeks);
    } catch (_) {
      // Leave unloaded; the card falls back to its no-data affordance.
    } finally {
      if (mounted) setState(() => _loadingPhaseIds.remove(phaseId));
    }
  }

  /// Re-fetch a phase's weeks after a task checkbox flip, so the detail
  /// sheet shows the daemon-confirmed state instead of a stale cache.
  Future<void> _reloadWeeks(int phaseId) async {
    try {
      final weeks = await widget.fetchWeeksForPhase(phaseId);
      if (mounted) setState(() => _weeksByPhase[phaseId] = weeks);
    } catch (_) {
      // Keep whatever we had; a failed refresh shouldn't blank the sheet.
    } finally {
      if (mounted) setState(() => _loadingPhaseIds.remove(phaseId));
    }
  }

  /// Wraps the parent's task actions so the focused phase's weeks refresh
  /// after the API round-trip — checked tasks must not stay checked-stale.
  Future<void> _handleCompleteTask(int taskId) async {
    try {
      await widget.onCompleteTask(taskId);
    } finally {
      final sel = _selected;
      final phaseId =
          sel != null ? (sel.phase['phase_id'] as num?)?.toInt() : null;
      if (phaseId != null) await _reloadWeeks(phaseId);
    }
  }

  Future<void> _handleReopenTask(int taskId) async {
    try {
      await widget.onReopenTask(taskId);
    } finally {
      final sel = _selected;
      final phaseId =
          sel != null ? (sel.phase['phase_id'] as num?)?.toInt() : null;
      if (phaseId != null) await _reloadWeeks(phaseId);
    }
  }

  (String, Color) _statusFor(Map<String, dynamic> phase, int index) {
    final matchesActive =
        ((phase['phase_id'] as num?)?.toInt()) == _activePhaseId;
    if (widget.currentWeek != null && matchesActive)
      return ('In Progress', StudyPlanPhaseGantt.currentColor(context));
    if (widget.currentWeek == null && index == 0)
      return ('Next Up', StudyPlanPhaseGantt.nextUpColor(context));
    return ('Upcoming', StudyPlanPhaseGantt.upcomingColor(context));
  }

  void _selectPhase(
    int index,
    Map<String, dynamic> phase,
    String statusLabel,
    Color statusColor,
  ) {
    final phaseId = (phase['phase_id'] as num?)?.toInt();
    if (phaseId != null) _loadWeeks(phaseId);

    final metrics =
        widget.unachievedMetrics.where((m) {
          final month = StudyPlanPhaseGantt._parseMonthMarker(
            m['month_marker']?.toString(),
          );
          return month != null &&
              StudyPlanPhaseGantt._monthInPhase(month, phase);
        }).toList();

    setState(() {
      _selected = (
        index: index,
        phase: phase,
        metrics: metrics,
        statusLabel: statusLabel,
        statusColor: statusColor,
      );
    });
  }

  void _closeDetail() {
    if (_selected == null) return;
    setState(() => _selected = null);
  }

  /// Positions the floating detail sheet over the gantt, anchored to the
  /// tapped phase card's row/column and clamped inside the timeline so it
  /// never runs off the edge.
  Widget _buildDetailPanel(
    ({
      int index,
      Map<String, dynamic> phase,
      List<Map<String, dynamic>> metrics,
      String statusLabel,
      Color statusColor,
    })
    sel,
    double timelineWidth,
    double barsHeight,
  ) {
    final start = (sel.phase['month_start'] as num?)?.toInt() ?? 0;
    final cardLeft = start * monthWidth;
    final cardTop = sel.index * cardStagger;
    const panelWidth = 400.0;
    final panelMaxHeight = math.min(480.0, math.max(120.0, barsHeight - 16.0));
    // Prefer anchoring right of the tapped card; flip left when the
    // panel would run off the end of the timeline.
    final fitsRight = (cardLeft + 24.0 + panelWidth) <= timelineWidth - 8.0;
    final preferredLeft =
        fitsRight ? cardLeft + 24.0 : cardLeft - panelWidth - 24.0;
    final panelLeft =
        preferredLeft
            .clamp(8.0, math.max(8.0, timelineWidth - panelWidth - 8.0))
            .toDouble();
    final panelTop =
        cardTop
            .clamp(8.0, math.max(8.0, barsHeight - panelMaxHeight - 8.0))
            .toDouble();

    final phaseId = (sel.phase['phase_id'] as num?)?.toInt();
    final weeks = phaseId != null ? _weeksByPhase[phaseId] : null;
    final loading = phaseId != null && _loadingPhaseIds.contains(phaseId);

    return Positioned(
      left: panelLeft,
      top: panelTop,
      width: panelWidth,
      height: panelMaxHeight,
      child: _PhaseDetailSheet(
        phase: sel.phase,
        statusLabel: sel.statusLabel,
        statusColor: sel.statusColor,
        metrics: sel.metrics,
        targetRole: widget.targetRole,
        guidingPrinciple: widget.guidingPrinciple,
        weeks: weeks,
        loadingWeeks: loading,
        showDensify: sel.statusLabel == 'In Progress' && phaseId != null,
        densifying: widget.densifying,
        onDensify: phaseId == null ? null : () => widget.onDensify(phaseId),
        onCompleteTask: _handleCompleteTask,
        onReopenTask: _handleReopenTask,
        onClose: _closeDetail,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.phases.isEmpty) return const SizedBox.shrink();

    final maxMonth = widget.phases.fold<int>(0, (m, p) {
      final end = (p['month_end'] as num?)?.toInt() ?? 0;
      return end > m ? end : m;
    });
    final timelineWidth = (maxMonth + 2) * monthWidth;
    final timelineHeight =
        widget.phases.length * cardStagger + rowHeight - cardStagger;

    // "Today" is inferred: anchored to the start of the active phase (or the
    // first phase), plus how far into it the current week suggests we are.
    final activeIndex = widget.phases.indexWhere(
      (p) => (p['phase_id'] as num?)?.toInt() == _activePhaseId,
    );
    double? todayX;
    if (widget.phases.isNotEmpty) {
      final anchor = activeIndex >= 0 ? activeIndex : 0;
      final activeStart =
          (widget.phases[anchor]['month_start'] as num?)?.toInt() ?? 0;
      double fraction = 0;
      if (widget.currentWeek != null) {
        final week = (widget.currentWeek!['week_number'] as num?)?.toInt() ?? 1;
        fraction = ((week - 1) % 4) / 4.0;
      }
      todayX = (activeStart + fraction) * monthWidth;
    }

    final sel = _selected;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Plan timeline',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 8),
        // Takes whatever height the parent gives (the page's Expanded).
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              const rulerHeight = 32.0;
              const verticalPadding = 8.0; // 4 top + 4 bottom in padding below
              final available =
                  constraints.maxHeight.isFinite
                      ? constraints.maxHeight - rulerHeight - verticalPadding
                      : 0.0;
              // Fill the page when the plan is short; keep natural height
              // (and scroll vertically) when it's long. The 520 floor leaves
              // room for the floating detail sheet.
              final barsAreaHeight = math.max(
                math.max(timelineHeight, 520.0),
                available,
              );

              return SingleChildScrollView(
                // Vertical scroll for tall plans; also keeps pull-to-refresh
                // working when content is shorter than the viewport.
                physics: const AlwaysScrollableScrollPhysics(),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  // ONE shared horizontal scroll for ruler + bars.
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Month ruler
                      SizedBox(
                        width: timelineWidth,
                        height: rulerHeight,
                        child: Stack(
                          children: [
                            for (int m = 0; m <= maxMonth + 1; m++)
                              Positioned(
                                left: m * monthWidth,
                                width: monthWidth,
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
                          ],
                        ),
                      ),
                      // Bars area
                      SizedBox(
                        width: timelineWidth,
                        height: barsAreaHeight,
                        child: Stack(
                          children: [
                            // Alternating month shading
                            for (int m = 0; m <= maxMonth + 1; m++)
                              if (m.isEven)
                                Positioned(
                                  left: m * monthWidth,
                                  top: 0,
                                  bottom: 0,
                                  width: monthWidth,
                                  child: Container(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHighest
                                        .withValues(alpha: 0.4),
                                  ),
                                ),
                            // Today indicator (red line + circle)
                            if (todayX != null) ...[
                              Positioned(
                                left: todayX - 1,
                                top: 0,
                                bottom: 0,
                                child: Container(
                                  width: 2,
                                  color: context.cerebrum.status.dangerStrong,
                                ),
                              ),
                              Positioned(
                                left: todayX - 5,
                                top: 0,
                                child: Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: context.cerebrum.status.dangerStrong,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            ],
                            // Phase cards
                            for (int i = 0; i < widget.phases.length; i++)
                              Builder(
                                builder: (context) {
                                  final phase = widget.phases[i];
                                  final start =
                                      (phase['month_start'] as num?)?.toInt() ??
                                      0;
                                  final end =
                                      (phase['month_end'] as num?)?.toInt() ??
                                      start;
                                  final durationMonths = math.max(
                                    1,
                                    end - start + 1,
                                  );
                                  final barWidth = math.min(
                                    durationMonths * monthWidth,
                                    timelineWidth - start * monthWidth,
                                  );
                                  final (statusLabel, statusColor) = _statusFor(
                                    phase,
                                    i,
                                  );
                                  final phaseId =
                                      (phase['phase_id'] as num?)?.toInt();
                                  final weeks =
                                      phaseId != null
                                          ? _weeksByPhase[phaseId]
                                          : null;
                                  final loading =
                                      phaseId != null &&
                                      _loadingPhaseIds.contains(phaseId);

                                  return Positioned(
                                    left: start * monthWidth,
                                    top: i * cardStagger,
                                    width: barWidth,
                                    child: _PhaseCard(
                                      phase: phase,
                                      statusLabel: statusLabel,
                                      statusColor: statusColor,
                                      weeks: weeks,
                                      loadingWeeks: loading,
                                      onTap:
                                          () => _selectPhase(
                                            i,
                                            phase,
                                            statusLabel,
                                            statusColor,
                                          ),
                                    ),
                                  );
                                },
                              ),
                            // Floating detail popup, anchored to the tapped card
                            if (sel != null)
                              Positioned.fill(
                                child: LayoutBuilder(
                                  builder: (context, constraints) {
                                    final barsHeight = constraints.maxHeight;
                                    return Stack(
                                      children: [
                                        Positioned.fill(
                                          child: GestureDetector(
                                            onTap: _closeDetail,
                                            child: Container(
                                              color: context
                                                  .cerebrum
                                                  .text
                                                  .strong
                                                  .withValues(alpha: 0.25),
                                            ),
                                          ),
                                        ),
                                        _buildDetailPanel(
                                          sel,
                                          timelineWidth,
                                          barsHeight,
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

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

// ===========================================================================
// Floating detail sheet: everything that doesn't fit on the timeline.
// ===========================================================================

class _PhaseDetailSheet extends StatelessWidget {
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
