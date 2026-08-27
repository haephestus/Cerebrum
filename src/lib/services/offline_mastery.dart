import 'package:drift/drift.dart' show Value;

import 'package:cerebrum/services/db/app_database.dart';

/// Per-engram SRS/mastery state, computed and stored **on-device** so flashcards
/// and MCQs give immediate feedback and schedule reviews with no server —
/// Anki-style, works fully offline.
///
/// IMPORTANT — the daemon owns mastery. The Cerebrum daemon has its own
/// (non-SM-2) scheduler with recent-score history, cognitive-level promotion, and
/// engram generation. This local state is a **provisional estimate** for offline
/// continuity only; whenever a submit reaches the daemon and returns a
/// `mastery_state`, adopt it via [adoptServerState] — the server wins. State
/// values mirror the daemon's `MasteryState` (new/learning/review/mastered/
/// lapsed) so the two never speak different vocabularies.
///
/// CROSS-REPO CONTRACT ⇄ daemon `MasteryState` (types.py) + `_update_mastery`.
/// Breaks if: (a) the state strings diverge from the daemon enum (UI shows
/// foreign states after adoptServerState); (b) anything treats this local
/// schedule/state as authoritative — the server always wins on sync.
class MasteryRecord {
  MasteryRecord({
    required this.engramId,
    this.easeFactor = 2.5,
    this.intervalDays = 0,
    this.repetitions = 0,
    this.lapses = 0,
    this.dueAt,
    this.lastGrade,
    this.masteryState = 'new', // matches daemon MasteryState.NEW
    required this.updatedAt,
  });

  final String engramId;
  double easeFactor;
  int intervalDays;
  int repetitions;
  int lapses;
  DateTime? dueAt;
  String? lastGrade;
  String masteryState; // learning | reviewing | mastered
  DateTime updatedAt;

  bool get isDue => dueAt == null || !dueAt!.isAfter(DateTime.now());

  Map<String, dynamic> toJson() => {
    'engram_id': engramId,
    'ease_factor': easeFactor,
    'interval_days': intervalDays,
    'repetitions': repetitions,
    'lapses': lapses,
    'due_at': dueAt?.toIso8601String(),
    'last_grade': lastGrade,
    'mastery_state': masteryState,
    'updated_at': updatedAt.toIso8601String(),
  };

  /// A UI-friendly result payload (mirrors the shape a server grade would take),
  /// tagged `source: offline` so callers can tell it apart.
  Map<String, dynamic> toResult({bool? correct}) => {
    if (correct != null) 'is_correct': correct,
    'mastery_state': masteryState,
    'interval_days': intervalDays,
    'due_at': dueAt?.toIso8601String(),
    'ease_factor': double.parse(easeFactor.toStringAsFixed(2)),
    'repetitions': repetitions,
    'source': 'offline',
  };

  factory MasteryRecord.fromJson(Map<String, dynamic> j) => MasteryRecord(
    engramId: j['engram_id'] as String,
    easeFactor: (j['ease_factor'] as num?)?.toDouble() ?? 2.5,
    intervalDays: (j['interval_days'] as num?)?.toInt() ?? 0,
    repetitions: (j['repetitions'] as num?)?.toInt() ?? 0,
    lapses: (j['lapses'] as num?)?.toInt() ?? 0,
    dueAt: j['due_at'] == null ? null : DateTime.tryParse(j['due_at'] as String),
    lastGrade: j['last_grade'] as String?,
    masteryState: (j['mastery_state'] as String?) ?? 'learning',
    updatedAt:
        DateTime.tryParse((j['updated_at'] as String?) ?? '') ?? DateTime.now(),
  );
}

class OfflineMastery {
  OfflineMastery._();

  /// Flashcard self-rating → SM-2 quality (0..5). `again` is a lapse.
  static int _qualityForRating(String rating) {
    switch (rating) {
      case 'again':
        return 1;
      case 'hard':
        return 3;
      case 'good':
        return 4;
      case 'easy':
        return 5;
      default:
        return 3;
    }
  }

