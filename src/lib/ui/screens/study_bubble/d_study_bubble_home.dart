import 'package:flutter/material.dart';
import 'package:cerebrum/api/bubbles_api.dart';
import 'package:cerebrum/services/note_store.dart';
import 'package:cerebrum/services/user_session.dart';
import 'package:cerebrum/ui/screens/home/gap_repository.dart';
import 'package:cerebrum/ui/screens/study_bubble/d_study_bubble_page.dart';
import 'package:cerebrum/ui/widgets/card_view.dart';

/// The study-bubbles grid page.
///
/// Answers "what should I study next?" at a glance:
///   - a "Continue where you left off" row for the most recently opened bubble
///   - a search/filter field over name + domains
///   - a responsive card grid (2-6 columns from available width, never a
///     hardcoded count)
///   - cards carry a real attention rail from GapRepository (neutral / amber
///     / red) plus note counts and last-updated facts
///
/// Honesty rules: attention colors come from the gap rollup only; note
/// counts come from the daemon's note_count (server truth) with a local
/// NoteStore fallback; when a bubble has no notes the chip is hidden rather
/// than showing a fabricated "0".
class DStudyBubbleHome extends StatefulWidget {
  final Function(Map<String, dynamic> bubble) onOpenBubble;
  const DStudyBubbleHome({super.key, required this.onOpenBubble});

  @override
  State<DStudyBubbleHome> createState() => _DStudyBubbleHomeState();
}

class _DStudyBubbleHomeState extends State<DStudyBubbleHome> {
  List<Map<String, dynamic>> bubbles = [];
  bool _loading = true;
  String? _error;
  String _query = '';
  final TextEditingController _searchController = TextEditingController();

  /// bubbleId -> attention score, from GapRepository's last-known rollup.
  Map<String, int> _attentionByBubble = const {};

  /// bubbleId -> note facts (count + most recent update).
  ///
  /// The count is SERVER truth (daemon's note_count, computed from the notes
  /// dir) — the local index is a partial cache and under-reports notes that
  /// were never synced to this device. Local NoteStore only stands in when the
  /// daemon didn't supply the field (older daemon / parser keeps it optional).
  Map<String, ({int count, DateTime? lastUpdated})> _noteMeta = const {};

  /// The most recently opened bubble, shown as the resume row. null until a
  /// stored id exists AND the bubble is still in the fetched list.
  Map<String, dynamic>? _resumeBubble;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await BubblesApi.fetchBubbles();
      final list =
          data
              .whereType<Map>()
              .map((b) => Map<String, dynamic>.from(b))
              .toList();

      final attention = await _loadAttention();
      final noteMeta = await _loadNoteMeta(list);
      final resume = await _loadResumeBubble(list);

      if (!mounted) return;
      setState(() {
        bubbles = list;
        _attentionByBubble = attention;
        _noteMeta = noteMeta;
        _resumeBubble = resume;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<Map<String, int>> _loadAttention() async {
    try {
      final cached = await const LiveGapRepository().cached();
      return {for (final e in cached.entries) e.key: e.value.attention};
    } catch (_) {
      // No gap data yet. Rails stay neutral rather than guessing.
      return const {};
    }
  }

  Future<Map<String, ({int count, DateTime? lastUpdated})>> _loadNoteMeta(
    List<Map<String, dynamic>> list,
  ) async {
    final meta = <String, ({int count, DateTime? lastUpdated})>{};
    for (final b in list) {
      final id = b['id']?.toString();
      if (id == null) continue;

      // 1) Server truth: daemon counts from the notes dir. Prefer it.
      final serverCount = b['note_count'];
      if (serverCount is int && serverCount >= 0) {
        meta[id] = (count: serverCount, lastUpdated: null);
        continue;
      }

      // 2) Fallback: older daemon / field absent — local cache stands in.
      try {
        final notes = await NoteStore.listNotes(id);
        DateTime? last;
        for (final n in notes) {
          final raw = n['updated_at'];
          final t = raw is String ? DateTime.tryParse(raw) : null;
          if (t != null && (last == null || t.isAfter(last))) last = t;
        }
        meta[id] = (count: notes.length, lastUpdated: last);
      } catch (_) {
        // One bubble failing its local read must not break the grid.
      }
    }
    return meta;
  }

  Future<Map<String, dynamic>?> _loadResumeBubble(
    List<Map<String, dynamic>> list,
  ) async {
    final storedId = await UserSession.getLastOpenedBubble();
    if (storedId == null || storedId.isEmpty) return null;
    for (final b in list) {
      if (b['id']?.toString() == storedId) return b;
    }
    return null;
  }

  /// Ring rail color from the real attention score (same thresholds as the
  /// home-page summary: 1-3 amber, 4+ red).
  Color _ringColor(String? bubbleId) {
    final attention = bubbleId == null ? null : _attentionByBubble[bubbleId];
    if (attention == null || attention == 0) {
      return const Color(0xFFB9B4CC);
    }
    if (attention <= 3) {
      return const Color(0xFFC9A24B);
    }
    return const Color(0xFFB3261E);
  }

  bool _matches(Map<String, dynamic> bubble, String query) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase();
    if ('${bubble['name'] ?? ''}'.toLowerCase().contains(q)) return true;
    final domains = bubble['domains'];
    if (domains is List) {
      return domains.any((d) => '$d'.toLowerCase().contains(q));
    }
    return false;
  }

  List<Map<String, dynamic>> get _visibleBubbles {
    if (_query.isEmpty) return bubbles;
    return bubbles.where((b) => _matches(b, _query)).toList();
  }

  void _openBubble(Map<String, dynamic> bubble) {
    UserSession.saveLastOpenedBubble(bubble['id']?.toString());
    widget.onOpenBubble(bubble);
  }

  void _addBubbleWidget() async {
    final newBubble = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DStudyBubblePage(addMode: true)),
    );

