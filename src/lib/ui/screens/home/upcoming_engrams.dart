import 'package:cerebrum/ui/themes/theme_access.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:cerebrum/api/learning_center_api.dart';
import 'package:cerebrum/models/engram_models.dart';
import 'package:cerebrum/services/user_session.dart';
import 'package:cerebrum/ui/screens/learning_center/d_learning_center_page.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// One schedule entry on the dashboard time rail. Generic on purpose: today
/// only engrams feed it, but analysis reviews / plan tasks plug in later
/// without restructuring the rail (same [due] + [title] contract).
class ScheduleItem {
  final String id;
  final String title;
  final DateTime due;
  final EngramType? type;

  /// Bar length on the gantt rail. The ANCHOR is [due] (real data); the tail
  /// is a nominal review span so same-hour starts visibly stack. A real
  /// daemon-side duration replaces the default when it exists.
  final Duration duration;

  const ScheduleItem({
    required this.id,
    required this.title,
    required this.due,
    this.type,
    this.duration = const Duration(minutes: 30),
  });

  DateTime get end => due.add(duration);
}

/// Items due on [day] (local midnight bounds), sorted by real due time.
/// Unscheduled engrams are excluded here — they have no position on the rail.
/// Pure + unit-tested.
List<ScheduleItem> buildDayItems(List<Engram> engrams, DateTime day) {
  final dayStart = DateTime(day.year, day.month, day.day);
  final dayEnd = dayStart.add(const Duration(days: 1));

  final items = <ScheduleItem>[
    for (final e in engrams)
      if (e.scheduledAt != null &&
          !e.scheduledAt!.isBefore(dayStart) &&
          e.scheduledAt!.isBefore(dayEnd))
        ScheduleItem(
          id: e.id,
          title: _engramTitle(e.type),
          due: e.scheduledAt!,
          type: e.type,
        ),
  ]..sort((a, b) => a.due.compareTo(b.due));
  return items;
}

/// Gantt row assignment: items become horizontal bars from [ScheduleItem.due]
/// to [ScheduleItem.end]; bars that overlap get different rows, touching bars
/// (one ends exactly when another starts) share a row.
///
/// Greedy interval partitioning — for each item in start order, place it in
/// the first row whose last bar already ended; open a new row when none fits.
/// Row count equals the maximum simultaneous overlap, which is also the
/// minimum possible. Pure + unit-tested.
List<({ScheduleItem item, int row})> layoutGantt(List<ScheduleItem> items) {
  final sorted = [...items]..sort((a, b) => a.due.compareTo(b.due));

  final rowEnds = <DateTime>[];
  final out = <({ScheduleItem item, int row})>[];

  for (final item in sorted) {
    var row = 0;
    while (row < rowEnds.length && rowEnds[row].isAfter(item.due)) {
      row++;
    }
    if (row >= rowEnds.length) {
      rowEnds.add(item.end);
    } else {
      rowEnds[row] = item.end;
    }
    out.add((item: item, row: row));
  }
  return out;
}

/// Number of scheduled items per local day — feeds the mini-calendar badges.
/// Pure + unit-tested.
Map<DateTime, int> buildDayCounts(List<Engram> engrams) {
  final counts = <DateTime, int>{};
  for (final e in engrams) {
    final due = e.scheduledAt;
    if (due == null) continue;
    final day = DateTime(due.year, due.month, due.day);
    counts[day] = (counts[day] ?? 0) + 1;
  }
  return counts;
}

/// Number of OVERDUE items per local day (due < now) — the mini calendar's
/// red badge data. Pure + unit-tested.
Map<DateTime, int> buildOverdueDayCounts(
  List<Engram> engrams, {
  DateTime? now,
}) {
  final reference = now ?? DateTime.now();
  final counts = <DateTime, int>{};
  for (final e in engrams) {
    final due = e.scheduledAt;
    if (due == null || !due.isBefore(reference)) continue;
    final day = DateTime(due.year, due.month, due.day);
    counts[day] = (counts[day] ?? 0) + 1;
  }
  return counts;
}

/// User-global overdue count (any scheduled engram with a real due time in the
/// past) — the header's "N overdue → Learning Center" banner. Pure + tested.
int countOverdue(List<Engram> engrams, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  var count = 0;
  for (final e in engrams) {
    final due = e.scheduledAt;
    if (due == null) continue;
    if (due.isBefore(reference)) count++;
  }
  return count;
}

