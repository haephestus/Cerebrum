import 'package:cerebrum/ui/themes/theme_access.dart';
import 'package:flutter/material.dart';
import 'package:cerebrum/services/engram_attempt_store.dart';

/// Shown on the long-question completion page while an answer is queued
/// offline or grading server-side.
class LongQuestionPendingCard extends StatelessWidget {
  const LongQuestionPendingCard({
    super.key,
    required this.attempt,
    required this.onAnswerAgain,
  });

  final EngramAttempt attempt;
  final VoidCallback onAnswerAgain;

  @override
  Widget build(BuildContext context) {
    final queued = attempt.isQueued;
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
                  queued ? Icons.cloud_off : Icons.hourglass_top,
                  size: 20,
                  color: context.cerebrum.status.warningStrong,
                ),
                const SizedBox(width: 8),
                Text(
                  queued
                      ? 'Saved — will submit when online'
                      : 'Grading in progress',
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

/// Shown on the long-question completion page once the LLM grade is back.
class LongQuestionGradedCard extends StatelessWidget {
  const LongQuestionGradedCard({
    super.key,
    required this.attempt,
    required this.onAnswerAgain,
  });

  final EngramAttempt attempt;
  final VoidCallback onAnswerAgain;

  @override
  Widget build(BuildContext context) {
    final result = attempt.result ?? const {};
    // Result schema is daemon-defined; render the common fields if present,
    // otherwise fall back to a readable dump so nothing is lost.
    final score = result['score'] ?? result['marks'] ?? result['grade'];
    final feedback =
        result['feedback'] ?? result['comment'] ?? result['rationale'];

    return Card(
      color: context.cerebrum.status.successSurface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.check_circle,
                  color: context.cerebrum.status.success,
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Graded',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
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
