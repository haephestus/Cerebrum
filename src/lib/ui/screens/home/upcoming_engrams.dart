import 'package:flutter/material.dart';
import 'package:cerebrum/api/learning_center_api.dart';
import 'package:cerebrum/models/engram_models.dart';

class EngramItem {
  final String title;
  final String? time;
  final String engramId;

  const EngramItem({required this.title, required this.engramId, this.time});
}

class DaySchedule {
  final DateTime date;
  final List<EngramItem> items;

  const DaySchedule({required this.date, required this.items});
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

  /// Fetches the upcoming engrams. A [background] refresh keeps the current
  /// cards visible (no spinner, no blanking) and, on failure, leaves whatever
  /// was already shown — so the section quietly appears/updates when engrams
  /// arrive and disappears (shrinks) when there are none.
  Future<void> _loadEngrams({bool background = false}) async {
    if (_fetching) return;
    _fetching = true;
    try {
      final response = await LearningCenterApi.listEngrams(
        bubbleId: "1edae102638a8cd7882e6de1c1e9639e",
        noteId: "01KTC4MWWA4YNSYNTYDYBEKB52",
        userId: "d6f3f2f2aff44185b7d97d160ffdec38",
      );

      if (!mounted) return;

      // PLACEHOLDER scheduling: the API doesn't return due times yet, so we
      // synthesize an ascending hour per engram just so the time column renders
      // like the design. TODO: group by real due date + show the real hour once
      // the backend supplies it (then drop the `slotHour` argument below).
      final items = [
        for (var i = 0; i < response.engrams.length; i++)
          _mapEngram(response.engrams[i], slotHour: 9 + i),
      ];

      setState(() {
        _days = items.isEmpty
            ? const []
            : [DaySchedule(date: DateTime.now(), items: items)];
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

  EngramItem _mapEngram(Engram e, {required int slotHour}) {
    final title = switch (e.type) {
      EngramType.mcq => "MCQ",
      EngramType.flashcard => "Flashcard",
      EngramType.shortQuestion => "Short Q",
      EngramType.longQuestion => "Long Q",
      EngramType.unknown => "Engram",
    };

    return EngramItem(title: title, time: _formatHour(slotHour), engramId: e.id);
  }

  /// 24h hour → "9 am" / "1 pm" (placeholder until real schedule data lands).
  static String _formatHour(int hour24) {
    final h = hour24 % 24;
    final period = h < 12 ? 'am' : 'pm';
    final display = h % 12 == 0 ? 12 : h % 12;
    return '$display $period';
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
        itemBuilder: (context, i) => DayEngramsCard(
          date: days[i].date,
          items: days[i].items,
          color: _palette[i % _palette.length],
          onTapEngram: onTapEngram,
        ),
      ),
    );
  }
}

class DayEngramsCard extends StatelessWidget {
  final DateTime date;
  final List<EngramItem> items;
  final Color color;
  final ValueChanged<EngramItem>? onTapEngram;

  const DayEngramsCard({
    super.key,
    required this.date,
    required this.items,
    required this.color,
    this.onTapEngram,
  });

  static const _days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

  static const _months = [
    "JAN", "FEB", "MAR", "APR", "MAY", "JUN",
    "JUL", "AUG", "SEP", "OCT", "NOV", "DEC",
  ];

  static const _ink = Color(0xff2F2940);

  @override
  Widget build(BuildContext context) {
    // Chip colour = a darkened shade of the card colour (matches the design).
    final chipColor = Color.lerp(color, Colors.black, 0.5)!;

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
              child: Column(
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
              child: items.isEmpty
                  ? const _EmptySlots()
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < items.length; i++)
                          Expanded(
                            child: Container(
                              // No leading line on the first slot (it hugs the
                              // date); a divider before every other slot.
                              decoration: i == 0
                                  ? null
                                  : BoxDecoration(
                                      border: Border(
                                        left: BorderSide(
                                          color: Colors.black
                                              .withValues(alpha: 0.28),
                                          width: 1.5,
                                        ),
                                      ),
                                    ),
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: EngramColumn(
                                item: items[i],
                                chipColor: chipColor,
                                onTap: () => onTapEngram?.call(items[i]),
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
          style: TextStyle(
            fontSize: 12,
            color: Color(0xff2F2940),
          ),
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
        // Hour symbol for when this engram is scheduled.
        Text(
          time,
          style: const TextStyle(fontSize: 10, color: _ink),
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
