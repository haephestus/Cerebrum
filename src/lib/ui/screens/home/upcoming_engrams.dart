import 'package:flutter/material.dart';
import 'package:cerebrum/api/learning_center_api.dart';
import 'package:cerebrum/models/engram_models.dart';
import 'package:cerebrum/services/user_session.dart';

class EngramItem {
  final String title;

  /// Real due time (from the daemon's `scheduled_at`) rendered as "9 am",
  /// or "Overdue" when the due time has passed. Null when the daemon has not
  /// scheduled this engram — render NO time in that case (homepage Phase 2
  /// honesty rule: never a synthesized hour).
  final String? time;
  final String engramId;

  const EngramItem({required this.title, required this.engramId, this.time});
}

class DaySchedule {
  /// The real due date this bucket groups. Null means the daemon has not
  /// scheduled these engrams (bucket labelled "Upcoming", not a fake date).
  final DateTime? date;
  final List<EngramItem> items;

  const DaySchedule({required this.date, required this.items});

  bool get isScheduled => date != null;
}

/// Groups engrams by their REAL due date (daemon `scheduled_at`), oldest due
/// day first. Engrams without a schedule land in a single "Upcoming" bucket
/// with a null date; their time chips render empty. Pure + unit-tested: the
/// schedule always comes from daemon data, never synthesized hours.
List<DaySchedule> buildDaysFromEngrams(List<Engram> engrams, {DateTime? now}) {
  final scheduled = <DateTime, List<Engram>>{};
  final unscheduled = <Engram>[];
  final reference = now ?? DateTime.now();

  for (final e in engrams) {
    final due = e.scheduledAt;
    if (due == null) {
      unscheduled.add(e);
      continue;
    }
    // Bucket key is the LOCAL day of the due instant. An overdue engram still
    // belongs to its own day — the chip says "Overdue", not a lie.
    final day = DateTime(due.year, due.month, due.day);
    scheduled.putIfAbsent(day, () => []).add(e);
  }

  final orderedDays = scheduled.keys.toList()..sort();
  return [
    for (final day in orderedDays)
      DaySchedule(
        date: day,
        items: [
          for (final e in scheduled[day]!)
            EngramItem(
              title: _engramTitle(e.type),
              engramId: e.id,
              time: _engramTime(e, now: reference),
            ),
        ],
      ),
    if (unscheduled.isNotEmpty)
      DaySchedule(
        date: null, // "Upcoming" — no real due date to claim
        items: [
          for (final e in unscheduled)
            EngramItem(title: _engramTitle(e.type), engramId: e.id),
        ],
      ),
  ];
}

String _engramTitle(EngramType type) => switch (type) {
  EngramType.mcq => "MCQ",
  EngramType.flashcard => "Flashcard",
  EngramType.shortQuestion => "Short Q",
  EngramType.longQuestion => "Long Q",
  EngramType.unknown => "Engram",
};

/// Real due time rendered as "9 am" / "1 pm"; "Overdue" once it has passed.
String? _engramTime(Engram e, {required DateTime now}) {
  final due = e.scheduledAt;
  if (due == null) return null;
  if (due.isBefore(now)) return 'Overdue';
  return _formatHour(due.hour);
}

/// 24h hour → "9 am" / "1 pm".
String _formatHour(int hour24) {
  final h = hour24 % 24;
  final period = h < 12 ? 'am' : 'pm';
  final display = h % 12 == 0 ? 12 : h % 12;
  return '$display $period';
}

class UpcomingEngramsSection extends StatefulWidget {
  const UpcomingEngramsSection({super.key});

  @override
  State<UpcomingEngramsSection> createState() => _UpcomingEngramsSectionState();
}

class _UpcomingEngramsSectionState extends State<UpcomingEngramsSection>
    with WidgetsBindingObserver {
  bool _loading = true; // only true until the FIRST fetch resolves
  bool _fetching = false; // guards against overlapping fetches
  List<DaySchedule> _days = const [];

  @override
  void initState() {
    super.initState();
    // Re-fetch when the app returns to the foreground (engrams may have been
    // generated while we were away). Navigating back to the home tab already
    // rebuilds this widget, so that path re-fetches on its own.
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
  /// dashboard is the global view, and the daemon's list_engrams already
  /// supports "none → all". A [background] refresh keeps the current cards
  /// visible (no spinner, no blanking) and, on failure, leaves whatever was
  /// already shown — so the section quietly appears when engrams arrive and
  /// disappears (shrinks) when there are none.
  Future<void> _loadEngrams({bool background = false}) async {
    if (_fetching) return;
    _fetching = true;
    try {
      // REAL client identity (the old literal user id did not exist). The
      // hardcoded bubble/note ids are gone: user-level scope is the honest
      // global-dashboard semantic.
      final userId = await UserSession.getUserId();
      if (userId == null) {
        if (!background) setState(() => _loading = false);
        return;
      }

      final response = await LearningCenterApi.listEngrams(userId: userId);

      if (!mounted) return;

      // Real schedule grouping from the daemon's scheduled_at; unscheduled
      // engrams land in an "Upcoming" bucket with no fake due time.
      final days = buildDaysFromEngrams(response.engrams);

      setState(() {
        _days = days;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      // On a background refresh keep whatever we had; only the first load
      // resolves the spinner on failure.
      if (!background) setState(() => _loading = false);
    } finally {
      _fetching = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 150,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_days.isEmpty) {
      return const SizedBox.shrink();
    }

    return UpcomingEngramsList(
      days: _days,
      onTapEngram: (item) {
        // Navigate to attempt screen
      },
    );
  }
}

/// Stacks one DayEngramsCard per day, cycling through the accent palette.
///
/// A shrink-wrapping [ListView] inside a [ConstrainedBox]: it sizes to its
/// content up to [_maxHeight] and then scrolls, so it can never overflow its
/// parent no matter how many days there are or how the window is scaled.
class UpcomingEngramsList extends StatelessWidget {
  final List<DaySchedule> days;
  final ValueChanged<EngramItem>? onTapEngram;

  const UpcomingEngramsList({super.key, required this.days, this.onTapEngram});

  static const double _maxHeight = 340;

  static const _palette = [
    Color(0xffB8AFD1), // lavender
    Color(0xffCFA6A6), // dusty rose
    Color(0xff8FBFB3), // teal
  ];

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: _maxHeight),
      child: ListView.separated(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: days.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder:
            (context, i) => DayEngramsCard(
              schedule: days[i],
              color: _palette[i % _palette.length],
              onTapEngram: onTapEngram,
            ),
      ),
    );
  }
}

