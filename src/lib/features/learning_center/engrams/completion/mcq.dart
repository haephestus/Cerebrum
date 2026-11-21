import 'package:cerebrum/features/learning_center/api/learning_center_api.dart';
import 'package:cerebrum/models/engram_models.dart';
import 'package:cerebrum/services/engram_store.dart';
import 'package:cerebrum/services/engram_attempt_store.dart';
import 'package:cerebrum/services/engram_sync_service.dart';
import 'package:cerebrum/services/offline_mastery.dart';
import 'package:cerebrum/common/themes/theme_access.dart';
import 'package:cerebrum/common/widgets/floating_modal.dart';
import 'package:flutter/material.dart';

class McqCompletionPage extends StatefulWidget {
  final Engram engram;
  final String userId;

  const McqCompletionPage({
    super.key,
    required this.engram,
    required this.userId,
  });

  @override
  State<McqCompletionPage> createState() => _McqCompletionPageState();
}

class _McqCompletionPageState extends State<McqCompletionPage> {
  String? _selected;
  bool _submitting = false;
  bool _loading = true;
  bool _voiding = false;

  /// The result to show — local (SM-2, offline-first) if we know the correct
  /// answer, else the server's result once it's back.
  Map<String, dynamic>? _result;

  /// Queued server attempt — drives the sync indicator.
  EngramAttempt? _attempt;

  McqContent get _content => widget.engram.content as McqContent;

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  /// True when the latest attempt belongs to a *previous* review cycle,
  /// not the one the daemon is now asking for. Compares the attempt's
  /// creation time against the daemon `scheduled_at` when present
  /// (authoritative), falling back to the local SM-2 `due_at`.
  /// Without this check, `_loadExisting` rehydrates the prior grade
  /// and locks the question (prefilled option + Done only) even when
  /// it is due again — making resubmission impossible forever.
  bool _isStaleCycle(EngramAttempt? attempt, MasteryRecord? mastery) {
    if (attempt == null) return false;
    final scheduled = widget.engram.scheduledAt;
    if (scheduled != null) {
      final t = DateTime.tryParse(attempt.createdAt);
      if (t != null && t.isBefore(scheduled)) return true;
    }
    if (mastery?.dueAt != null && mastery?.lastGrade != null) {
      if (!mastery!.dueAt!.isAfter(DateTime.now())) return true;
    }
    return false;
  }

  void _answerAgain() {
    setState(() {
      _selected = null;
      _result = null;
      _attempt = null;
    });
  }

  Future<void> _loadExisting() async {
    final mastery = await OfflineMastery.masteryFor(widget.engram.id);
    final attempt = await EngramAttemptStore.latestForEngram(widget.engram.id);
    if (!mounted) return;

    // Ignore a previous cycle's attempt / result so the question comes up
    // blank (and submittable) when suggested again.
    final stale = _isStaleCycle(attempt, mastery);
    final effectiveAttempt = stale ? null : attempt;
    final effectiveMastery = stale ? null : mastery;

    Map<String, dynamic>? result;
    if (effectiveMastery != null && effectiveMastery.lastGrade != null) {
      result = effectiveMastery.toResult(
        correct: effectiveMastery.lastGrade == 'correct',
      );
    } else if (effectiveAttempt != null && effectiveAttempt.isGraded) {
      result = effectiveAttempt.result;
    }

    setState(() {
      _attempt = effectiveAttempt;
      _selected =
          stale ? null : (attempt?.payload['selected_option'] as String?);
      _result = result;
      _loading = false;
    });
    if (attempt != null && attempt.isGraded && !attempt.seen) {
      await EngramSyncService.markSeen(attempt.attemptId);
    }
  }

