import 'package:cerebrum/ui/themes/theme_access.dart';
import 'package:flutter/material.dart';

import 'package:cerebrum/api/bubbles_api.dart';
import 'package:cerebrum/api/learning_center_api.dart';
import 'package:cerebrum/services/user_session.dart';
import '../../../models/gap_models.dart';
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
///   - open readings: suggested-reading items in the cached gap rollup
///     (GapRepository) — a real pending-reading count. The
///     opened_at/resolved lifecycle ([[unaddressed-notes-surface]]) is
///     daemon work; until it lands this counts all suggested readings.
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
  int? _openReadings;

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
      _loadOpenReadings(),
    ]);

    if (!mounted) return;

    setState(() {
      _gapsOpen = results[0] ?? (background ? _gapsOpen : null);
      _bubblesActive = results[1] ?? (background ? _bubblesActive : null);
      _dueToday = results[2] ?? (background ? _dueToday : null);
      _openReadings = results[3] ?? (background ? _openReadings : null);

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

  /// Open readings from the cached gap rollup: suggested-reading items. This
  /// is the real pending-reading count today; the opened_at/resolved lifecycle
  /// is daemon work ([[unaddressed-notes-surface]]). No rollup data yet →
  /// the tile shrinks away rather than pretending to be zero.
  Future<int?> _loadOpenReadings() async {
    try {
      final cached = await widget.gapRepository.cached();
      return cached.values.fold<int>(
        0,
        (sum, b) => sum + b.countOf(GapKind.suggestedReading),
      );
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
          accent: _gapsOpen! > 0 ? context.cerebrum.status.dangerDeep : null,
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
          label: 'due today',
          value: _dueToday!,
          accent: _dueToday! > 0 ? context.cerebrum.brand.primary : null,
        ),

      if (_openReadings != null)
        _PulseMetric(
          icon: Icons.book_outlined,
          label: 'open readings',
          value: _openReadings!,
          accent: _openReadings! > 0 ? context.cerebrum.brand.primary : null,
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
    final valueColor = metric.accent ?? context.cerebrum.brand.ink;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: context.cerebrum.surface.sunken,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(metric.icon, size: 14, color: context.cerebrum.text.muted),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  metric.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9,
                    color: context.cerebrum.text.muted,
                  ),
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
