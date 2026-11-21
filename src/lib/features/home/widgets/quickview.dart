import 'dart:async';
import 'dart:io';
import 'package:cerebrum/common/keyboard_nav/keyboard_nav.dart';
import 'package:cerebrum/features/reader/reader.dart';
import 'package:cerebrum/common/themes/theme_access.dart';
import 'package:cerebrum/features/learning_center/api/suggested_reading_api.dart';
import 'package:http/http.dart' as http;
import 'package:cerebrum/services/note_store.dart';
import 'package:cerebrum/services/storage_paths.dart';
import 'package:cerebrum/features/editor/editor_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../models/gap_models.dart';
import '../helpers/gap_repository.dart';

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
  final FocusNode? focusNode;

  const Quickview({
    super.key,
    this.gapRepository = const LiveGapRepository(),
    this.focusNode,
  });

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
  int _navIndex = 0;

  FocusNode? _ownFocusNode;
  FocusNode get _focusNode =>
      widget.focusNode ??
      (_ownFocusNode ??= FocusNode(debugLabel: 'quickview-nav'));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ownFocusNode?.dispose();
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
      _navIndex = 0;
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

  /// Opens a suggested reading.
  ///
  /// The canonical suggestion row already carries the durable document
  /// identity (`file_fingerprint`) and best-hit page, so open straight there.
  /// Only a bare citation (no fingerprint) needs the daemon, and it is
  /// resolved BY ITS OWN TEXT — not by re-running the note-seeded suggestion
  /// search, which answers a different question and used to open whatever the
  /// note's weak areas happened to match.
  Future<void> _openReading(_ReadingSuggestion suggestion) async {
    final evidence = suggestion.evidence;
    final link = evidence.sourceLink?.trim();

    // 1. Canonical row: open the exact document + page directly.
    final knownFingerprint = evidence.fileFingerprint?.trim();
    if (knownFingerprint != null && knownFingerprint.isNotEmpty) {
      _openReader(knownFingerprint, page: evidence.page);
      return;
    }

    if (link == null || link.isEmpty) {
      _snack('No reading source available');
      return;
    }

    // 2. Web URL
    if (link.startsWith('http://') || link.startsWith('https://')) {
      await launchUrl(Uri.parse(link));
      return;
    }

    // 3. Bare KB fingerprint (64 hex chars)
    if (RegExp(r'^[0-9a-f]{64}$').hasMatch(link)) {
      _openReader(link, page: evidence.page);
      return;
    }

    // 4. Citation text like "CLRS": resolve by the citation itself.
    try {
      final match = await SuggestedReadingApi.resolve(
        query: link,
        noteId: evidence.noteId,
      );

      final fingerprint = match?.fileFingerprint;
      if (fingerprint != null && fingerprint.isNotEmpty) {
        _openReader(fingerprint, page: match?.page ?? evidence.page);
        return;
      }

      // Daemon answered and the KB holds no visible document for this
      // citation: it is a real bibliographic reference, not a KB file.
      _snack('"$link" isn\'t in your knowledge base');
    } on SocketException catch (e) {
      // Daemon not running / wrong port / network unreachable. Do NOT report
      // this as a missing file — the user was misled by that mask.
      debugPrint('Reading lookup failed (daemon unreachable): $e');
      _snack(
        'Can\'t reach the knowledge-base daemon. Start it, then tap '
        '"Open reading" again.',
      );
    } on http.ClientException catch (e) {
      debugPrint('Reading lookup failed (daemon unreachable): $e');
      _snack(
        'Can\'t reach the knowledge-base daemon. Start it, then tap '
        '"Open reading" again.',
      );
    } on TimeoutException catch (e) {
      debugPrint('Reading lookup timed out: $e');
      _snack(
        'The knowledge-base daemon timed out. Start it, then tap '
        '"Open reading" again.',
      );
    } catch (e) {
      debugPrint('Reading lookup failed: $e');
      _snack(
        'Couldn\'t check your knowledge base. The daemon may be offline or '
        'returned an error.',
      );
    }
  }

  void _openReader(String fingerprint, {int? page}) {
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Reader(fileFingerprint: fingerprint, page: page),
      ),
    );
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  static String _timeAgo(DateTime updatedAt) {
    final diff = DateTime.now().difference(updatedAt);

    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';

    return '${(diff.inDays / 7).floor()}w ago';
  }

  int get _actionCount =>
      (_recent != null ? 1 : 0) + (_reading != null ? 1 : 0);

  void _activateNav() {
    if (_actionCount == 0) return;
    var idx = _navIndex.clamp(0, _actionCount - 1);
    if (_recent != null) {
      if (idx == 0) {
        _resume();
        return;
      }
      idx -= 1;
    }
    if (_reading != null && idx == 0) {
      _openReading(_reading!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final focused = _focusNode.hasFocus;
    return KeyboardNavScope(
      focusNode: _focusNode,
      onUp:
          () => setState(() {
            if (_navIndex > 0) _navIndex--;
          }),
      onDown:
          () => setState(() {
            if (_navIndex < _actionCount - 1) _navIndex++;
          }),
      onActivate: _activateNav,
      child: GestureDetector(
        onTap: () => _focusNode.requestFocus(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color:
                  focused ? context.cerebrum.brand.accent : Colors.transparent,
              width: 2,
            ),
          ),
          child: Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  color: context.cerebrum.text.strong,
                  child: Text(
                    'Where You Left Off',
                    style: TextStyle(
                      color: context.cerebrum.text.onAccent,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Expanded(child: _buildBody()),
              ],
            ),
          ),
        ),
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
            Icon(
              Icons.note_alt_outlined,
              size: 56,
              color: context.cerebrum.text.faint,
            ),
            const SizedBox(height: 16),
            const Text(
              'No notes yet',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Create a note inside a study bubble and it will show up here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: context.cerebrum.text.muted,
              ),
            ),
          ],
        ),
      );
    }

    final hasFocus = _focusNode.hasFocus;
    var actionIndex = 0;
    final recentIndex = recent != null ? actionIndex++ : -1;
    final readingIndex = reading != null ? actionIndex++ : -1;

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
              focused: hasFocus && _navIndex == recentIndex,
            ),

          if (recent != null && reading != null) ...[
            const SizedBox(height: 20),
            const Divider(height: 1),
            const SizedBox(height: 20),
          ],

          if (reading != null)
            _ReadingCard(
              reading: reading,
              onTap: () => _openReading(reading),
              focused: hasFocus && _navIndex == readingIndex,
            ),
        ],
      ),
    );
  }
}