class DayEngramsCard extends StatelessWidget {
  final DaySchedule schedule;
  final Color color;
  final ValueChanged<EngramItem>? onTapEngram;

  const DayEngramsCard({
    super.key,
    required this.schedule,
    required this.color,
    this.onTapEngram,
  });

  static const _days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
  static const _months = [
    "JAN",
    "FEB",
    "MAR",
    "APR",
    "MAY",
    "JUN",
    "JUL",
    "AUG",
    "SEP",
    "OCT",
    "NOV",
    "DEC",
  ];
  static const _ink = Color(0xff2F2940);

  @override
  Widget build(BuildContext context) {
    // Chip colour = a darkened shade of the card colour (matches the design).
    final chipColor = Color.lerp(color, Colors.black, 0.5)!;
    final date = schedule.date;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      // IntrinsicHeight + stretch: the row sizes to its tallest column and the
      // slot dividers span the full height — no fixed heights to overflow.
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 82,
              child:
                  date == null
                      ? const _UnscheduledLabel()
                      : Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _days[date.weekday - 1],
                            style: const TextStyle(fontSize: 12, color: _ink),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "${date.day}",
                            style: const TextStyle(
                              fontSize: 40,
                              fontWeight: FontWeight.bold,
                              height: .9,
                              color: _ink,
                            ),
                          ),
                          Text(
                            _months[date.month - 1],
                            style: const TextStyle(fontSize: 15, color: _ink),
                          ),
                        ],
                      ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child:
                  schedule.items.isEmpty
                      ? const _EmptySlots()
                      : Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < schedule.items.length; i++)
                            Expanded(
                              child: Container(
                                // No leading line on the first slot (it hugs the
                                // date); a divider before every other slot.
                                decoration:
                                    i == 0
                                        ? null
                                        : BoxDecoration(
                                          border: Border(
                                            left: BorderSide(
                                              color: Colors.black.withValues(
                                                alpha: 0.28,
                                              ),
                                              width: 1.5,
                                            ),
                                          ),
                                        ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                child: EngramColumn(
                                  item: schedule.items[i],
                                  chipColor: chipColor,
                                  onTap:
                                      () =>
                                          onTapEngram?.call(schedule.items[i]),
                                ),
                              ),
                            ),
                        ],
                      ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Date column for an unscheduled queue: honest label instead of a fake date.
class _UnscheduledLabel extends StatelessWidget {
  const _UnscheduledLabel();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Upcoming",
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xff2F2940),
          ),
        ),
        SizedBox(height: 2),
        Text(
          "no due time yet",
          style: TextStyle(fontSize: 10, color: Color(0xff2F2940)),
        ),
      ],
    );
  }
}

/// Placeholder shown on a day with no engrams (keeps the card a sensible size).
class _EmptySlots extends StatelessWidget {
  const _EmptySlots();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 90,
      child: Center(
        child: Text(
          'No engrams scheduled',
          style: TextStyle(fontSize: 12, color: Color(0xff2F2940)),
        ),
      ),
    );
  }
}

class EngramColumn extends StatelessWidget {
  final EngramItem item;
  final Color chipColor;
  final VoidCallback? onTap;

  const EngramColumn({
    super.key,
    required this.item,
    required this.chipColor,
    this.onTap,
  });

  static const _ink = Color(0xff2F2940);

  @override
  Widget build(BuildContext context) {
    final time = item.time ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Real due time when the daemon supplies it; empty otherwise (no fake
        // hours). Overdue is shown verbatim as the chip's time state.
        Text(
          time,
          style: TextStyle(
            fontSize: 10,
            color: time == 'Overdue' ? const Color(0xff8C2F2F) : _ink,
            fontWeight: time == 'Overdue' ? FontWeight.w700 : FontWeight.w400,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 10),
        // Every engram shows its chip (previously only the first did).
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: chipColor,
            borderRadius: BorderRadius.circular(6),
          ),
          alignment: Alignment.center,
          child: Text(
            item.title,
            style: const TextStyle(color: Colors.white, fontSize: 9),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const Spacer(),
        const SizedBox(height: 8),
        InkWell(
          onTap: onTap,
          child: const Icon(Icons.add_circle_outline, size: 18, color: _ink),
        ),
      ],
    );
  }
}
