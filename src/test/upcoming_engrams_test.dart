import 'package:cerebrum/models/engram_models.dart';
import 'package:cerebrum/ui/screens/home/upcoming_engrams.dart';
import 'package:flutter_test/flutter_test.dart';

/// Minimal engram JSON. `scheduledAt` uses a LOCAL-naive ISO string (no `Z`)
/// so `Engram.fromJson`'s toLocal() is a no-op — grouping assertions stay
/// deterministic on any machine timezone.
Map<String, dynamic> engramJson({
  required String id,
  String type = 'flashcard',
  String? scheduledAt,
  String? state,
}) => {
  'id': id,
  'note_id': 'n1',
  'type': type,
  'target_cognitive_level': 2,
  'tags': const ['review'],
  'content': {
    'finding_index': 0,
    'card_number': 1,
    'front': 'front',
    'back': 'back',
    'severity': 'low',
  },
  if (scheduledAt != null) 'scheduled_at': scheduledAt,
  if (state != null) 'state': state,
};

Engram engram({
  required String id,
  String type = 'flashcard',
  String? scheduledAt,
  String? state,
}) => Engram.fromJson(
  engramJson(id: id, type: type, scheduledAt: scheduledAt, state: state),
);

void main() {
  group('Engram schedule parsing', () {
    test('absent scheduled_at and state stay null (no invented schedule)', () {
      final e = engram(id: 'e1');
      expect(e.scheduledAt, isNull);
      expect(e.state, isNull);
      expect(e.type, EngramType.flashcard);
    });

    test('present scheduled_at is parsed', () {
      final e = engram(
        id: 'e2',
        scheduledAt: '2026-09-10T09:00:00',
        state: 'due',
      );
      expect(e.scheduledAt, DateTime(2026, 9, 10, 9));
      expect(e.state, 'due');
    });

    test('list response parses the full array', () {
      final response = EngramListResponse.fromJson({
        'count': 1,
        'engrams': [engramJson(id: 'e3', scheduledAt: '2026-09-10T09:00:00')],
      });
      expect(response.engrams, hasLength(1));
      expect(response.engrams.single.scheduledAt, DateTime(2026, 9, 10, 9));
    });
  });

  group('buildDaysFromEngrams', () {
    test('groups by real due date, oldest day first, real hour chips', () {
      final days = buildDaysFromEngrams(
        [
          engram(id: 'late', scheduledAt: '2026-09-11T14:30:00'),
          engram(id: 'early', scheduledAt: '2026-09-10T09:00:00'),
        ],
        now: DateTime(2026, 9, 10, 8), // early is not overdue yet
      );

      expect(days, hasLength(2));
      expect(days[0].date, DateTime(2026, 9, 10));
      expect(days[0].items.single.time, '9 am');
      expect(days[1].date, DateTime(2026, 9, 11));
      expect(days[1].items.single.time, '2 pm');
    });

    test('same-day engrams share a bucket', () {
      final days = buildDaysFromEngrams([
        engram(id: 'a', scheduledAt: '2026-09-10T09:00:00'),
        engram(id: 'b', scheduledAt: '2026-09-10T14:00:00'),
      ], now: DateTime(2026, 9, 9));

      expect(days, hasLength(1));
      expect(days.single.items, hasLength(2));
    });

    test('unscheduled engrams land in the Upcoming bucket with no time', () {
      final days = buildDaysFromEngrams([
        engram(id: 'unsched'),
      ], now: DateTime(2026, 9, 9));

      expect(days, hasLength(1));
      expect(days.single.isScheduled, isFalse);
      expect(days.single.date, isNull); // no fake date
      expect(days.single.items.single.time, isNull); // no fake time
    });

    test('overdue engrams are marked Overdue, never a fake hour', () {
      final days = buildDaysFromEngrams([
        engram(id: 'over', scheduledAt: '2026-09-10T09:00:00'),
      ], now: DateTime(2026, 9, 10, 12));

      expect(days.single.items.single.time, 'Overdue');
    });

    test('hour formatting: noon and midnight are 12, not 0', () {
      final noon = buildDaysFromEngrams([
        engram(id: 'n', scheduledAt: '2026-09-10T12:00:00'),
      ], now: DateTime(2026, 9, 9));
      final midnight = buildDaysFromEngrams([
        engram(id: 'm', scheduledAt: '2026-09-10T00:00:00'),
      ], now: DateTime(2026, 9, 9));

      expect(noon.single.items.single.time, '12 pm');
      expect(midnight.single.items.single.time, '12 am');
    });
  });
}
