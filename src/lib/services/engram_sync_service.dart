import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:cerebrum/api/learning_center_api.dart';
import 'package:cerebrum/services/engram_attempt_store.dart';
import 'package:cerebrum/services/id.dart';
import 'package:cerebrum/services/notifications.dart';
import 'package:cerebrum/services/offline_mastery.dart';

/// Offline-first engram answers — the learning-center analogue of `SyncService`,
/// kept as its own service because engram answers are a **two-phase** flow that
/// note sync isn't: submit the answer, then later fetch the LLM grade (`job_id`).
///
/// [EngramAttemptStore] is both the queue and the durable record. An attempt
/// walks `queued → submitted → graded`:
///  - **queued**: saved locally (offline-safe), not yet sent.
///  - **submitted**: the daemon accepted it; a grading `job_id` is pending
///    (short/long). MCQ/flashcard are graded synchronously, so they skip
///    straight to graded.
///  - **graded**: the result is back → we fire a notification + bump the badge;
///    the completion screen shows it on reopen.
///
/// Reconnect handling mirrors `SyncService`: [drain] runs on app start/resume,
/// and anything left pending starts a light auto-drain poll until it clears.
/// (This service owns its own poll so its two-phase logic stays out of the
/// note-sync code; app start/resume drives both.)
///
/// ══ CROSS-REPO CONTRACT (why it's shaped this way) ══════════════════════
/// The `queued → submitted → graded` walk is dictated by the daemon's response
/// shapes: mcq/flashcard grade synchronously (no `job_id` → straight to graded);
/// short/long return a `job_id` and are graded async (→ submitted, then polled
/// via [LearningCenterApi.fetchGradingJob]). So `_advance` KEYS ON the presence
/// of `job_id` — if the daemon changed mcq/flashcard to async (or short/long to
/// sync), this branch is wrong.
///
/// Identity is client-owned: [submit] mints the `attempt_id` with `nanoid()`
/// (daemon `uuid4().hex` shape) and passes the attempt's `createdAt` as
/// `attempted_at`. The daemon dedupes replays on that id (create_attempt =
/// INSERT OR IGNORE) — this is what makes the offline queue safe to retry.
///
/// Mastery is daemon-owned: on a graded response carrying `mastery_state`,
/// `_markGraded` calls [OfflineMastery.adoptServerState] so the server value
/// wins over the local provisional estimate. Don't invert that priority.
/// ════════════════════════════════════════════════════════════════════════
class EngramSyncService {
  EngramSyncService._();

  static const _retryInterval = Duration(seconds: 20);
  static Timer? _retryTimer;

