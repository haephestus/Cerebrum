import 'package:cerebrum/common/keyboard_nav/keyboard_nav.dart';
import 'package:cerebrum/common/themes/theme_access.dart';
import 'package:flutter/material.dart';
import 'package:cerebrum/features/study_bubble/api/bubbles_api.dart';
import 'package:cerebrum/services/note_store.dart';
import 'package:cerebrum/services/user_session.dart';
import 'package:cerebrum/features/home/helpers/gap_repository.dart';
import 'package:cerebrum/features/study_bubble/widgets/card_view.dart';
import 'package:cerebrum/features/study_bubble/widgets/create_study_bubble_dialog.dart';

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
  final FocusNode? navFocusNode;
  final VoidCallback? onFocusRail;
  const DStudyBubbleHome({
    super.key,
    required this.onOpenBubble,
    this.navFocusNode,
    this.onFocusRail,
  });

  @override
  State<DStudyBubbleHome> createState() => _DStudyBubbleHomeState();
}

class _DStudyBubbleHomeState extends State<DStudyBubbleHome> {
  List<Map<String, dynamic>> bubbles = [];
  bool _loading = true;
  String? _error;
  String _query = '';
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode(debugLabel: 'bubbles-search');
  FocusNode? _ownNavFocusNode;
  FocusNode get _navFocusNode =>
      widget.navFocusNode ??
      (_ownNavFocusNode ??= FocusNode(debugLabel: 'bubbles-nav'));

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

  /// Keyboard-nav focus over [resume? , ...visibleBubbles].
  int _navIndex = 0;
  int _gridColumns = 1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _ownNavFocusNode?.dispose();
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
        _clampNavIndex();
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
      return context.cerebrum.status.neutralSoft;
    }
    if (attention <= 3) {
      return context.cerebrum.brand.accent;
    }
    return context.cerebrum.status.danger;
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

  bool get _showResume => _resumeBubble != null && _query.isEmpty;

  int get _navItemCount => (_showResume ? 1 : 0) + _visibleBubbles.length;

  void _clampNavIndex() {
    final count = _navItemCount;
    if (count <= 0) {
      _navIndex = 0;
      return;
    }
    _navIndex = _navIndex.clamp(0, count - 1);
  }

  void _syncNavLayout(int columns) {
    _gridColumns = columns < 1 ? 1 : columns;
    _clampNavIndex();
  }

  void _moveNav(int delta) {
    if (_navItemCount <= 0) return;
    final next = (_navIndex + delta).clamp(0, _navItemCount - 1);
    if (next == _navIndex && delta < 0 && widget.onFocusRail != null) {
      widget.onFocusRail!();
      return;
    }
    setState(() => _navIndex = next);
  }

  void _moveNavVertical(int rowDelta) {
    if (_navItemCount <= 0) return;
    final resumeOffset = _showResume ? 1 : 0;
    setState(() {
      if (_navIndex < resumeOffset) {
        // On resume row: down enters grid at first cell, up stays.
        if (rowDelta > 0 && _navItemCount > resumeOffset) {
          _navIndex = resumeOffset;
        }
      } else {
        final gridIndex = _navIndex - resumeOffset;
        final targetGrid = gridIndex + rowDelta * _gridColumns;
        if (targetGrid < 0) {
          _navIndex = _showResume ? 0 : 0;
        } else {
          final maxGrid = _visibleBubbles.length - 1;
          _navIndex = resumeOffset + targetGrid.clamp(0, maxGrid);
        }
      }
    });
  }

  void _activateNavIndex() {
    if (_navItemCount <= 0) return;
    final resumeOffset = _showResume ? 1 : 0;
    if (_navIndex < resumeOffset) {
      _openBubble(_resumeBubble!);
      return;
    }
    final bubble = _visibleBubbles[_navIndex - resumeOffset];
    _openBubble(bubble);
  }

  void _focusSearch() {
    _searchFocusNode.requestFocus();
  }

  void _handleNavBack() {
    if (_searchFocusNode.hasFocus) {
      _searchFocusNode.unfocus();
      _navFocusNode.requestFocus();
    } else {
      _navFocusNode.requestFocus();
    }
  }

  void _openBubble(Map<String, dynamic> bubble) {
    UserSession.saveLastOpenedBubble(bubble['id']?.toString());
    widget.onOpenBubble(bubble);
  }

  void _addBubbleWidget() async {
    final newBubble = await showCreateStudyBubbleDialog(context);

    // When creation returns a bubble
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
                child: Text(
                  "Delete",
                  style: TextStyle(color: context.cerebrum.status.danger),
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
        _clampNavIndex();
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
      builder:
          (dialogContext) => AlertDialog(
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
      body: KeyboardNavScope(
        focusNode: _navFocusNode,
        onUp: () => _moveNavVertical(-1),
        onDown: () => _moveNavVertical(1),
        onLeft: () => _moveNav(-1),
        onRight: () => _moveNav(1),
        onTop: () => setState(() => _navIndex = 0),
        onBottom:
            () => setState(() {
              if (_navItemCount > 0) _navIndex = _navItemCount - 1;
            }),
        onActivate: _activateNavIndex,
        onSearch: _focusSearch,
        onBack: _handleNavBack,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                onChanged:
                    (value) => setState(() {
                      _query = value;
                      _clampNavIndex();
                    }),
                decoration: const InputDecoration(
                  hintText: 'Search bubbles… (/ to focus)',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            if (_showResume)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: _ResumeBubbleRow(
                  bubble: _resumeBubble!,
                  focused: _navFocusNode.hasFocus && _navIndex == 0,
                  onTap: () => _openBubble(_resumeBubble!),
                ),
              ),
            Expanded(child: _buildBody()),
          ],
        ),
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
              style: TextStyle(color: context.cerebrum.status.dangerDeep),
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
            Icon(
              Icons.bubble_chart,
              size: 56,
              color: context.cerebrum.status.neutralSoft,
            ),
            const SizedBox(height: 12),
            const Text(
              'No study bubbles yet',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              'Create your first study bubble to start collecting notes.',
              style: TextStyle(
                color: context.cerebrum.text.muted,
                fontSize: 13,
              ),
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
          style: TextStyle(color: context.cerebrum.text.muted),
        ),
      );
    }

    final resumeOffset = _showResume ? 1 : 0;

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
            _syncNavLayout(columns);

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
                final focused =
                    _navFocusNode.hasFocus && _navIndex == resumeOffset + index;

                return CardView(
                  data: bubble,
                  accentColor: _ringColor(id),
                  noteCount: meta?.count,
                  lastUpdated: meta?.lastUpdated,
                  focused: focused,
                  onTap: () {
                    setState(() => _navIndex = resumeOffset + index);
                    _openBubble(bubble);
                  },
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
  final bool focused;

  const _ResumeBubbleRow({
    required this.bubble,
    required this.onTap,
    this.focused = false,
  });

  @override
  Widget build(BuildContext context) {
    final focusBorderColor =
        focused ? context.cerebrum.brand.accent : Colors.transparent;

    return Material(
      color: context.cerebrum.surface.cardSurface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: focusBorderColor, width: 2),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: context.cerebrum.brand.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.play_arrow,
                  color: context.cerebrum.text.onDark,
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
                        color: context.cerebrum.text.onDark.withValues(
                          alpha: 0.45,
                        ),
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
                      style: TextStyle(
                        color: context.cerebrum.text.onDark,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: context.cerebrum.text.onDark.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