class _RecentNoteCard extends StatefulWidget {
  final _RecentNote recent;
  final VoidCallback onTap;
  final String timeAgo;
  final bool focused;

  const _RecentNoteCard({
    required this.recent,
    required this.onTap,
    required this.timeAgo,
    this.focused = false,
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
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color:
                  widget.focused
                      ? context.cerebrum.brand.accent
                      : Colors.transparent,
              width: 2,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.recent.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
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
                  _hovering ? 'Click to open' : 'Edited ${widget.timeAgo}',
                  key: ValueKey(_hovering),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: _hovering ? FontWeight.w600 : FontWeight.normal,
                    color:
                        _hovering
                            ? context.cerebrum.brand.primary
                            : context.cerebrum.text.faint,
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
  final bool focused;

  const _ReadingCard({
    required this.reading,
    required this.onTap,
    this.focused = false,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: focused ? context.cerebrum.brand.accent : Colors.transparent,
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Continue reading',
            style: TextStyle(fontSize: 13, color: context.cerebrum.text.muted),
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
              style: TextStyle(
                fontSize: 13,
                color: context.cerebrum.text.muted,
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            'Suggested from ${reading.evidence.noteTitle}',
            style: TextStyle(fontSize: 12, color: context.cerebrum.text.faint),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onTap,
            icon: const Icon(Icons.menu_book_outlined, size: 18),
            label: const Text('Open reading'),
          ),
        ],
      ),
    );
  }
}
