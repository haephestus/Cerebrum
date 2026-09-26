import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cerebrum/models/engram_models.dart';
import 'package:cerebrum/ui/screens/home/upcoming_engrams.dart';

String _isoToday() {
  final n = DateTime.now();
  final y = n.year.toString().padLeft(4, '0');
  final m = n.month.toString().padLeft(2, '0');
  final d = n.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

Engram _engram({required String id, String? scheduledAt}) => Engram(
  id: id,
  noteId: 'n1',
  type: EngramType.flashcard,
  targetCognitiveLevel: 2,
  tags: const [],
  content: FlashcardContent(
    findingIndex: 0,
    cardNumber: 1,
    front: 'front',
    back: 'back',
    severity: 'low',
  ),
  scheduledAt: scheduledAt == null ? null : DateTime.parse(scheduledAt),
);

void main() {
  group('buildDayItems', () {
    test('keeps only items due on the selected day, sorted by due time', () {
      final day = DateTime(2026, 9, 12);
      final items = buildDayItems([
        _engram(id: 'b', scheduledAt: '2026-09-12T22:30:00'),
        _engram(id: 'a', scheduledAt: '2026-09-12T09:00:00'),
        _engram(id: 'c', scheduledAt: '2026-09-13T00:30:00'), // next day
        _engram(id: 'd', scheduledAt: '2026-09-11T23:59:00'), // prev day
      ], day);

      expect(items.map((i) => i.id), ['a', 'b']);
    });

    test('includes 00:00 as the first instant of the day', () {
      final day = DateTime(2026, 9, 12);
      final items = buildDayItems([
        _engram(id: 'boundary', scheduledAt: '2026-09-12T00:00:00'),
      ], day);

      expect(items.single.id, 'boundary');
      expect(items.single.due.hour, 0);
      expect(items.single.due.minute, 0);
    });

    test('excludes unscheduled engrams entirely', () {
      final day = DateTime(2026, 9, 12);
      final items = buildDayItems([
        _engram(id: 'scheduled', scheduledAt: '2026-09-12T10:00:00'),
        _engram(id: 'unscheduled'),
      ], day);

      expect(items.map((i) => i.id), ['scheduled']);
    });

    test('empty day returns an empty list', () {
      final day = DateTime(2026, 9, 12);
      final items = buildDayItems([
        _engram(id: 'other-day', scheduledAt: '2026-09-30T10:00:00'),
      ], day);

      expect(items, isEmpty);
    });

    test('keeps the real due instant on the item', () {
      final day = DateTime(2026, 9, 12);
      final items = buildDayItems([
        _engram(id: 'a', scheduledAt: '2026-09-12T14:30:00'),
      ], day);

      expect(items.single.due.hour, 14);
      expect(items.single.due.minute, 30);
    });
  });

  group('buildDayCounts', () {
    test('counts items per local day', () {
      final counts = buildDayCounts([
        _engram(id: 'a', scheduledAt: '2026-09-12T09:00:00'),
        _engram(id: 'b', scheduledAt: '2026-09-12T22:00:00'),
        _engram(id: 'c', scheduledAt: '2026-09-13T10:00:00'),
      ]);

      expect(counts[DateTime(2026, 9, 12)], 2);
      expect(counts[DateTime(2026, 9, 13)], 1);
      expect(counts.length, 2);
    });

    test('excludes unscheduled engrams', () {
      final counts = buildDayCounts([
        _engram(id: 'a', scheduledAt: '2026-09-12T09:00:00'),
        _engram(id: 'unscheduled'),
      ]);

      expect(counts[DateTime(2026, 9, 12)], 1);
    });
  });

  group('buildOverdueDayCounts', () {
    test('flags per-day counts of items due before now', () {
      final now = DateTime(2026, 9, 12, 12);
      final overdue = buildOverdueDayCounts([
        _engram(id: 'a', scheduledAt: '2026-09-12T09:00:00'), // earlier today
        _engram(id: 'b', scheduledAt: '2026-09-12T22:00:00'), // later today
        _engram(id: 'c', scheduledAt: '2026-09-11T10:00:00'), // yesterday
      ], now: now);

      expect(overdue[DateTime(2026, 9, 12)], 1);
      expect(overdue[DateTime(2026, 9, 11)], 1);
      expect(overdue.length, 2);
    });

    test('unscheduled engrams never count as overdue', () {
      final now = DateTime(2026, 9, 12, 12);
      final overdue = buildOverdueDayCounts([
        _engram(id: 'unscheduled'),
      ], now: now);

      expect(overdue, isEmpty);
    });
  });

  group('countOverdue', () {
    test('counts user-global items due before now', () {
      final now = DateTime(2026, 9, 12, 12);
      final count = countOverdue([
        _engram(id: 'a', scheduledAt: '2026-09-12T09:00:00'),
        _engram(id: 'b', scheduledAt: '2026-09-12T22:00:00'),
        _engram(id: 'c', scheduledAt: '2026-09-11T10:00:00'),
        _engram(id: 'unscheduled'),
      ], now: now);

      expect(count, 2);
    });

    test('zero when nothing is due before now', () {
      final now = DateTime(2026, 9, 12, 12);
      final count = countOverdue([
        _engram(id: 'a', scheduledAt: '2026-09-12T22:00:00'),
      ], now: now);

      expect(count, 0);
    });
  });

  group('countUnscheduled', () {
    test('counts engrams the daemon has not scheduled yet', () {
      final count = countUnscheduled([
        _engram(id: 'a'),
        _engram(id: 'b', scheduledAt: '2026-09-12T09:00:00'),
        _engram(id: 'c'),
      ]);

      expect(count, 2);
    });

    test('zero when every engram is scheduled (or there are none)', () {
      expect(
        countUnscheduled([
          _engram(id: 'a', scheduledAt: '2026-09-12T09:00:00'),
        ]),
        0,
      );
      expect(countUnscheduled([]), 0);
    });
  });

  group('formatRailHour', () {
    test('midnight and noon are 12, not 0', () {
      expect(formatRailHour(0), '12am');
      expect(formatRailHour(12), '12pm');
    });

    test('morning and evening labels', () {
      expect(formatRailHour(9), '9am');
      expect(formatRailHour(13), '1pm');
      expect(formatRailHour(23), '11pm');
    });
  });

  group('layoutGantt', () {
    ScheduleItem at(String id, String iso, {int minutes = 30}) => ScheduleItem(
      id: id,
      title: id,
      due: DateTime.parse(iso),
      type: EngramType.flashcard,
      duration: Duration(minutes: minutes),
    );

    test('non-overlapping items share row 0', () {
      final layout = layoutGantt([
        at('a', '2026-09-12T09:00:00'),
        at('b', '2026-09-12T10:00:00'),
        at('c', '2026-09-12T14:00:00'),
      ]);

      expect(layout.map((e) => e.row), [0, 0, 0]);
    });

    test('same-hour starts stack onto separate rows', () {
      final layout = layoutGantt([
        at('a', '2026-09-12T09:00:00'),
        at('b', '2026-09-12T09:05:00'), // overlaps a's tail
        at('c', '2026-09-12T09:10:00'), // overlaps both walkers' tails
      ]);

      expect(layout.map((e) => e.row), [0, 1, 2]);
    });

    test(
      'touching bars share a row (one ends exactly when another starts)',
      () {
        final layout = layoutGantt([
          at('a', '2026-09-12T09:00:00'), // ends 09:30
          at('b', '2026-09-12T09:30:00'),
        ]);

        expect(layout.map((e) => e.row), [0, 0]);
      },
    );

    test(
      'greedy backfill reuses the earliest free row in an overlap chain',
      () {
        // a 09:00-10:00, b 09:30-10:30, c 10:00-11:00 → b rows above a,
        // c fits back into a's row the moment a ends.
        final layout = layoutGantt([
          at('a', '2026-09-12T09:00:00', minutes: 60),
          at('b', '2026-09-12T09:30:00', minutes: 60),
          at('c', '2026-09-12T10:00:00', minutes: 60),
        ]);

        expect(layout.map((e) => e.row), [0, 1, 0]);
      },
    );

    test('returns items sorted by due', () {
      final layout = layoutGantt([
        at('b', '2026-09-12T10:00:00'),
        at('a', '2026-09-12T09:00:00'),
      ]);

      expect(layout.map((e) => e.item.id), ['a', 'b']);
    });

    test('empty input yields no rows', () {
      expect(layoutGantt([]), isEmpty);
    });
  });

  group('ScheduleRail layout', () {
    ScheduleItem item(String id, String iso, {int minutes = 30}) =>
        ScheduleItem(
          id: id,
          title: 'MCQ $id',
          due: DateTime.parse(iso),
          type: EngramType.flashcard,
          duration: Duration(minutes: minutes),
        );

    Future<void> pumpRail(
      WidgetTester tester, {
      required DateTime day,
      List<ScheduleItem> items = const [],
      int overdueCount = 0,
      int unscheduledCount = 0,
    }) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScheduleRail(
              selectedDay: day,
              items: items,
              overdueCount: overdueCount,
              unscheduledCount: unscheduledCount,
              onPrevDay: () {},
              onNextDay: () {},
              onOpenCalendar: () {},
              onOpenLearningCenter: () {},
            ),
          ),
        ),
      );
    }

    testWidgets('renders a filled day without a layout storm', (tester) async {
      await pumpRail(
        tester,
        day: DateTime(2026, 9, 12),
        items: [
          item('a', '2026-09-12T09:00:00'),
          item('b', '2026-09-12T09:15:00'), // overlaps a → stacks a row down
          item('c', '2026-09-12T14:00:00'),
          item('d', '2026-09-12T23:59:00'), // edge of the day, bar clamps
        ],
      );
      await tester.pump();

      expect(find.text('MCQ a'), findsOneWidget);
      expect(find.text('MCQ b'), findsOneWidget);
      expect(find.text('MCQ c'), findsOneWidget);
      expect(find.text('MCQ d'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('same-hour items stack into separate gantt rows', (
      tester,
    ) async {
      await pumpRail(
        tester,
        day: DateTime(2026, 9, 12),
        items: [
          item('a', '2026-09-12T09:00:00'),
          item('b', '2026-09-12T09:10:00'),
          item('c', '2026-09-12T09:20:00'),
        ],
      );
      await tester.pump();

      final aY = tester.getTopLeft(find.text('MCQ a')).dy;
      final bY = tester.getTopLeft(find.text('MCQ b')).dy;
      final cY = tester.getTopLeft(find.text('MCQ c')).dy;

      expect(aY, lessThan(bY));
      expect(bY, lessThan(cY));
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders an empty day and still paints the 24h axis', (
      tester,
    ) async {
      await pumpRail(tester, day: DateTime(2026, 9, 12));
      await tester.pump();

      expect(find.text('12am'), findsOneWidget);
      expect(find.text('12pm'), findsOneWidget);
      expect(find.text('9pm'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows a fixed 6-hour window over a ~4-viewport-wide day', (
      tester,
    ) async {
      await pumpRail(tester, day: DateTime(2026, 9, 12));
      await tester.pump();

      final scrollable = tester.widget<SingleChildScrollView>(
        find.byType(SingleChildScrollView),
      );
      expect(scrollable.scrollDirection, Axis.horizontal);

      final position =
          tester.state<ScrollableState>(find.byType(Scrollable)).position;
      // hourWidth = viewport/6 → the 24h day is 4 viewports wide, so the
      // user must pan ~3 viewports to reach 23:59. Proves the rail is a
      // window, not a full-view timeline.
      expect(
        position.maxScrollExtent,
        greaterThan(2 * position.viewportDimension),
      );
      expect(position.viewportDimension, lessThan(position.maxScrollExtent));
    });

    testWidgets('shows the now-cursor when the selected day is today', (
      tester,
    ) async {
      final today = DateTime.now();
      await pumpRail(tester, day: today);
      await tester.pump();

      expect(find.byKey(const ValueKey('now-cursor')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('hides the now-cursor on non-today days', (tester) async {
      final otherDay = DateTime.now().subtract(const Duration(days: 1));
      await pumpRail(tester, day: otherDay);
      await tester.pump();

      expect(find.byKey(const ValueKey('now-cursor')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no overflow under large text scaling (real-fonts case) ', (
      tester,
    ) async {
      // The date column used to overflow with real font metrics / display
      // text scaling even though Ahem-font tests passed. The bottom block
      // (arrows + TODAY) must clip, never throw.
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await pumpRail(
        tester,
        day: DateTime.now(), // today → TODAY label renders
        items: [
          item('a', '${_isoToday()}T09:00:00'),
          item('b', '${_isoToday()}T09:10:00'),
        ],
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('arrow taps fire the day-change callbacks', (tester) async {
      var prev = 0;
      var next = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScheduleRail(
              selectedDay: DateTime(2026, 9, 12),
              items: const [],
              overdueCount: 0,
              unscheduledCount: 0,
              onPrevDay: () => prev++,
              onNextDay: () => next++,
              onOpenCalendar: () {},
              onOpenLearningCenter: () {},
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pump();

      expect(prev, 1);
      expect(next, 1);
    });

    testWidgets('shows overdue and unscheduled counters on the right', (
      tester,
    ) async {
      await pumpRail(
        tester,
        day: DateTime(2026, 9, 12),
        overdueCount: 3,
        unscheduledCount: 5,
      );
      await tester.pump();

      expect(find.text('3'), findsOneWidget);
      expect(find.text('overdue'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('unscheduled'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('caps the stack at 3 rows and hints at the hidden items', (
      tester,
    ) async {
      // 5 same-hour items → 5 gantt rows, but the rail renders only the
      // first 3 and collapses the other 2 into a "+N more" hint.
      await pumpRail(
        tester,
        day: DateTime(2026, 9, 12),
        items: [
          item('a', '2026-09-12T09:00:00'),
          item('b', '2026-09-12T09:01:00'),
          item('c', '2026-09-12T09:02:00'),
          item('d', '2026-09-12T09:03:00'),
          item('e', '2026-09-12T09:04:00'),
        ],
      );
      await tester.pump();

      expect(find.text('MCQ a'), findsOneWidget);
      expect(find.text('MCQ b'), findsOneWidget);
      expect(find.text('MCQ c'), findsOneWidget);
      expect(find.text('MCQ d'), findsNothing);
      expect(find.text('MCQ e'), findsNothing);
      expect(find.text('+2 more'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('wheel over the rail pans it; leaving releases the wheel', (
      tester,
    ) async {
      await pumpRail(tester, day: DateTime(2026, 9, 12));
      await tester.pump();

      final position =
          tester.state<ScrollableState>(find.byType(Scrollable)).position;

      // Physical mouse enters the timeline → the rail owns the wheel.
      final center = tester.getCenter(find.byType(SingleChildScrollView));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: center);
      await mouse.moveTo(center);
      await tester.pump();

      final before = position.pixels;
      await tester.sendEventToBinding(
        PointerScrollEvent(position: center, scrollDelta: const Offset(0, 120)),
      );
      await tester.pump();

      // Hovered → the wheel pans the rail, not the page around it.
      expect(position.pixels, greaterThan(before));

      // The mouse physically leaves the rail → the wheel is handed back and
      // the rail no longer moves on scroll events.
      await mouse.moveTo(const Offset(-20, -20));
      await tester.pump();

      final afterLeave = position.pixels;
      await tester.sendEventToBinding(
        PointerScrollEvent(position: center, scrollDelta: const Offset(0, 120)),
      );
      await tester.pump();

      expect(position.pixels, afterLeave);
    });
  });
}
