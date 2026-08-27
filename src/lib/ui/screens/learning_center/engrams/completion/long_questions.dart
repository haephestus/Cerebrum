import 'package:flutter/material.dart';
import 'package:cerebrum/models/engram_models.dart';
import 'package:cerebrum/services/engram_attempt_store.dart';
import 'package:cerebrum/services/engram_sync_service.dart';

class LongQuestionCompletionPage extends StatefulWidget {
  final Engram engram;
  final String userId;

  const LongQuestionCompletionPage({
    super.key,
    required this.engram,
    required this.userId,
  });

  @override
  State<LongQuestionCompletionPage> createState() =>
      _LongQuestionCompletionPageState();
}

class _LongQuestionCompletionPageState
    extends State<LongQuestionCompletionPage> {
  final _controller = TextEditingController();
  bool _submitting = false;
  bool _loading = true;

  /// The latest attempt for this engram (offline queue + graded result live
  /// here). Null → the user hasn't answered yet, show the form.
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
    // Opening the engram = the user has seen any grade → clear the badge.
    if (a != null && a.isGraded && !a.seen) {
      await EngramSyncService.markSeen(a.attemptId);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_controller.text.trim().isEmpty) return;
    setState(() => _submitting = true);
    try {
      // Queue-first: always saved locally, sent now if online, else on reconnect.
      final attempt = await EngramSyncService.submit(
        engramId: widget.engram.id,
        type: 'long_question',
        userId: widget.userId,
        payload: {'raw_answer': _controller.text},
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
    _controller.clear();
    setState(() => _attempt = null);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.engram.content as LongQuestionContent;

    return Scaffold(
      appBar: AppBar(title: const Text('Long Question')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            c.questionStem,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          ...c.parts.map(
            (p) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('(${p.part}) ${p.question}  [${p.marks} marks]'),
            ),
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Center(child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ))
          else if (_attempt == null)
            _buildForm()
          else if (_attempt!.isGraded)
            _GradedCard(attempt: _attempt!, onAnswerAgain: _answerAgain)
          else
            _PendingCard(attempt: _attempt!, onAnswerAgain: _answerAgain),
          // Reveal-after-answer: model answer / mark scheme for self-comparison
          // (only present when engrams were fetched with answers).
          if (!_loading && _attempt != null) _buildModelAnswer(c),
        ],
      ),
    );
  }

  Widget _buildModelAnswer(LongQuestionContent c) {
    final hasScheme = c.parts.any((p) => (p.markScheme ?? '').isNotEmpty);
    if ((c.answer ?? '').isEmpty && !hasScheme) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Card(
        color: Colors.grey.shade100,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Model answer',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              if ((c.answer ?? '').isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(c.answer!),
              ],
              ...c.parts.where((p) => (p.markScheme ?? '').isNotEmpty).map(
                    (p) => Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('(${p.part}) ${p.markScheme}'),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _controller,
          maxLines: 8,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'Write your full answer here...',
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Submit for grading'),
        ),
      ],
    );
  }
}

/// Shown while an answer is queued offline or grading server-side.
class _PendingCard extends StatelessWidget {
  const _PendingCard({required this.attempt, required this.onAnswerAgain});
  final EngramAttempt attempt;
  final VoidCallback onAnswerAgain;

  @override
  Widget build(BuildContext context) {
    final queued = attempt.isQueued;
    return Card(
      color: Colors.amber.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(queued ? Icons.cloud_off : Icons.hourglass_top,
                    size: 20, color: Colors.amber.shade800),
                const SizedBox(width: 8),
                Text(
                  queued ? 'Saved — will submit when online' : 'Grading in progress',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              queued
                  ? "Your answer is stored on this device and will be sent for "
                      "grading automatically once you're back online."
                  : "Your answer was submitted. The result will appear here when "
                      "grading finishes.",
            ),
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

/// Shown once the LLM grade is back.
class _GradedCard extends StatelessWidget {
  const _GradedCard({required this.attempt, required this.onAnswerAgain});
  final EngramAttempt attempt;
  final VoidCallback onAnswerAgain;

  @override
  Widget build(BuildContext context) {
    final result = attempt.result ?? const {};
    // Result schema is daemon-defined; render the common fields if present,
    // otherwise fall back to a readable dump so nothing is lost.
    final score = result['score'] ?? result['marks'] ?? result['grade'];
    final feedback = result['feedback'] ?? result['comment'] ?? result['rationale'];

    return Card(
      color: Colors.green.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green.shade700, size: 20),
                const SizedBox(width: 8),
                const Text('Graded', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            if (score != null)
              Text('Score: $score', style: const TextStyle(fontSize: 16)),
            if (feedback != null) ...[
              const SizedBox(height: 8),
              Text('$feedback'),
            ],
            if (score == null && feedback == null)
              Text(result.isEmpty ? 'No detail returned.' : result.toString()),
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