    // When creation page returns a bubble
    if (newBubble != null && mounted) {
      setState(() => bubbles.insert(0, Map<String, dynamic>.from(newBubble)));
    }
  }

  Future<void> _deleteBubble(Map<String, dynamic> bubble) async {
    final bubbleId = bubble['id']?.toString();
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (BuildContext dialogContext) => AlertDialog(
            title: const Text("Delete Study Bubble"),
            content: const Text(
              "Are you sure you want to delete this study bubble?",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text(
                  "Delete",
                  style: TextStyle(color: Colors.red),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text("Cancel"),
              ),
            ],
          ),
    );

    if (confirm != true || bubbleId == null) return;

    try {
      await BubblesApi.deleteBubble(bubbleId);
      final updated = await BubblesApi.fetchBubbles();
      if (!mounted) return;
      setState(() {
        bubbles =
            updated
                .whereType<Map>()
                .map((b) => Map<String, dynamic>.from(b))
                .toList();
        if (_resumeBubble?['id']?.toString() == bubbleId) {
          _resumeBubble = null;
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$e")));
    }
  }

  Future<void> _editBubble(Map<String, dynamic> bubble) async {
    final id = bubble['id']?.toString();
    if (id == null) return;

    final nameCtrl = TextEditingController(
      text: (bubble['name'] as String?) ?? '',
    );
    final descCtrl = TextEditingController(
      text: (bubble['description'] as String?) ?? '',
    );

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Edit Study Bubble"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: "Name"),
            ),
            TextField(
              controller: descCtrl,
              decoration: const InputDecoration(labelText: "Description"),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text("Save"),
          ),
        ],
      ),
    );

    if (saved != true) return;
    if (!mounted) return;

    final name = nameCtrl.text.trim();
    final description = descCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Name can't be empty")));
      return;
    }

    try {
      await BubblesApi.updateBubble(
        bubbleId: id,
        name: name,
        description: description,
      );
      if (!mounted) return;
      // Reflect immediately without a full refetch.
      setState(() {
        bubble['name'] = name;
        bubble['description'] = description;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Study Bubbles")),
      floatingActionButton: FloatingActionButton(
        onPressed: _addBubbleWidget,
        tooltip: 'Create study bubble',
        child: const Icon(Icons.add),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _query = value),
              decoration: const InputDecoration(
                hintText: 'Search bubbles…',
                prefixIcon: Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          if (_resumeBubble != null && _query.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: _ResumeBubbleRow(
                bubble: _resumeBubble!,
                onTap: () => _openBubble(_resumeBubble!),
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

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Couldn\'t load study bubbles.',
              style: TextStyle(color: Colors.red.shade700),
            ),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (bubbles.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bubble_chart, size: 56, color: Color(0xFFB9B4CC)),
            const SizedBox(height: 12),
            const Text(
              'No study bubbles yet',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              'Create your first study bubble to start collecting notes.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ],
        ),
      );
    }

    final visible = _visibleBubbles;
    if (visible.isEmpty) {
      return Center(
        child: Text(
          'No bubbles match "${_query.trim()}".',
          style: TextStyle(color: Colors.grey.shade600),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(20),
      child: RefreshIndicator(
        onRefresh: _load,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // 200px is the minimum comfortable card width; grow columns only
            // when the window actually has the room.
            final maxColumns = (constraints.maxWidth / 200).floor().clamp(2, 6);
            final columns = maxColumns.clamp(1, visible.length);

            return GridView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: visible.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: 20,
                mainAxisSpacing: 20,
                mainAxisExtent: 220,
              ),
              itemBuilder: (context, index) {
                final bubble = visible[index];
                final id = bubble['id']?.toString();
                final meta = _noteMeta[id];

                return CardView(
                  data: bubble,
                  accentColor: _ringColor(id),
                  noteCount: meta?.count,
                  lastUpdated: meta?.lastUpdated,
                  onTap: () => _openBubble(bubble),
                  onDelete: () => _deleteBubble(bubble),
                  onEdit: () => _editBubble(bubble),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// "Continue where you left off" row: the most recently opened bubble with a
/// one-tap resume. Hidden entirely when the stored bubble is gone.
class _ResumeBubbleRow extends StatelessWidget {
  final Map<String, dynamic> bubble;
  final VoidCallback onTap;

  const _ResumeBubbleRow({required this.bubble, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF2A2A30),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFF6C4FCE),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.play_arrow,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CONTINUE WHERE YOU LEFT OFF',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 10,
                        letterSpacing: 1.1,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${bubble['name'] ?? 'Study bubble'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
