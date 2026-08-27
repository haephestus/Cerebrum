import 'package:flutter/material.dart';
import 'package:cerebrum/models/engram_models.dart';
import 'package:cerebrum/services/engram_attempt_store.dart';
import 'package:cerebrum/services/engram_sync_service.dart';
import 'package:cerebrum/services/offline_mastery.dart';

class FlashcardCompletionPage extends StatefulWidget {
  final Engram engram;
  final String userId;

  const FlashcardCompletionPage({
    super.key,
    required this.engram,
    required this.userId,
  });

  @override
  State<FlashcardCompletionPage> createState() =>
      _FlashcardCompletionPageState();
}

class _FlashcardCompletionPageState extends State<FlashcardCompletionPage> {
  bool _flipped = false;
  bool _submitting = false;
  bool _loading = true;
  String? _ratedAs;

  /// Local SRS state — the source of immediate, offline feedback.
  MasteryRecord? _mastery;

  /// The queued server attempt — drives the "will sync / synced" indicator.
  EngramAttempt? _attempt;

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  Future<void> _loadExisting() async {
    final mastery = await OfflineMastery.masteryFor(widget.engram.id);
    final attempt = await EngramAttemptStore.latestForEngram(widget.engram.id);
    if (!mounted) return;
    setState(() {
      _mastery = mastery;
      _attempt = attempt;
      _ratedAs =
          attempt?.payload['self_rating'] as String? ?? mastery?.lastGrade;
      if (_ratedAs != null) _flipped = true;
      _loading = false;
    });
    if (attempt != null && attempt.isGraded && !attempt.seen) {
      await EngramSyncService.markSeen(attempt.attemptId);
    }
  }

  Future<void> _rate(String rating) async {
    setState(() => _submitting = true);
    try {
      // 1) Grade LOCALLY first — immediate, offline-first SRS feedback.
      final mastery =
          await OfflineMastery.applyFlashcard(widget.engram.id, rating);
      // 2) Queue the answer for the daemon (record + server-side scheduling).
      final attempt = await EngramSyncService.submit(
        engramId: widget.engram.id,
        type: 'flashcard',
        userId: widget.userId,
        payload: {'self_rating': rating},
        targetCognitiveLevel: widget.engram.targetCognitiveLevel,
      );
      if (!mounted) return;
      setState(() {
        _mastery = mastery;
        _attempt = attempt;
        _ratedAs = rating;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.engram.content as FlashcardContent;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Flashcard')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final rated = _ratedAs != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Flashcard')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            GestureDetector(
              onTap: rated ? null : () => setState(() => _flipped = !_flipped),
              child: Container(
                width: double.infinity,
                height: 220,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _flipped ? Colors.indigo.shade50 : Colors.white,
                  border: Border.all(color: Colors.black12),
                  borderRadius: BorderRadius.circular(16),
                ),
                alignment: Alignment.center,
                child: SingleChildScrollView(
                  child: Text(
                    _flipped ? c.back : c.front,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (!_flipped)
              const Text(
                'Tap the card to reveal the answer',
                style: TextStyle(color: Colors.black54),
              ),
            const SizedBox(height: 24),
            if (_flipped && !rated)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _rateButton('again', Colors.red, _submitting, _rate),
                  _rateButton('hard', Colors.orange, _submitting, _rate),
                  _rateButton('good', Colors.blue, _submitting, _rate),
                  _rateButton('easy', Colors.green, _submitting, _rate),
                ],
              ),
            if (rated) _ratedPanel(),
          ],
        ),
      ),
    );
  }

  Widget _ratedPanel() {
    final m = _mastery;
    return Column(
      children: [
        Text(
          'Rated: $_ratedAs',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        if (m != null) ...[
          const SizedBox(height: 6),
          Text(
            m.masteryState,
            style: const TextStyle(
              color: Colors.black87,
              fontWeight: FontWeight.w600,
            ),
          ),
          // The daemon owns the real schedule; this is a local offline estimate
          // until the answer syncs.
          Text(
            'next review ~${m.intervalDays} '
            '${m.intervalDays == 1 ? 'day' : 'days'} (offline estimate)',
            style: const TextStyle(color: Colors.black54, fontSize: 12),
          ),
        ],
        const SizedBox(height: 6),
        _syncStatus(),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
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
          color: synced ? Colors.green.shade700 : Colors.amber.shade800,
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            synced ? 'Synced' : 'Saved — will sync when online',
            style: const TextStyle(color: Colors.black54),
          ),
        ),
      ],
    );
  }

  Widget _rateButton(
    String label,
    Color color,
    bool disabled,
    Future<void> Function(String) onRate,
  ) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
      ),
      onPressed: disabled ? null : () => onRate(label),
      child: Text(label),
    );
  }
}