  /// Queue an engram answer and try to send it immediately. Always persists
  /// locally first (offline-safe). Returns the freshest attempt state so the UI
  /// can render queued / submitted / graded right away.
  static Future<EngramAttempt> submit({
    required String engramId,
    required String type, // mcq | flashcard | short_question | long_question
    required String userId,
    required Map<String, dynamic> payload,
    int targetCognitiveLevel = 1,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final attempt = EngramAttempt(
      // nanoid (uuid4-hex shape) matches the daemon id space so the daemon
      // dedupes a replayed offline submit on this client-minted id.
      attemptId: nanoid(),
      engramId: engramId,
      type: type,
      userId: userId,
      payload: payload,
      targetCognitiveLevel: targetCognitiveLevel,
      createdAt: now,
      updatedAt: now,
    );
    await EngramAttemptStore.write(attempt);
    await _advance(attempt); // best-effort now
    await _ensureAutoDrain();
    return (await EngramAttemptStore.read(attempt.attemptId)) ?? attempt;
  }

  /// Push every pending attempt as far as it'll go (call on app start / resume /
  /// reconnect). Stops at the first network failure so we don't hammer an
  /// unreachable daemon; refreshes the badge and (dis)arms the poll at the end.
  static Future<void> drain() async {
    for (final attempt in await EngramAttemptStore.pending()) {
      final ok = await _advance(attempt);
      if (!ok) break; // offline — leave the rest queued
    }
    await _refreshBadge();

    if ((await EngramAttemptStore.pending()).isEmpty) {
      _retryTimer?.cancel();
      _retryTimer = null;
    }
  }

  /// Mark a graded result as seen (call when its engram screen opens) and clear
  /// it from the badge.
  static Future<void> markSeen(String attemptId) async {
    await EngramAttemptStore.markSeen(attemptId);
    await _refreshBadge();
  }

  /// Recompute the badge from the store — call once on app start so a grade that
  /// landed in a previous session still shows.
  static Future<void> refreshBadge() => _refreshBadge();

  // -- internals ---------------------------------------------------------

  /// Move one attempt forward one step. Returns false only on a network failure
  /// (so the caller stops draining); a not-yet-ready grade is NOT a failure.
  static Future<bool> _advance(EngramAttempt a) async {
    try {
      if (a.isQueued) {
        final resp = await _submitToApi(a);
        final jobId = resp['job_id'] as String?;
        if (jobId != null) {
          // Async grading (short/long) — wait for the result on a later pass.
          await EngramAttemptStore.update(a.attemptId, (x) {
            x.status = 'submitted';
            x.jobId = jobId;
            x.error = null;
          });
        } else {
          // Synchronous grading (mcq/flashcard) — the response IS the result.
          await _markGraded(a.attemptId, resp);
        }
        return true;
      }

      if (a.isSubmitted && a.jobId != null) {
        final job = await LearningCenterApi.fetchGradingJob(a.jobId!);
        if (job != null) {
          if (job['status'] == 'failed') {
            await EngramAttemptStore.update(a.attemptId, (x) {
              x.status = 'failed';
              x.error = job['error'] as String? ?? 'grading failed';
            });
          } else {
            await _markGraded(a.attemptId, job); // done → {score, grader, ...}
          }
        }
        // job == null → still grading; keep it submitted, not an error.
        return true;
      }

      return true;
    } catch (e) {
      debugPrint('[EngramSync] attempt ${a.attemptId} (${a.type}) deferred: $e');
      return false; // offline / hub down — retry on the next drain
    }
  }

  static Future<Map<String, dynamic>> _submitToApi(EngramAttempt a) {
    switch (a.type) {
      case 'mcq':
        return LearningCenterApi.submitMcq(
          engramId: a.engramId,
          userId: a.userId,
          selectedOption: a.payload['selected_option'] as String,
          targetCognitiveLevel: a.targetCognitiveLevel,
          attemptId: a.attemptId,
          attemptedAt: a.createdAt,
        );
      case 'flashcard':
        return LearningCenterApi.submitFlashcard(
          engramId: a.engramId,
          userId: a.userId,
          selfRating: a.payload['self_rating'] as String,
          targetCognitiveLevel: a.targetCognitiveLevel,
          attemptId: a.attemptId,
          attemptedAt: a.createdAt,
        );
      case 'short_question':
        return LearningCenterApi.submitShortQuestion(
          engramId: a.engramId,
          userId: a.userId,
          responses: List<Map<String, dynamic>>.from(
            (a.payload['responses'] as List).map(
              (e) => Map<String, dynamic>.from(e as Map),
            ),
          ),
          targetCognitiveLevel: a.targetCognitiveLevel,
          attemptId: a.attemptId,
          attemptedAt: a.createdAt,
        );
      case 'long_question':
        return LearningCenterApi.submitLongQuestion(
          engramId: a.engramId,
          userId: a.userId,
          rawAnswer: a.payload['raw_answer'] as String,
          targetCognitiveLevel: a.targetCognitiveLevel,
          attemptId: a.attemptId,
          attemptedAt: a.createdAt,
        );
      default:
        throw ArgumentError('Unknown engram type: ${a.type}');
    }
  }

  static Future<void> _markGraded(
    String attemptId,
    Map<String, dynamic> result,
  ) async {
    final a = await EngramAttemptStore.update(attemptId, (x) {
      x.status = 'graded';
      x.result = result;
      x.seen = false;
      x.error = null;
    });
    if (a != null) {
      // The daemon owns mastery — adopt its authoritative state when it sends one
      // (mcq/flashcard synchronous grades), overriding the local provisional.
      final serverState = result['mastery_state'] as String?;
      if (serverState != null) {
        await OfflineMastery.adoptServerState(a.engramId, serverState);
      }
      await Notifications.notify(
        title: 'Answer graded',
        body: 'Your ${_label(a.type)} answer has a result.',
        payload: 'engram:${a.engramId}',
      );
    }
  }

  static Future<void> _refreshBadge() =>
      Notifications.refreshBadge(EngramAttemptStore.unseenGradedCount);

  static Future<void> _ensureAutoDrain() async {
    if (_retryTimer != null) return;
    if ((await EngramAttemptStore.pending()).isEmpty) return;
    _retryTimer = Timer.periodic(_retryInterval, (_) => drain());
  }

  static String _label(String type) {
    switch (type) {
      case 'mcq':
        return 'multiple-choice';
      case 'flashcard':
        return 'flashcard';
      case 'short_question':
        return 'short-question';
      case 'long_question':
        return 'long-question';
      default:
        return 'question';
    }
  }
}