/// User-global unscheduled count (engrams the daemon has not given a due time
/// yet) — the rail's right-side "unscheduled" counter. Pure + unit-tested.
int countUnscheduled(List<Engram> engrams) =>
    engrams.where((e) => e.scheduledAt == null).length;

/// 24h hour → compact rail label: 0→"12am", 12→"12pm", 13→"1pm", 23→"11pm".
String formatRailHour(int hour24) {
  final h = hour24 % 24;
  final period = h < 12 ? 'am' : 'pm';
  final display = h % 12 == 0 ? 12 : h % 12;
  return '$display$period';
}

String _engramTitle(EngramType type) => switch (type) {
  EngramType.mcq => "MCQ",
  EngramType.flashcard => "Flashcard",
  EngramType.shortQuestion => "Short Q",
  EngramType.longQuestion => "Long Q",
  EngramType.unknown => "Engram",
};

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Dashboard "what's due, one day at a time" section.
///
/// A single horizontal time rail (12am → 11:59pm) for the selected day:
///   - real engram due times positioned on the rail; nothing fabricated
///   - panned horizontally; 23:59 → next day, 00:00 → previous day
///   - a now-cursor (current system time) at the focus, only on today
///   - tapping the date opens the mini calendar (overdue badges per day)
///   - an overdue banner jumps to the Learning Center
///
/// Self-loads the user's engrams (user-level scope) and self-hides when the
/// user has none.
class UpcomingEngramsSection extends StatefulWidget {
  const UpcomingEngramsSection({super.key});

  @override
  State<UpcomingEngramsSection> createState() => _UpcomingEngramsSectionState();
}

