import 'package:flutter/material.dart';
import 'package:cerebrum/models/engram_models.dart';
import 'package:cerebrum/services/engram_attempt_store.dart';
import 'package:cerebrum/services/engram_sync_service.dart';
import 'package:cerebrum/services/offline_mastery.dart';

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

  Future<void> _loadExisting() async {
    final mastery = await OfflineMastery.masteryFor(widget.engram.id);
    final attempt = await EngramAttemptStore.latestForEngram(widget.engram.id);
    if (!mounted) return;

    Map<String, dynamic>? result;
    if (mastery != null && mastery.lastGrade != null) {
      result = mastery.toResult(correct: mastery.lastGrade == 'correct');
    } else if (attempt != null && attempt.isGraded) {
      result = attempt.result;
    }

    setState(() {
      _attempt = attempt;
      _selected = attempt?.payload['selected_option'] as String?;
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
        final mastery =
            await OfflineMastery.applyMcq(widget.engram.id, correct);
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

  @override
  Widget build(BuildContext context) {
    final c = _content;
    final locked = _attempt != null || _result != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Multiple Choice')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.stem,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
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
                        tileColor = Colors.green.shade50;
                        trailing =
                            Icon(Icons.check, color: Colors.green.shade700);
                      } else if (isSelected) {
                        tileColor = Colors.red.shade50;
                        trailing = Icon(Icons.close, color: Colors.red.shade700);
                      }
                    } else if (isSelected) {
                      tileColor = Colors.blue.shade50;
                    }
                    return Card(
                      color: tileColor,
                      child: ListTile(
                        leading: CircleAvatar(child: Text(opt.key)),
                        title: Text(opt.value),
                        selected: isSelected,
                        trailing: trailing,
                        onTap: locked
                            ? null
                            : () => setState(() => _selected = opt.key),
                      ),
                    );
                  }),
                  const SizedBox(height: 20),
                  if (_attempt == null && _result == null)
                    ElevatedButton(
                      onPressed:
                          _selected == null || _submitting ? null : _submit,
                      child: _submitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Submit'),
                    )
                  else if (_result != null)
                    _resultCard(_result!)
                  else
                    _pendingCard(),
                ],
              ),
            ),
    );
  }

  Widget _resultCard(Map<String, dynamic> r) {
    final correct = r['is_correct'] == true;
    return Card(
      color: correct ? Colors.green.shade50 : Colors.red.shade50,
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
              Text('Next review in ${r['interval_days']} '
                  '${r['interval_days'] == 1 ? 'day' : 'days'}'),
            const SizedBox(height: 8),
            _syncStatus(),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pendingCard() {
    return Card(
      color: Colors.amber.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.cloud_off, size: 20, color: Colors.amber.shade800),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Saved — will submit when online',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Your answer is stored on this device and will be scored once '
              "you're back online.",
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
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
        Icon(synced ? Icons.check : Icons.cloud_off,
            size: 16,
            color: synced ? Colors.green.shade700 : Colors.amber.shade800),
        const SizedBox(width: 4),
        Flexible(
          child: Text(synced ? 'Synced' : 'Saved — will sync when online',
              style: const TextStyle(color: Colors.black54)),
        ),
      ],
    );
  }
}
