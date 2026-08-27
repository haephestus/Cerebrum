import 'package:flutter/material.dart';
import 'package:cerebrum/models/engram_models.dart';
import 'package:cerebrum/services/engram_attempt_store.dart';
import 'package:cerebrum/services/engram_sync_service.dart';

class ShortQuestionCompletionPage extends StatefulWidget {
  final Engram engram;
  final String userId;

  const ShortQuestionCompletionPage({
    super.key,
    required this.engram,
    required this.userId,
  });

  @override
  State<ShortQuestionCompletionPage> createState() =>
      _ShortQuestionCompletionPageState();
}

class _ShortQuestionCompletionPageState
    extends State<ShortQuestionCompletionPage> {
  final Map<int, TextEditingController> _controllers = {};
  bool _submitting = false;
  bool _loading = true;

  /// Latest attempt for this engram (offline queue + graded result).
  EngramAttempt? _attempt;

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  Future<void> _loadExisting() async {
    final a = await EngramAttemptStore.latestForEngram(widget.engram.id);
    if (!mounted) return;
    setState(() {
      _attempt = a;
      _loading = false;
    });
    if (a != null && a.isGraded && !a.seen) {
      await EngramSyncService.markSeen(a.attemptId);
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(int questionNumber) {
    return _controllers.putIfAbsent(
      questionNumber,
      () => TextEditingController(),
    );
  }

  Future<void> _submit(List<ShortQuestionItem> questions) async {
    setState(() => _submitting = true);
    try {
      // Daemon contract: [{question_index: int, raw_answer: str}], where
      // question_index is matched against each question's `question_number`
      // (server drops answers with no matching number) — see the daemon's
      // ai_grading.questions_by_index.
      final responses = questions
          .map<Map<String, dynamic>>((q) => {
                'question_index': q.questionNumber,
                'raw_answer': _controllerFor(q.questionNumber).text,
              })
          .toList();

      // Queue-first: always saved locally, sent now if online, else on reconnect.
      final attempt = await EngramSyncService.submit(
        engramId: widget.engram.id,
        type: 'short_question',
        userId: widget.userId,
        payload: {'responses': responses},
        targetCognitiveLevel: widget.engram.targetCognitiveLevel,
      );
      if (!mounted) return;
      setState(() => _attempt = attempt);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Submit failed: $e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _answerAgain() {
    for (final c in _controllers.values) {
      c.clear();
    }
    setState(() => _attempt = null);
  }

  /// Reveal-after-answer: for each sub-question, the student's answer beside the
  /// model answer (present only when engrams were fetched with answers). Answers
  /// are read from the recorded attempt so it also works on reopen.
  List<Widget> _buildComparison(ShortQuestionContent c) {
    final responses = (_attempt?.payload['responses'] as List?) ?? const [];
    final answers = <int, String>{};
    for (final r in responses) {
      if (r is Map) {
        final idx = (r['question_index'] as num?)?.toInt();
        if (idx != null) answers[idx] = (r['raw_answer'] as String?) ?? '';
      }
    }
    return c.questions.map((q) {
      final yours = answers[q.questionNumber] ?? '';
      final expected = q.expectedAnswer;
      return Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(q.stem,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('Your answer',
                  style: TextStyle(fontSize: 12, color: Colors.black54)),
              Text(yours.isEmpty ? '—' : yours),
              if (expected != null && expected.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('Model answer',
                    style: TextStyle(fontSize: 12, color: Colors.black54)),
                Text(expected),
              ],
            ],
          ),
        ),
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.engram.content as ShortQuestionContent;

    return Scaffold(
      appBar: AppBar(title: const Text('Short Questions')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _attempt != null
              ? ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    _AttemptStatus(
                      attempt: _attempt!,
                      onAnswerAgain: _answerAgain,
                    ),
                    const SizedBox(height: 16),
                    ..._buildComparison(c),
                  ],
                )
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    ...c.questions.map((q) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              q.stem,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            if (q.hint != null && q.hint!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  'Hint: ${q.hint}',
                                  style: const TextStyle(
                                    fontStyle: FontStyle.italic,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _controllerFor(q.questionNumber),
                              maxLines: 3,
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                hintText: 'Your answer...',
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    ElevatedButton(
                      onPressed:
                          _submitting ? null : () => _submit(c.questions),
                      child: _submitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Submit All'),
                    ),
                  ],
                ),
    );
  }
}

/// Compact pending/graded status for a submitted short-question attempt.
class _AttemptStatus extends StatelessWidget {
  const _AttemptStatus({required this.attempt, required this.onAnswerAgain});
  final EngramAttempt attempt;
  final VoidCallback onAnswerAgain;

  @override
  Widget build(BuildContext context) {
    final graded = attempt.isGraded;
    final queued = attempt.isQueued;
    final result = attempt.result ?? const {};
    final score = result['score'] ?? result['marks'] ?? result['grade'];
    final feedback =
        result['feedback'] ?? result['comment'] ?? result['rationale'];

    final IconData icon;
    final Color color;
    final String title;
    final String body;
    if (graded) {
      icon = Icons.check_circle;
      color = Colors.green;
      title = 'Graded';
      body = '';
    } else if (queued) {
      icon = Icons.cloud_off;
      color = Colors.amber;
      title = 'Saved — will submit when online';
      body = "Your answers are stored on this device and will be sent for "
          "grading automatically once you're back online.";
    } else {
      icon = Icons.hourglass_top;
      color = Colors.amber;
      title = 'Grading in progress';
      body = 'Your answers were submitted. Results will appear here when '
          'grading finishes.';
    }

    return Card(
      color: color.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            if (body.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(body),
            ],
            if (graded) ...[
              const SizedBox(height: 8),
              if (score != null)
                Text('Score: $score', style: const TextStyle(fontSize: 16)),
              if (feedback != null) ...[
                const SizedBox(height: 8),
                Text('$feedback'),
              ],
              if (score == null && feedback == null)
                Text(result.isEmpty ? 'No detail returned.' : result.toString()),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton(
                  onPressed: onAnswerAgain,
                  child: const Text('Answer again'),
                ),
                const Spacer(),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
