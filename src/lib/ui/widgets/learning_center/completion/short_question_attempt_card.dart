import 'package:cerebrum/ui/themes/theme_access.dart';
import 'package:flutter/material.dart';
import 'package:cerebrum/services/engram_attempt_store.dart';

/// Compact pending/graded status for a submitted short-question attempt,
/// shown on the short-question completion page.
class ShortQuestionAttemptCard extends StatelessWidget {
  const ShortQuestionAttemptCard({
    super.key,
    required this.attempt,
    required this.onAnswerAgain,
  });

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
      color = context.cerebrum.status.success;
      title = 'Graded';
      body = '';
    } else if (queued) {
      icon = Icons.cloud_off;
      color = context.cerebrum.status.warning;
      title = 'Saved — will submit when online';
      body =
          "Your answers are stored on this device and will be sent for "
          "grading automatically once you're back online.";
    } else {
      icon = Icons.hourglass_top;
      color = context.cerebrum.status.warning;
      title = 'Grading in progress';
      body =
          'Your answers were submitted. Results will appear here when '
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
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            if (body.isNotEmpty) ...[const SizedBox(height: 8), Text(body)],
            if (graded) ...[
              const SizedBox(height: 8),
              if (score != null)
                Text('Score: $score', style: const TextStyle(fontSize: 16)),
              if (feedback != null) ...[
                const SizedBox(height: 8),
                Text('$feedback'),
              ],
              if (score == null && feedback == null)
                Text(
                  result.isEmpty ? 'No detail returned.' : result.toString(),
                ),
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