  /// Grade a flashcard self-rating locally. Returns the updated record.
  static Future<MasteryRecord> applyFlashcard(
    String engramId,
    String rating,
  ) async {
    final rec = await masteryFor(engramId) ?? _fresh(engramId);
    _applySm2(rec, _qualityForRating(rating), rating);
    await _write(rec);
    return rec;
  }

  /// Grade an MCQ locally (needs the correct answer client-side — see
  /// `McqContent.correctOption`). Correct ≈ "good", incorrect ≈ "again".
  static Future<MasteryRecord> applyMcq(String engramId, bool correct) async {
    final rec = await masteryFor(engramId) ?? _fresh(engramId);
    _applySm2(rec, correct ? 4 : 1, correct ? 'correct' : 'incorrect');
    await _write(rec);
    return rec;
  }

  static MasteryRecord _fresh(String engramId) =>
      MasteryRecord(engramId: engramId, updatedAt: DateTime.now());

  /// Core SM-2 update (mutates [rec]). Provisional only — the daemon's scheduler
  /// is authoritative; [adoptServerState] overwrites [masteryState] on sync.
  static void _applySm2(MasteryRecord rec, int quality, String grade) {
    final lapsed = quality < 3;
    if (lapsed) {
      // Lapse: relearn from the start, review again tomorrow.
      rec.repetitions = 0;
      rec.intervalDays = 1;
      rec.lapses += 1;
    } else {
      if (rec.repetitions == 0) {
        rec.intervalDays = 1;
      } else if (rec.repetitions == 1) {
        rec.intervalDays = 6;
      } else {
        rec.intervalDays = (rec.intervalDays * rec.easeFactor).round();
      }
      rec.repetitions += 1;
    }

    // Ease factor update, floored at 1.3 (SM-2).
    rec.easeFactor = (rec.easeFactor +
            (0.1 - (5 - quality) * (0.08 + (5 - quality) * 0.02)))
        .clamp(1.3, 3.0);

    rec.dueAt = DateTime.now().add(Duration(days: rec.intervalDays));
    rec.lastGrade = grade;
    // Vocabulary mirrors daemon MasteryState.
    if (lapsed) {
      rec.masteryState = 'lapsed';
    } else if (rec.intervalDays >= 21) {
      rec.masteryState = 'mastered';
    } else if (rec.repetitions <= 1) {
      rec.masteryState = 'learning';
    } else {
      rec.masteryState = 'review';
    }
    rec.updatedAt = DateTime.now();
  }

  /// Adopt the daemon's authoritative `mastery_state` for an engram (call when a
  /// submit response / grading job reports one). The server wins over the local
  /// provisional estimate.
  static Future<void> adoptServerState(
    String engramId,
    String serverState,
  ) async {
    final rec = await masteryFor(engramId) ?? _fresh(engramId);
    rec.masteryState = serverState;
    rec.updatedAt = DateTime.now();
    await _write(rec);
  }

  // -- store (Drift; see docs/drift-migration.md) ------------------------

  static AppDatabase get _db => AppDatabase.instance;

  static Future<MasteryRecord?> masteryFor(String engramId) async {
    final r = await _db.mastery(engramId);
    if (r == null) return null;
    return MasteryRecord(
      engramId: r.engramId,
      easeFactor: r.easeFactor,
      intervalDays: r.intervalDays,
      repetitions: r.repetitions,
      lapses: r.lapses,
      dueAt: r.dueAt,
      lastGrade: r.lastGrade,
      masteryState: r.masteryState,
      updatedAt: r.updatedAt,
    );
  }

  static Future<void> _write(MasteryRecord rec) async {
    await _db.upsertMastery(
      EngramMasteryRowsCompanion.insert(
        engramId: rec.engramId,
        easeFactor: Value(rec.easeFactor),
        intervalDays: Value(rec.intervalDays),
        repetitions: Value(rec.repetitions),
        lapses: Value(rec.lapses),
        dueAt: Value(rec.dueAt),
        lastGrade: Value(rec.lastGrade),
        masteryState: Value(rec.masteryState),
        updatedAt: rec.updatedAt,
      ),
    );
  }
}
