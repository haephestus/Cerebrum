import 'dart:convert';

import 'package:drift/drift.dart' show Value;

import 'package:cerebrum/services/db/app_database.dart';

/// One offline-capable engram answer attempt (offline-first, extended to the
/// learning center).
///
/// Lifecycle: `queued` (saved locally, not yet sent) → `submitted` (accepted by
/// the daemon, an LLM grading `job_id` is pending) → `graded` (the result is
/// back). MCQ/flashcard skip straight to `graded` because the daemon scores them
/// synchronously (no `job_id`). `failed` is a terminal error we surface.
class EngramAttempt {
  EngramAttempt({
    required this.attemptId,
    required this.engramId,
    required this.type,
    required this.userId,
    required this.payload,
    required this.targetCognitiveLevel,
    this.status = 'queued',
    this.jobId,
    this.result,
    this.error,
    this.seen = false,
    required this.createdAt,
    required this.updatedAt,
  });

  final String attemptId;
  final String engramId;

  /// One of `mcq | flashcard | short_question | long_question` — matches the
  /// submit endpoint path segment.
  final String type;
  final String userId;

  /// The type-specific submit body (e.g. `{raw_answer: ...}` for long,
  /// `{responses: [...]}` for short).
  final Map<String, dynamic> payload;
  final int targetCognitiveLevel;

  String status;
  String? jobId;
  Map<String, dynamic>? result;
  String? error;

  /// False once a grade lands until the user opens the engram — drives the
  /// "new result" badge.
  bool seen;

  final String createdAt;
  String updatedAt;

  bool get isQueued => status == 'queued';
  bool get isSubmitted => status == 'submitted';
  bool get isGraded => status == 'graded';
  bool get isPending => isQueued || isSubmitted;

  Map<String, dynamic> toJson() => {
    'attempt_id': attemptId,
    'engram_id': engramId,
    'type': type,
    'user_id': userId,
    'payload': payload,
    'target_cognitive_level': targetCognitiveLevel,
    'status': status,
    'job_id': jobId,
    'result': result,
    'error': error,
    'seen': seen,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };

  factory EngramAttempt.fromJson(Map<String, dynamic> j) => EngramAttempt(
    attemptId: j['attempt_id'] as String,
    engramId: j['engram_id'] as String,
    type: j['type'] as String,
    userId: j['user_id'] as String,
    payload: Map<String, dynamic>.from((j['payload'] as Map?) ?? const {}),
    targetCognitiveLevel: (j['target_cognitive_level'] as num?)?.toInt() ?? 1,
    status: (j['status'] as String?) ?? 'queued',
    jobId: j['job_id'] as String?,
    result:
        j['result'] == null
            ? null
            : Map<String, dynamic>.from(j['result'] as Map),
    error: j['error'] as String?,
    seen: j['seen'] as bool? ?? false,
    createdAt: (j['created_at'] as String?) ?? '',
    updatedAt: (j['updated_at'] as String?) ?? '',
  );
}

/// Store for engram attempts — the learning-center analogue of `NoteStore`,
/// backed by the Drift/SQLite [AppDatabase] (indexed queries instead of
/// file-scans; ready for reactive `watch*` streams). Attempts are the queue
/// *and* the durable record: the sync service reads pending attempts to drive
/// them forward, and the completion screens read the latest attempt per engram
/// to show a grade on reopen.
///
/// Public API is unchanged from the earlier JSON version, so callers
/// ([EngramSyncService], the completion screens) didn't change.
class EngramAttemptStore {
  static AppDatabase get _db => AppDatabase.instance;

  static EngramAttempt _fromRow(EngramAttemptRow r) => EngramAttempt(
    attemptId: r.attemptId,
    engramId: r.engramId,
    type: r.type,
    userId: r.userId,
    payload: Map<String, dynamic>.from(jsonDecode(r.payloadJson) as Map),
    targetCognitiveLevel: r.targetCognitiveLevel,
    status: r.status,
    jobId: r.jobId,
    result: r.resultJson == null
        ? null
        : Map<String, dynamic>.from(jsonDecode(r.resultJson!) as Map),
    error: r.error,
    seen: r.seen,
    createdAt: r.createdAt.toUtc().toIso8601String(),
    updatedAt: r.updatedAt.toUtc().toIso8601String(),
  );

  static DateTime _parse(String iso) =>
      DateTime.tryParse(iso)?.toUtc() ?? DateTime.now().toUtc();

  // -- writes ------------------------------------------------------------

  static Future<void> write(EngramAttempt attempt) async {
    attempt.updatedAt = DateTime.now().toUtc().toIso8601String();
    await _db.upsertAttempt(
      EngramAttemptsCompanion.insert(
        attemptId: attempt.attemptId,
        engramId: attempt.engramId,
        type: attempt.type,
        userId: attempt.userId,
        payloadJson: jsonEncode(attempt.payload),
        targetCognitiveLevel: Value(attempt.targetCognitiveLevel),
        status: Value(attempt.status),
        jobId: Value(attempt.jobId),
        resultJson:
            Value(attempt.result == null ? null : jsonEncode(attempt.result)),
        error: Value(attempt.error),
        seen: Value(attempt.seen),
        createdAt: _parse(attempt.createdAt),
        updatedAt: _parse(attempt.updatedAt),
      ),
    );
  }

  static Future<EngramAttempt?> read(String attemptId) async {
    final row = await _db.attempt(attemptId);
    return row == null ? null : _fromRow(row);
  }

  /// Apply a change to a stored attempt and persist it. Returns the updated
  /// record (or null if it's gone).
  static Future<EngramAttempt?> update(
    String attemptId,
    void Function(EngramAttempt) mutate,
  ) async {
    final attempt = await read(attemptId);
    if (attempt == null) return null;
    mutate(attempt);
    await write(attempt);
    return attempt;
  }

  // -- queries -----------------------------------------------------------

  /// Attempts still needing work, oldest first (submit the queue in order so
  /// per-engram SRS state evolves correctly).
  static Future<List<EngramAttempt>> pending() async =>
      (await _db.pendingAttempts()).map(_fromRow).toList();

  /// The most recent attempt for an engram — what a completion screen shows on
  /// reopen (pending banner or graded result).
  static Future<EngramAttempt?> latestForEngram(String engramId) async {
    final row = await _db.latestAttemptForEngram(engramId);
    return row == null ? null : _fromRow(row);
  }

  /// Count of graded-but-unseen results — the notification/badge number.
  static Future<int> unseenGradedCount() => _db.unseenGradedCount();

  /// Mark an attempt's result as seen (call when its engram is opened) so the
  /// badge clears.
  static Future<void> markSeen(String attemptId) async {
    await update(attemptId, (a) => a.seen = true);
  }
}
