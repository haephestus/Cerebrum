import 'dart:io';

import 'package:cerebrum/services/note_store.dart';
import 'package:cerebrum/services/storage_paths.dart';
import 'package:cerebrum/ui/screens/editor/editor_scaffold.dart';
import 'package:flutter/material.dart';

import 'gap_models.dart';
import 'gap_repository.dart';

/// Home's primary "continue work" surface.
///
/// Shows two independent resume points:
///   - the most recently edited note
///   - a suggested-reading item pulled from GapRepository.cached()
///
/// Both are local reads and silently empty if there is nothing grounded
/// to show.
class Quickview extends StatefulWidget {
  final GapRepository gapRepository;

  const Quickview({super.key, this.gapRepository = const LiveGapRepository()});

  @override
  State<Quickview> createState() => _QuickviewState();
}

class _RecentNote {
  final String bubbleId;
  final String noteId;
  final String title;
  final DateTime updatedAt;

  const _RecentNote({
    required this.bubbleId,
    required this.noteId,
    required this.title,
    required this.updatedAt,
  });
}

class _ReadingSuggestion {
  final GapItem item;
  final GapEvidence evidence;

  const _ReadingSuggestion({required this.item, required this.evidence});
}

class _QuickviewState extends State<Quickview> with WidgetsBindingObserver {
  _RecentNote? _recent;
  _ReadingSuggestion? _reading;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _load();
    }
  }

  Future<void> _load() async {
    final results = await Future.wait([
      _findMostRecentNote(),
      _findReadingSuggestion(),
    ]);

    if (!mounted) return;

    setState(() {
      _recent = results[0] as _RecentNote?;
      _reading = results[1] as _ReadingSuggestion?;
      _loading = false;
    });
  }

  Future<_RecentNote?> _findMostRecentNote() async {
    final root = await StoragePaths.cerebrumRoot();
    final bubblesDir = Directory('${root.path}/bubbles');

    if (!await bubblesDir.exists()) return null;

    _RecentNote? best;

    await for (final entry in bubblesDir.list()) {
      if (entry is! Directory) continue;

      final bubbleId = entry.path.split(Platform.pathSeparator).last;

      final notes = await NoteStore.listNotes(bubbleId);

      for (final n in notes) {
        final updatedRaw = n['updated_at'] as String?;
        final updated =
            updatedRaw == null ? null : DateTime.tryParse(updatedRaw);

        if (updated == null) continue;

        final noteId = n['note_id'] as String?;
        if (noteId == null) continue;

        if (best == null || updated.isAfter(best.updatedAt)) {
          best = _RecentNote(
            bubbleId: bubbleId,
            noteId: noteId,
            title: n['title']?.toString() ?? 'Untitled',
            updatedAt: updated,
          );
        }
      }
    }

    return best;
  }

  /// Picks a suggested-reading gap item from the cached rollup.
  ///
  /// "Most recent" here is approximated by [GapEvidence.analysisVersion]
  /// because that is the only ordering signal currently available.
  Future<_ReadingSuggestion?> _findReadingSuggestion() async {
    final cached = await widget.gapRepository.cached();

    _ReadingSuggestion? best;

    for (final summary in cached.values) {
      for (final item in summary.items) {
        if (item.kind != GapKind.suggestedReading) continue;
        if (item.evidence.isEmpty) continue;

        final evidence = item.evidence.first;

        final candidateVersion = evidence.analysisVersion?.toDouble() ?? -1;

        final bestVersion = best?.evidence.analysisVersion?.toDouble() ?? -1;

        if (best == null || candidateVersion > bestVersion) {
          best = _ReadingSuggestion(item: item, evidence: evidence);
        }
      }
    }

    return best;
  }

  Future<void> _resume() async {
    final recent = _recent;

    if (recent == null) return;

    final fullNote = await NoteStore.readNote(recent.bubbleId, recent.noteId);

    if (fullNote == null || !mounted) return;

    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => EditorScaffold(note: fullNote)));

    // Editing the note changes its updated_at; refresh what we show.
    _load();
  }

  /// TODO: wire this to the Syncfusion PDF viewer once it is in the
  /// project. Until then, be honest about not being able to open it.
  void _openReading() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          "Opening reading material isn't wired up yet — "
          'needs the PDF viewer integration.',
        ),
      ),
    );
  }

  static String _timeAgo(DateTime updatedAt) {
    final diff = DateTime.now().difference(updatedAt);

    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';

    return '${(diff.inDays / 7).floor()}w ago';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            color: Colors.black,
            child: const Text(
              'Where You Left Off',
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final recent = _recent;
    final reading = _reading;

    if (recent == null && reading == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.note_alt_outlined,
              size: 56,
              color: Color(0xFF8E8E93),
            ),
            const SizedBox(height: 16),
            const Text(
              'No notes yet',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Create a note inside a study bubble and it will show up here.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (recent != null)
            _RecentNoteCard(
              recent: recent,
              onTap: _resume,
              timeAgo: _timeAgo(recent.updatedAt),
            ),

          if (recent != null && reading != null) ...[
            const SizedBox(height: 20),
            const Divider(height: 1),
            const SizedBox(height: 20),
          ],

          if (reading != null)
            _ReadingCard(reading: reading, onTap: _openReading),
        ],
      ),
    );
  }
}

class _RecentNoteCard extends StatefulWidget {
  final _RecentNote recent;
  final VoidCallback onTap;
  final String timeAgo;

  const _RecentNoteCard({
    required this.recent,
    required this.onTap,
    required this.timeAgo,
  });

  @override
  State<_RecentNoteCard> createState() => _RecentNoteCardState();
}

class _RecentNoteCardState extends State<_RecentNoteCard> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.recent.title,
                  // add  the type of file or data this pulls from?
                  // like recent.title note or suggested reading, right should
                  // be able to continue the suggested reading
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

              const SizedBox(width: 12),

              AnimatedSwitcher(
                duration: const Duration(milliseconds: 120),
                transitionBuilder: (child, animation) {
                  return FadeTransition(opacity: animation, child: child);
                },
                child: Text(
                  _hovering ? 'Click to continue' : 'Edited ${widget.timeAgo}',
                  key: ValueKey(_hovering),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: _hovering ? FontWeight.w600 : FontWeight.normal,
                    color: _hovering ? const Color(0xFF6C4FCE) : Colors.black45,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReadingCard extends StatelessWidget {
  final _ReadingSuggestion reading;
  final VoidCallback onTap;

  const _ReadingCard({required this.reading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Continue reading',
          style: TextStyle(fontSize: 13, color: Colors.black54),
        ),

        const SizedBox(height: 8),

        Text(
          reading.item.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),

        if (reading.item.detail != null &&
            reading.item.detail!.trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            reading.item.detail!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, color: Colors.black54),
          ),
        ],

        const SizedBox(height: 4),

        Text(
          'Suggested from ${reading.evidence.noteTitle}',
          style: const TextStyle(fontSize: 12, color: Colors.black45),
        ),

        const SizedBox(height: 16),

        OutlinedButton.icon(
          onPressed: onTap,
          icon: const Icon(Icons.menu_book_outlined, size: 18),
          label: const Text('Open reading'),
        ),
      ],
    );
  }
}