class _UpcomingEngramsSectionState extends State<UpcomingEngramsSection>
    with WidgetsBindingObserver {
  bool _loading = true; // only true until the FIRST fetch resolves
  bool _fetching = false; // guards against overlapping fetches
  List<Engram> _engrams = const [];
  DateTime _selectedDay = DateTime.now();
  String? _userId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadEngrams();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadEngrams(background: true);
  }

  /// Fetches the user's engrams. Scope is USER-LEVEL (no bubble/note) — the
  /// dashboard is the global view. A [background] refresh keeps the current
  /// rail visible and, on failure, leaves whatever was already shown.
  Future<void> _loadEngrams({bool background = false}) async {
    if (_fetching) return;
    _fetching = true;
    try {
      final userId = await UserSession.getUserId();
      if (userId == null) {
        if (!background) setState(() => _loading = false);
        return;
      }

      final response = await LearningCenterApi.listEngrams(userId: userId);

      if (!mounted) return;

      // The selected day survives refreshes: the user's pan/calendar choice is
      // deliberate and should not reset on a foreground refetch.
      setState(() {
        _engrams = response.engrams;
        _userId = userId;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      if (!background) setState(() => _loading = false);
    } finally {
      _fetching = false;
    }
  }

  Future<void> _openCalendar() async {
    final picked = await showDialog<DateTime>(
      context: context,
      builder:
          (_) => _MiniCalendarDialog(
            initialDay: _selectedDay,
            today: DateTime.now(),
            countsByDay: buildDayCounts(_engrams),
            overdueByDay: buildOverdueDayCounts(_engrams),
          ),
    );
    if (picked != null && mounted) {
      setState(() => _selectedDay = picked);
    }
  }

  void _openLearningCenter() {
    final userId = _userId;
    if (userId == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DLearningCenterPage(userId: userId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 150,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    // No engrams at all → the section shrinks away (the dashboard hides it),
    // same as before. Days WITH no items still show the rail: the full-day
    // timeline is the point.
    if (_engrams.isEmpty) {
      return const SizedBox.shrink();
    }

    return ScheduleRail(
      selectedDay: _selectedDay,
      items: buildDayItems(_engrams, _selectedDay),
      overdueCount: countOverdue(_engrams),
      unscheduledCount: countUnscheduled(_engrams),
      onPrevDay:
          () => setState(
            () => _selectedDay = _selectedDay.subtract(const Duration(days: 1)),
          ),
      onNextDay:
          () => setState(
            () => _selectedDay = _selectedDay.add(const Duration(days: 1)),
          ),
      onOpenCalendar: _openCalendar,
      onOpenLearningCenter: _openLearningCenter,
    );
  }
}

/// Compact day schedule card.
///
/// Layout:
///
/// ┌──────────┬──────────────────────────────┬──────────┐
/// │ Tuesday  │  3 pm       4 pm       5 pm  │ 2        │
/// │ 13       │  │          │          │     │ overdue  │
/// │ DEC      │  Meeting    │     +    │     │ 5        │
/// │          │      +      │           │     │ unsched. │
/// └──────────┴──────────────────────────────┴──────────┘
///
/// The date column and the counters column stay fixed while the timeline can
/// pan horizontally; the viewport shows a fixed 6-hour window (the rest of
/// the day is reached by drag or wheel). Real event times are positioned
/// against the 24-hour timeline.
class ScheduleRail extends StatefulWidget {
  final DateTime selectedDay;
  final List<ScheduleItem> items;
  final int overdueCount;
  final int unscheduledCount;
  final VoidCallback onPrevDay;
  final VoidCallback onNextDay;
  final VoidCallback onOpenCalendar;
  final VoidCallback onOpenLearningCenter;

  const ScheduleRail({
    super.key,
    required this.selectedDay,
    required this.items,
    required this.overdueCount,
    required this.unscheduledCount,
    required this.onPrevDay,
    required this.onNextDay,
    required this.onOpenCalendar,
    required this.onOpenLearningCenter,
  });

  @override
  State<ScheduleRail> createState() => _ScheduleRailState();
}

class _ScheduleRailState extends State<ScheduleRail> {
  static const double _dateWidth = 128;
  static const double _countersWidth = 128;
  static const double _axisHeight = 22;
  static const double _rowHeight = 24;
  static const double _rowGap = 4;
  static const double _edgePad = 12;
  static const double _bottomPad = 28;
  static const double _minBodyHeight = 128;

  /// Stack depth cap: overlap chains beyond this stop growing the rail
  /// vertically; the surplus items collapse into a "+N more" hint.
  static const int _maxVisibleRows = 3;

  final ScrollController _scroll = ScrollController();

  Timer? _nowTimer;
  DateTime _lastNavAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Hour width in px. Set per layout from the viewport: the rail always
  /// shows a fixed 6-hour window (hourWidth = viewport / 6), so the 24h day
  /// is exactly 4 viewports wide and the missing 18h is reached by panning.
  double _hourWidth = 96;

  /// Whether the pointer currently hovers the timeline. The wheel is captured
  /// while hovering (even at the min/max ends); only a physical exit hands
  /// the wheel back to the page's own scrolling.
  bool _hovering = false;

  double get _timelineWidth => _edgePad * 2 + (24 * _hourWidth);

  /// Gantt layout for the current items — single source of truth for both the
  /// bar positions and the rail's total height.
  List<({ScheduleItem item, int row})> get _layout => layoutGantt(widget.items);

  /// Items in rows the rail actually renders (rows 0.._maxVisibleRows-1).
  List<({ScheduleItem item, int row})> get _visibleLayout => [
    for (final placed in _layout)
      if (placed.row < _maxVisibleRows) placed,
  ];

  /// Items hidden by the row cap — they feed the "+N more" hint.
  int get _hiddenCount => _layout.length - _visibleLayout.length;

  int get _rowCount =>
      _layout.isEmpty ? 0 : _layout.map((e) => e.row).reduce(math.max) + 1;

  int get _visibleRowCount => math.min(_rowCount, _maxVisibleRows);

  /// Strip reserved under the last visible row for the "+N more" hint when
  /// the cap hides anything. It pushes the hint off the bars but stays tiny —
  /// the rail does NOT grow another row per hidden item.
  double get _hintStripHeight => _hiddenCount > 0 ? 20 : 0;

  /// Rail body height grows with the stack depth up to the cap: axis + one
  /// 24px bar per visible row + (optionally) the hint strip + room for the
  /// "+" affordance row at the bottom.
  double get _bodyHeight => math.max(
    _minBodyHeight,
    _axisHeight +
        _visibleRowCount * (_rowHeight + _rowGap) +
        _hintStripHeight +
        _bottomPad,
  );

  @override
  void initState() {
    super.initState();

    _nowTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted && _isSameDay(widget.selectedDay, DateTime.now())) {
        setState(() {});
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _anchorInitial();
    });
  }

  @override
  void dispose() {
    _nowTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(ScheduleRail oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (_isSameDay(oldWidget.selectedDay, widget.selectedDay)) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _anchorAfterDayChange(oldWidget.selectedDay);
    });
  }

  // ---------------------------------------------------------------------------
  // Scrolling
  // ---------------------------------------------------------------------------

  double _timeToPx(DateTime time) {
    final minutes = time.hour * 60 + time.minute;
    return minutes * _hourWidth / 60;
  }

  void _anchorInitial() {
    if (!_scroll.hasClients) return;

    final position = _scroll.position;

    if (position.viewportDimension <= 0) return;

    final now = DateTime.now();

    if (_isSameDay(widget.selectedDay, now)) {
      final target = (_edgePad +
              _timeToPx(now) -
              position.viewportDimension * 0.42)
          .clamp(0.0, position.maxScrollExtent);

      _scroll.jumpTo(target);
    } else if (widget.items.isNotEmpty) {
      final first = widget.items.first.due;

      final target = (_edgePad +
              _timeToPx(first) -
              position.viewportDimension * 0.25)
          .clamp(0.0, position.maxScrollExtent);

      _scroll.jumpTo(target);
    }
  }

  void _anchorAfterDayChange(DateTime oldDay) {
    if (!_scroll.hasClients) return;

    final position = _scroll.position;

    if (position.viewportDimension <= 0) return;

    final now = DateTime.now();

    if (_isSameDay(widget.selectedDay, now)) {
      final target = (_edgePad +
              _timeToPx(now) -
              position.viewportDimension * 0.42)
          .clamp(0.0, position.maxScrollExtent);

      _scroll.jumpTo(target);
    } else if (widget.items.isNotEmpty) {
      final first = widget.items.first.due;

      final target = (_edgePad +
              _timeToPx(first) -
              position.viewportDimension * 0.25)
          .clamp(0.0, position.maxScrollExtent);

      _scroll.jumpTo(target);
    } else if (widget.selectedDay.isAfter(oldDay)) {
      _scroll.jumpTo(0);
    } else {
      _scroll.jumpTo(position.maxScrollExtent);
    }

    _lastNavAt = DateTime.now();
  }

  /// Allows the user to continue dragging through the edge of the timeline
  /// into the previous/next day.
  bool _onScroll(ScrollNotification notification) {
    if (!_scroll.hasClients) return false;

    if (notification is! ScrollUpdateNotification ||
        notification.dragDetails == null) {
      return false;
    }

    final position = _scroll.position;

    if (position.maxScrollExtent <= 0) return false;

    if (DateTime.now().difference(_lastNavAt).inMilliseconds < 300) {
      return false;
    }

    final delta = notification.scrollDelta ?? 0;

    if (delta > 0 && position.pixels >= position.maxScrollExtent - 0.5) {
      widget.onNextDay();
      return true;
    }

    if (delta < 0 && position.pixels <= 0.5) {
      widget.onPrevDay();
      return true;
    }

    return false;
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final selected = widget.selectedDay;
    final isToday = _isSameDay(selected, DateTime.now());

    return Container(
      width: double.infinity,
      height: _bodyHeight,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: context.cerebrum.surface.outlineStrong.withAlpha(60),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildDateColumn(selected),
          Expanded(
            child: MouseRegion(
              onEnter: (_) => _hovering = true,
              onExit: (_) => _hovering = false,
              child: Listener(
                onPointerSignal: _onPointerSignal,
                child: _buildTimeline(isToday),
              ),
            ),
          ),
          _buildCountersColumn(),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Date column
  // ---------------------------------------------------------------------------

  Widget _buildDateColumn(DateTime selected) {
    const weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];

    const months = [
      'JAN',
      'FEB',
      'MAR',
      'APR',
      'MAY',
      'JUN',
      'JUL',
      'AUG',
      'SEP',
      'OCT',
      'NOV',
      'DEC',
    ];

    final isToday = _isSameDay(selected, DateTime.now());

    return SizedBox(
      width: _dateWidth,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 10, 4, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              weekdays[selected.weekday - 1],
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                height: 1,
                fontWeight: FontWeight.w500,
                color: context.cerebrum.brand.ink.withValues(alpha: 0.9),
              ),
            ),

            const SizedBox(height: 3),

            // Big numerals: at large display text scales a month like "SEP"
            // is wider than the 64px date column and would wrap glyph-by-
            // glyph into 3 stacked lines (a real overflow seen at scale ~1.5).
            // softWrap:false keeps them on ONE line at natural width and
            // FittedBox scales the line down instead — never wraps, never
            // overflows.
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.topCenter,
              child: Text(
                '${selected.day}',
                softWrap: false,
                style: TextStyle(
                  fontSize: 31,
                  height: 0.95,
                  fontWeight: FontWeight.w800,
                  color: context.cerebrum.brand.ink,
                ),
              ),
            ),

            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                months[selected.month - 1],
                softWrap: false,
                style: TextStyle(
                  fontSize: 28,
                  height: 0.95,
                  fontWeight: FontWeight.w800,
                  color: context.cerebrum.brand.ink,
                ),
              ),
            ),

            // Bottom block (day arrows + TODAY) is pinned to the bottom when
            // there is room but NEVER allowed to overflow the column: an
            // OverflowBox passes unbounded height so the block keeps its
            // natural size and clips at worst on tiny/large-scaled layouts —
            // the RenderFlex overflow error is structurally impossible here,
            // regardless of font metrics or text scale.
            Expanded(
              child: OverflowBox(
                alignment: Alignment.bottomLeft,
                minHeight: 0,
                maxHeight: double.infinity,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isToday)
                      GestureDetector(
                        onTap: widget.onOpenCalendar,
                        child: Text(
                          'TODAY',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                            color: context.cerebrum.status.dangerDeep,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Counters column
  // ---------------------------------------------------------------------------

  /// Right-side, fixed companion to the date column: user-global overdue and
  /// unscheduled counts, always visible regardless of where the timeline is
  /// panned. The overdue counter is tappable → Learning Center, mirroring the
  /// header banner; the overlap here is deliberate (the rail row of an overdue
  /// day and this counter are different surfaces for the same number).
  ///
  /// Numbers are short, but the word labels would wrap at large display text
  /// scales — each label gets a FittedBox so it scales down instead of
  /// wrapping, same overflow-proofing as the date column.
  Widget _buildCountersColumn() {
    return SizedBox(
      width: _countersWidth,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 10, 8, 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: widget.onOpenLearningCenter,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${widget.overdueCount}',
                      style: TextStyle(
                        fontSize: 16,
                        height: 1,
                        fontWeight: FontWeight.w700,
                        color: context.cerebrum.status.dangerDeep,
                      ),
                    ),
                    const SizedBox(height: 3),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'overdue',
                        softWrap: false,
                        style: TextStyle(
                          fontSize: 11,
                          height: 1,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                          color: context.cerebrum.status.dangerDeep,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${widget.unscheduledCount}',
                  style: TextStyle(
                    fontSize: 16,
                    height: 1,
                    fontWeight: FontWeight.w400,
                    color: context.cerebrum.brand.ink,
                  ),
                ),
                const SizedBox(height: 3),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'unscheduled',
                    softWrap: false,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: context.cerebrum.brand.ink.withValues(alpha: 0.8),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Timeline
  // ---------------------------------------------------------------------------

  Widget _buildTimeline(bool isToday) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Drive the hour scale off the viewport: exactly 6 hours visible.
        // The 24h day is then 4 viewports wide — a fixed "6-hour window" the
        // user pans through, never a full-view day.
        _hourWidth = constraints.maxWidth / 6;
        return NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: SingleChildScrollView(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            physics: const ClampingScrollPhysics(),
            child: SizedBox(
              width: _timelineWidth,
              height: _bodyHeight,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  _buildHourColumns(),

                  for (final placed in _visibleLayout) _buildGanttBar(placed),

                  if (isToday) _buildNowCursor(),

                  if (_hiddenCount > 0) _buildMoreHint(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// "+N more" hint under the last visible row — renders only when the row
  /// cap hid anything. Sits in its own reserved strip so it never overlaps
  /// bars or the "+" row.
  Widget _buildMoreHint() {
    return Positioned(
      left: _edgePad + 2,
      right: _edgePad,
      top: _axisHeight + _visibleRowCount * (_rowHeight + _rowGap),
      height: _hintStripHeight - 2,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          '+$_hiddenCount more',
          style: TextStyle(
            fontSize: 8,
            height: 1,
            fontWeight: FontWeight.w600,
            color: context.cerebrum.brand.ink.withValues(alpha: 0.75),
          ),
        ),
      ),
    );
  }

  Widget _buildHourColumns() {
    return Positioned.fill(
      child: Stack(
        children: [
          for (var hour = 0; hour < 24; hour++)
            Positioned(
              left: _edgePad + hour * _hourWidth,
              top: 0,
              bottom: 0,
              width: _hourWidth,
              child: _buildHourColumn(hour),
            ),
        ],
      ),
    );
  }

  Widget _buildHourColumn(int hour) {
    final isCurrentHour =
        _isSameDay(widget.selectedDay, DateTime.now()) &&
        DateTime.now().hour == hour;

    return Container(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: context.cerebrum.brand.ink.withValues(
              alpha: isCurrentHour ? 0.55 : 0.28,
            ),
            width: isCurrentHour ? 1.2 : 0.7,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(left: 5, top: 9, right: 4),
        child: Align(
          alignment: Alignment.topLeft,
          child: Text(
            formatRailHour(hour),
            style: TextStyle(
              fontSize: 8,
              height: 1,
              fontWeight: isCurrentHour ? FontWeight.w700 : FontWeight.w400,
              color: context.cerebrum.brand.ink.withValues(
                alpha: isCurrentHour ? 1 : 0.8,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Gantt bars
  // ---------------------------------------------------------------------------

  /// A bar anchored at the item's real due instant, spanning [duration]
  /// minutes at hour scale. Width clamps to the day edge so a bar can't paint
  /// into the next day (and to a readable minimum).
  Widget _buildGanttBar(({ScheduleItem item, int row}) placed) {
    final item = placed.item;
    final overdue = item.due.isBefore(DateTime.now());

    final left = _edgePad + _timeToPx(item.due);
    final rawWidth = item.duration.inMinutes * (_hourWidth / 60);
    final available = _timelineWidth - left;
    final width = rawWidth.clamp(8.0, math.max(8.0, available)).toDouble();

    final top = _axisHeight + placed.row * (_rowHeight + _rowGap);

    return Positioned(
      left: left,
      top: top,
      width: width,
      height: _rowHeight,
      child: GestureDetector(
        onTap: () {
          // Event interaction can be wired here later.
        },
        child: Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color:
                overdue
                    ? context.cerebrum.status.dangerDeep
                    : context.cerebrum.brand.ink,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 8,
              height: 1,
              color: context.cerebrum.surface.raised,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Now indicator
  // ---------------------------------------------------------------------------

  Widget _buildNowCursor() {
    final now = DateTime.now();
    final x = _edgePad + _timeToPx(now);

    return Positioned(
      key: const ValueKey('now-cursor'),
      left: x - 0.75,
      top: _axisHeight,
      bottom: _bottomPad,
      child: Container(
        width: 1.5,
        decoration: BoxDecoration(
          color: context.cerebrum.status.dangerDeep,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Wheel pan
  // ---------------------------------------------------------------------------

  /// Makes the mouse wheel pan the timeline (dx+dy like the plan-portfolio
  /// gantt). The wheel is owned by the rail while the pointer hovers it —
  /// every scroll event is consumed even at the min/max ends, so the outer
  /// page is NOT kicked down mid-pan. Only once the mouse physically leaves
  /// the rail ([_hovering] false) do wheel events fall through to the page.
  /// `pointerScroll` still clamps at the ends, so at the extremes the rail
  /// simply stays put while the event is absorbed.
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (!_scroll.hasClients) return;
    if (!_hovering) return;
    final position = _scroll.position;
    final delta = event.scrollDelta.dx + event.scrollDelta.dy;
    if (delta == 0) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (e) {
      position.pointerScroll(delta);
    });
  }
}
// ── Mini calendar ───────────────────────────────────────────────────────────

/// A small month grid with per-day badges: a red circle with the count of
/// OVERDUE items when the day has any, otherwise a neutral badge with the
/// total scheduled count. Tapping a day returns it (pops with the [DateTime]).
class _MiniCalendarDialog extends StatefulWidget {
  final DateTime initialDay;
  final DateTime today;
  final Map<DateTime, int> countsByDay;
  final Map<DateTime, int> overdueByDay;

  const _MiniCalendarDialog({
    required this.initialDay,
    required this.today,
    required this.countsByDay,
    required this.overdueByDay,
  });

  @override
  State<_MiniCalendarDialog> createState() => _MiniCalendarDialogState();
}

class _MiniCalendarDialogState extends State<_MiniCalendarDialog> {
  late DateTime _selected;
  late DateTime _displayed; // first day of the displayed month

  @override
  void initState() {
    super.initState();
    _selected = widget.initialDay;
    _displayed = DateTime(widget.initialDay.year, widget.initialDay.month, 1);
  }

  void _shiftMonth(int delta) {
    setState(() {
      _displayed = DateTime(_displayed.year, _displayed.month + delta, 1);
    });
  }

  void _shiftYear(int delta) {
    setState(() {
      _displayed = DateTime(_displayed.year + delta, _displayed.month, 1);
    });
  }

  void _pick(DateTime day) => Navigator.of(context).pop(day);

  @override
  Widget build(BuildContext context) {
    const weekdays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
    const months = [
      "Jan",
      "Feb",
      "Mar",
      "Apr",
      "May",
      "Jun",
      "Jul",
      "Aug",
      "Sep",
      "Oct",
      "Nov",
      "Dec",
    ];

    final firstWeekday = _displayed.weekday; // 1=Mon..7=Sun
    final daysInMonth = DateTime(_displayed.year, _displayed.month + 1, 0).day;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Month header.
            Row(
              children: [
                IconButton(
                  onPressed: () => _shiftMonth(-1),
                  icon: const Icon(Icons.chevron_left),
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      '${months[_displayed.month - 1]} ${_displayed.year}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: context.cerebrum.brand.ink,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => _shiftMonth(1),
                  icon: const Icon(Icons.chevron_right),
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            // Year header, smaller.
            Row(
              children: [
                InkWell(
                  onTap: () => _shiftYear(-1),
                  child: Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(
                      Icons.arrow_left,
                      size: 14,
                      color: context.cerebrum.brand.ink,
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      '${_displayed.year}',
                      style: TextStyle(
                        fontSize: 10,
                        color: context.cerebrum.brand.ink.withValues(
                          alpha: 0.7,
                        ),
                      ),
                    ),
                  ),
                ),
                InkWell(
                  onTap: () => _shiftYear(1),
                  child: Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(
                      Icons.arrow_right,
                      size: 14,
                      color: context.cerebrum.brand.ink,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Weekday header.
            Row(
              children: [
                for (final w in weekdays)
                  Expanded(
                    child: Center(
                      child: Text(
                        w,
                        style: TextStyle(
                          fontSize: 9,
                          color: context.cerebrum.brand.ink.withValues(
                            alpha: 0.6,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            // Day grid.
            _buildDayGrid(firstWeekday, daysInMonth),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => _pick(widget.today),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(0, 28),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Today', style: TextStyle(fontSize: 11)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDayGrid(int firstWeekday, int daysInMonth) {
    final cells = <Widget>[];
    final leading = firstWeekday - 1; // empty cells before the 1st
    for (var i = 0; i < leading; i++) {
      cells.add(const SizedBox.square(dimension: 36));
    }
    for (var d = 1; d <= daysInMonth; d++) {
      cells.add(_dayCell(DateTime(_displayed.year, _displayed.month, d)));
    }

    return Wrap(spacing: 2, runSpacing: 2, children: cells);
  }

  Widget _dayCell(DateTime day) {
    final count = widget.countsByDay[day] ?? 0;
    final overdue = widget.overdueByDay[day] ?? 0;
    final selected = _isSameDay(day, _selected);

    return InkWell(
      onTap: () => _pick(day),
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 36,
        height: 36,
        child: Stack(
          children: [
            Center(
              child: Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color:
                      selected
                          ? context.cerebrum.brand.ink.withValues(alpha: 0.12)
                          : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${day.day}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                    color: context.cerebrum.brand.ink,
                  ),
                ),
              ),
            ),
            if (count > 0)
              Positioned(
                top: 1,
                right: 1,
                child: Container(
                  width: 14,
                  height: 14,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color:
                        overdue > 0
                            ? context.cerebrum.status.dangerDeep
                            : context.cerebrum.status.neutralSoft,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${overdue > 0 ? overdue : count}',
                    style: TextStyle(
                      fontSize: 7,
                      color: context.cerebrum.text.onDark,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