  Future<void> _submit() async {
    if (_selected == null) return;
    setState(() => _submitting = true);
    try {
      // Offline-first: if the daemon told us the correct option, grade locally
      // for immediate feedback (works with no connection).
      final correctOption = _content.correctOption;
      Map<String, dynamic>? localResult;
      if (correctOption != null) {
        final correct = _selected == correctOption;
        final mastery = await OfflineMastery.applyMcq(
          widget.engram.id,
          correct,
        );
        localResult = mastery.toResult(correct: correct);
      }

      // Always queue for the daemon (record + authoritative scoring/scheduling).
      final attempt = await EngramSyncService.submit(
        engramId: widget.engram.id,
        type: 'mcq',
        userId: widget.userId,
        payload: {'selected_option': _selected!},
        targetCognitiveLevel: widget.engram.targetCognitiveLevel,
      );
      if (!mounted) return;
      setState(() {
        _attempt = attempt;
        // Prefer the local grade for instant feedback; else use the server's
        // (present when online + no local correct answer available).
        _result = localResult ?? (attempt.isGraded ? attempt.result : null);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Submit failed: $e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Wrong-key recovery. The daemon voids this engram's attempts and queues a
  /// replacement; no score is recomputed. Local cache/attempt/mastery are
  /// dropped so the retired key cannot reappear offline. Pop with `true` so
  /// the learning-centre list refetches.
  Future<void> _voidAndRegenerate() async {
    if (_voiding) return;
    setState(() => _voiding = true);
    try {
      final result = await LearningCenterApi.voidAndRegenerateMcq(
        engramId: widget.engram.id,
        userId: widget.userId,
      );
      await EngramStore.removeCached(
        userId: widget.userId,
        engramId: widget.engram.id,
      );
      await EngramAttemptStore.deleteForEngram(widget.engram.id);
      await OfflineMastery.reset(widget.engram.id);
      if (!mounted) return;
      final voided = (result['voided_attempt_ids'] as List?)?.length ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Key voided — replacement queued. $voided attempt(s) voided.',
          ),
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Void & regenerate failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _voiding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _content;
    final locked = _attempt != null || _result != null;

    return FloatingModal(
      title: 'Multiple Choice',
      child:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : LayoutBuilder(
                builder: (context, constraints) {
                  final isNarrow = constraints.maxWidth < 480;
                  final pad = isNarrow ? 12.0 : 20.0;
                  final stemSize = isNarrow ? 16.0 : 18.0;
                  return SingleChildScrollView(
                    padding: EdgeInsets.all(pad),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.stem,
                          style: TextStyle(
                            fontSize: stemSize,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 20),
                        ...c.options.entries.map((opt) {
                          final isSelected = _selected == opt.key;
                          // Reveal-after-answer: once locked, colour the correct option
                          // green and a wrong pick red (needs correct_option, which
                          // only arrives in the answers-included fetch).
                          final correctOpt = c.correctOption;
                          Color? tileColor;
                          Widget? trailing;
                          if (locked && correctOpt != null) {
                            if (opt.key == correctOpt) {
                              tileColor =
                                  context.cerebrum.status.successSurface;
                              trailing = Icon(
                                Icons.check,
                                color: context.cerebrum.status.success,
                              );
                            } else if (isSelected) {
                              tileColor = context.cerebrum.status.dangerSurface;
                              trailing = Icon(
                                Icons.close,
                                color: context.cerebrum.status.dangerDeep,
                              );
                            }
                          } else if (isSelected) {
                            tileColor = context.cerebrum.status.infoSurface;
                          }
                          return Card(
                            color: tileColor,
                            child: ListTile(
                              leading: CircleAvatar(child: Text(opt.key)),
                              title: Text(opt.value),
                              selected: isSelected,
                              trailing: trailing,
                              onTap:
                                  locked
                                      ? null
                                      : () =>
                                          setState(() => _selected = opt.key),
                            ),
                          );
                        }),
                        const SizedBox(height: 20),
                        if (_attempt == null && _result == null)
                          SizedBox(
                            width: isNarrow ? double.infinity : null,
                            child: ElevatedButton(
                              style:
                                  isNarrow
                                      ? ElevatedButton.styleFrom(
                                        minimumSize: const Size.fromHeight(48),
                                      )
                                      : null,
                              onPressed:
                                  _selected == null || _submitting
                                      ? null
                                      : _submit,
                              child:
                                  _submitting
                                      ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                      : const Text('Submit'),
                            ),
                          )
                        else if (_result != null)
                          _resultCard(_result!)
                        else
                          _pendingCard(),
                      ],
                    ),
                  );
                },
              ),
    );
  }

  Widget _resultCard(Map<String, dynamic> r) {
    final correct = r['is_correct'] == true;
    return Card(
      color:
          correct
              ? context.cerebrum.status.successSurface
              : context.cerebrum.status.dangerSurface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              correct ? 'Correct!' : 'Not quite.',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            if (r['mastery_state'] != null) ...[
              const SizedBox(height: 8),
              Text('Mastery: ${r['mastery_state']}'),
            ],
            if (r['interval_days'] != null)
              Text(
                'Next review in ${r['interval_days']} '
                '${r['interval_days'] == 1 ? 'day' : 'days'}',
              ),
            const SizedBox(height: 8),
            _syncStatus(),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                OutlinedButton(
                  onPressed: _answerAgain,
                  child: const Text('Answer again'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Done'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _voiding ? null : _voidAndRegenerate,
                icon:
                    _voiding
                        ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : const Icon(Icons.report_problem_outlined),
                label: Text(
                  _voiding
                      ? 'Voiding and queuing replacement…'
                      : 'Answer key is wrong — void & regenerate',
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Voids your attempts on this question and queues a fresh one. '
              'Scores are not changed.',
              style: TextStyle(
                fontSize: 12,
                color: context.cerebrum.text.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pendingCard() {
    return Card(
      color: context.cerebrum.status.warningSurface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.cloud_off,
                  size: 20,
                  color: context.cerebrum.status.warningStrong,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Saved — will submit when online',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Your answer is stored on this device and will be scored once '
              "you're back online.",
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                OutlinedButton(
                  onPressed: _answerAgain,
                  child: const Text('Answer again'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Done'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _syncStatus() {
    final a = _attempt;
    final synced = a != null && a.isGraded;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          synced ? Icons.check : Icons.cloud_off,
          size: 16,
          color:
              synced
                  ? context.cerebrum.status.success
                  : context.cerebrum.status.warningStrong,
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            synced ? 'Synced' : 'Saved — will sync when online',
            style: TextStyle(color: context.cerebrum.text.muted),
          ),
        ),
      ],
    );
  }
}
