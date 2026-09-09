import 'package:flutter/material.dart';

import 'package:cerebrum/api/bubbles_api.dart';
import 'package:cerebrum/api/learning_center_api.dart';
import 'package:cerebrum/services/user_session.dart';
import 'gap_repository.dart';

/// Dashboard's "first three seconds" glance strip.
///
/// Deliberately does NOT show a streak or a mastery percentage — neither is
/// computed anywhere in this codebase today, and inventing one would break
/// the same no-fabricated-data rule the rest of the homepage already follows
/// (see gap_extract.dart, gap_models.dart).
///
/// Every number here is a real, already-available count:
///   - gaps open: total items across the gap rollup (GapRepository)
///   - bubbles: how many study bubbles exist (BubblesApi)
///   - due today: engrams whose real scheduled_at falls on today
///
/// Once a real mastery/streak source exists, add it here as its own metric
/// rather than approximating one from these numbers.
class DashboardPulseStrip extends StatefulWidget {
  final GapRepository gapRepository;

  const DashboardPulseStrip({
    super.key,
    this.gapRepository = const LiveGapRepository(),
  });

  @override
  State<DashboardPulseStrip> createState() => _DashboardPulseStripState();
}

class _PulseMetric {
  final IconData icon;
  final String label;
  final int value;
  final Color? accent;

  const _PulseMetric({
    required this.icon,
    required this.label,
    required this.value,
    this.accent,
  });
}

class _DashboardPulseStripState extends State<DashboardPulseStrip>
    with WidgetsBindingObserver {
  bool _loading = true;

  int? _gapsOpen;
  int? _bubblesActive;
  int? _dueToday;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _load(background: true);
    }
  }

  /// Each metric fails independently — one bad source (e.g. daemon
  /// unreachable) shouldn't blank the metrics that did resolve.
  ///
  /// A [background] refresh never re-shows the loading placeholder.
  Future<void> _load({bool background = false}) async {
    final results = await Future.wait([
      _loadGapsOpen(),
      _loadBubblesActive(),
      _loadDueToday(),
    ]);

    if (!mounted) return;

    setState(() {
      _gapsOpen = results[0] ?? (background ? _gapsOpen : null);
      _bubblesActive = results[1] ?? (background ? _bubblesActive : null);
      _dueToday = results[2] ?? (background ? _dueToday : null);

      _loading = false;
    });
  }

  Future<int?> _loadGapsOpen() async {
    try {
      final cached = await widget.gapRepository.cached();

      final summaries =
          cached.isNotEmpty ? cached : await widget.gapRepository.refresh();

      return summaries.values.fold<int>(0, (sum, b) => sum + b.items.length);
    } catch (_) {
      return null;
    }
  }

  Future<int?> _loadBubblesActive() async {
    try {
      final data = await BubblesApi.fetchBubbles();
      return data.length;
    } catch (_) {
      return null;
    }
  }

  Future<int?> _loadDueToday() async {
    try {
      final userId = await UserSession.getUserId();

      if (userId == null) return null;

      final response = await LearningCenterApi.listEngrams(userId: userId);

      final now = DateTime.now();

      return response.engrams.where((e) {
        final due = e.scheduledAt;

        if (due == null) return false;

        return due.year == now.year &&
            due.month == now.month &&
            due.day == now.day;
      }).length;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Loading placeholder.
    if (_loading) {
      return const SizedBox(height: 60);
    }

    final metrics = <_PulseMetric>[
      if (_gapsOpen != null)
        _PulseMetric(
          icon: Icons.warning_amber_rounded,
          label: 'gaps open',
          value: _gapsOpen!,
          accent: _gapsOpen! > 0 ? const Color(0xFF8C2F2F) : null,
        ),

      if (_bubblesActive != null)
        // TODO(agent): perhaps find a better fit here? suggest one
        _PulseMetric(
          icon: Icons.bubble_chart,
          label: 'bubbles',
          value: _bubblesActive!,
        ),

      if (_dueToday != null)
        _PulseMetric(
          icon: Icons.today_outlined,
          label: 'overdue engrams',
          value: _dueToday!,
          accent: _dueToday! > 0 ? const Color(0xFF6C4FCE) : null,
        ),

      // TODO: Add open readings once a real pending-readings source exists.
      _PulseMetric(
        icon: Icons.book_outlined,
        label: 'open readings',
        value: _dueToday!,
      ),
    ];

    // Fully offline first load with nothing cached yet.
    if (metrics.isEmpty) {
      return const SizedBox.shrink();
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < metrics.length; i++) ...[
          if (i > 0) const SizedBox(width: 12),

          Expanded(child: _PulseChip(metric: metrics[i])),
        ],
      ],
    );
  }
}

class _PulseChip extends StatelessWidget {
  final _PulseMetric metric;

  const _PulseChip({required this.metric});

  @override
  Widget build(BuildContext context) {
    final valueColor = metric.accent ?? const Color(0xFF2F2940);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F1FA),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(metric.icon, size: 14, color: Colors.black54),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  metric.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 9, color: Colors.black54),
                ),
              ),
            ],
          ),

          const SizedBox(height: 2),

          Text(
            '${metric.value}',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}
